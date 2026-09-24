# Aurora's master user password is AWS-managed (manage_master_user_password
# = true in the data module), so it never lands in Terraform state directly -
# it lives in an RDS-generated Secrets Manager secret that must be read back
# here to compose a usable connection string.
data "aws_secretsmanager_secret_version" "aurora_master" {
  secret_id = var.aurora_secret_arn
}

locals {
  aurora_master = jsondecode(data.aws_secretsmanager_secret_version.aurora_master.secret_string)

  # binbon-backend-inventory.xlsx and deploy/compose/postgres-init/01-create-databases.sql
  # both establish database-per-service as the real design - each service gets
  # its own logical database on the shared Aurora cluster, not one shared "app"
  # database, so their independent sqlx migration histories can never collide.
  postgres_urls = {
    for service, dbname in var.postgres_service_databases :
    service => "postgres://${local.aurora_master.username}:${urlencode(local.aurora_master.password)}@${var.aurora_endpoint}:5432/${dbname}"
  }
  redis_url     = "redis://${var.redis_endpoint}:6379"
  kafka_brokers = join(",", var.kafka_brokers)

  postgres_secrets = {
    for service, url in local.postgres_urls :
    "DATABASE_URL_${service}" => url
  }

  infra_secrets = merge(local.postgres_secrets, {
    REDIS_URL        = local.redis_url
    KAFKA_BROKERS    = local.kafka_brokers

    CLICKHOUSE_URL      = var.clickhouse_url
    CLICKHOUSE_USER     = "default"
    CLICKHOUSE_PASSWORD = var.clickhouse_admin_password
    CLICKHOUSE_DATABASE = var.clickhouse_database

    OPENSEARCH_URL = var.opensearch_endpoint

    # Platform-wide shared secrets. Not infra-derived like the rest of this map -
    # they are generated once by scripts/bootstrap-secrets.sh and read back here,
    # so the same value reaches every service that needs it.
    JWT_SECRET       = var.jwt_secret
    INTERNAL_API_KEY = var.internal_api_key

    # media-service's key for signed HLS URLs; also from bootstrap-secrets.sh.
    MEDIA_URL_SIGNING_KEY = var.media_url_signing_key

    SCYLLA_NODES    = var.keyspaces_endpoint
    SCYLLA_KEYSPACE = var.keyspaces_keyspace_name
    SCYLLA_USERNAME = var.keyspaces_username
    SCYLLA_PASSWORD = var.keyspaces_password

    S3_BUCKET        = var.s3_bucket
    S3_ENDPOINT      = "https://s3.${var.s3_region}.amazonaws.com"
    S3_REGION        = var.s3_region
    S3_ACCESS_KEY    = var.s3_access_key_id
    S3_SECRET_KEY    = var.s3_secret_access_key
    CDN_BASE_URL     = "https://${var.cdn_domain_name}"
  })
}

resource "aws_secretsmanager_secret" "infra" {
  name       = "${var.name}-infra-secrets"
  kms_key_id = var.kms_key_arn
  tags       = var.tags
}

resource "aws_secretsmanager_secret_version" "infra" {
  secret_id     = aws_secretsmanager_secret.infra.id
  secret_string = jsonencode(local.infra_secrets)
}

# Create one database per service inside the Aurora cluster.
#
# Aurora comes up with a single database (aurora_database_name); each service
# expects its own, named in postgres_service_databases and baked into the
# DATABASE_URL composed above. Those databases used to be created by hand, so a
# fresh account brought up 20 crash-looping services with no hint in the
# codebase that the step existed. Deriving them from the same map that builds
# the URLs keeps the two from ever disagreeing.
#
# The RDS Data API is used rather than the postgresql provider because Aurora
# sits in a private subnet: a provider connection would fail for anyone not on
# the VPN, whereas the Data API goes over the AWS API plane. The cost is a
# dependency on the AWS CLI wherever Terraform runs.
#
# CREATE DATABASE cannot run inside a transaction, so it is issued on its own.
# The || true swallows the duplicate error, which makes re-apply idempotent.
resource "terraform_data" "service_database" {
  for_each = var.create_service_databases ? var.postgres_service_databases : {}

  # Recreate only if the database name itself changes; renaming a service's
  # database is a data migration, not something to trigger silently.
  triggers_replace = [each.value]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -uo pipefail
      out=$(aws rds-data execute-statement \
              --region "${data.aws_region.current.name}" \
              --resource-arn "${var.aurora_cluster_arn}" \
              --secret-arn "${var.aurora_secret_arn}" \
              --database postgres \
              --sql 'CREATE DATABASE "${each.value}"' 2>&1) || {
        if printf '%s' "$out" | grep -qi 'already exists'; then
          echo 'database ${each.value} already exists'
          exit 0
        fi
        printf 'failed to create database ${each.value}: %s\n' "$out" >&2
        exit 1
      }
      echo 'created database ${each.value}'
    EOT
  }
}

data "aws_region" "current" {}
