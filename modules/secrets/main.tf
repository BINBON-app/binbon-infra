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
