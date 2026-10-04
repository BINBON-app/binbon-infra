remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = { bucket = "binbon-bootstrap-tfstate-20261004100200286800000001", key = "${local.env.locals.environment}/${local.env.locals.region}/${basename(get_original_terragrunt_dir())}/terraform.tfstate", region = "eu-central-1", encrypt = true, dynamodb_table = "binbon-bootstrap-tf-lock"
  }
}
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = "provider \"aws\" { region = \"eu-central-1\" }"
}
locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  tags = { Project = "binbon", Environment = local.env.locals.environment, ManagedBy = "Terraform"
  }
  # Fetched directly from Secrets Manager rather than a manual TF_VAR export -
  # seeded once via scripts/bootstrap-secrets.sh, never from a local file.
  clickhouse_admin_password = run_cmd(
    "--terragrunt-quiet",
    "aws", "secretsmanager", "get-secret-value",
    "--secret-id", "binbon-${local.env.locals.environment}-clickhouse-admin-password",
    "--region", "eu-central-1",
    "--query", "SecretString",
    "--output", "text"
  )
  # Platform-wide shared secrets, seeded the same way. These are what stop every
  # service from falling back to the DEV_JWT_SECRET / "dev-internal-key" constants
  # compiled into the backend (and what unblocks APP_ENV=production, where those
  # fallbacks are a hard boot failure).
  jwt_secret = run_cmd(
    "--terragrunt-quiet",
    "aws", "secretsmanager", "get-secret-value",
    "--secret-id", "binbon-${local.env.locals.environment}-jwt-secret",
    "--region", "eu-central-1",
    "--query", "SecretString",
    "--output", "text"
  )
  internal_api_key = run_cmd(
    "--terragrunt-quiet",
    "aws", "secretsmanager", "get-secret-value",
    "--secret-id", "binbon-${local.env.locals.environment}-internal-api-key",
    "--region", "eu-central-1",
    "--query", "SecretString",
    "--output", "text"
  )
  media_url_signing_key = run_cmd(
    "--terragrunt-quiet",
    "aws", "secretsmanager", "get-secret-value",
    "--secret-id", "binbon-${local.env.locals.environment}-media-url-signing-key",
    "--region", "eu-central-1",
    "--query", "SecretString",
    "--output", "text"
  )
}
terraform {
  source = dirname(find_in_parent_folders("modules/secrets/main.tf"))
}
dependency "foundation" {
  config_path = "../foundation"
  mock_outputs = { kms_key_arn = "arn:aws:kms:eu-central-1:123456789012:key/mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}
dependency "data" {
  config_path = "../data"
  mock_outputs = {
    aurora_endpoint = "mock", aurora_secret_arn = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:mock", aurora_cluster_arn = "arn:aws:rds:eu-central-1:123456789012:cluster:mock", redis_endpoint = "mock",
    keyspace_name = "mock", keyspaces_endpoint = "mock:9142", keyspaces_username = "mock", keyspaces_password = "mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}
dependency "redpanda" {
  config_path = "../redpanda"
  mock_outputs = { kafka_private_seed_brokers = ["mock:9092"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}
dependency "clickhouse" {
  config_path = "../clickhouse"
  mock_outputs = { https_url = "https://mock:8443"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}
dependency "opensearch" {
  config_path = "../opensearch"
  mock_outputs = { endpoint = "mock.eu-central-1.es.amazonaws.com"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}
dependency "media" {
  config_path = "../media"
  mock_outputs = {
    bucket_name = "mock-bucket", cloudfront_domain_name = "mock.cloudfront.net",
    s3_access_key_id = "mock", s3_secret_access_key = "mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}
inputs = {
  name        = "binbon-${local.env.locals.environment}"
  kms_key_arn = dependency.foundation.outputs.kms_key_arn

  aurora_endpoint   = dependency.data.outputs.aurora_endpoint
  aurora_secret_arn  = dependency.data.outputs.aurora_secret_arn
  aurora_cluster_arn = dependency.data.outputs.aurora_cluster_arn
  redis_endpoint    = dependency.data.outputs.redis_endpoint

  # database-per-service (see deploy/compose/postgres-init/01-create-databases.sql
  # in the monorepo for the canonical list) - each service's sqlx migration
  # history lives in its own database, so they can never collide.
  postgres_service_databases = {
    "auth-service"         = "binbon_auth"
    "user-service"         = "binbon_user"
    "device-service"       = "binbon_device"
    "rbac-service"         = "binbon_rbac"
    "media-service"        = "binbon_media"
    "video-processing-service" = "binbon_video"
    "sticker-service"      = "binbon_sticker"
    "call-service"         = "binbon_calls"
    "wallet-service"       = "binbon_wallet"
    "payment-service"      = "binbon_payments"
    "payout-service"       = "binbon_payouts"
    "live-service"         = "binbon_live"
    "notification-service" = "binbon_notifications"
    "gift-service"         = "binbon_gifts"
    "pk-service"           = "binbon_pk"
    "location-service"     = "binbon_location"
    "audit-service"        = "binbon_audit"
    "report-service"       = "binbon_reports"
    "moderation-service"   = "binbon_moderation"
    "fraud-service"        = "binbon_fraud"
  }

  kafka_brokers = dependency.redpanda.outputs.kafka_private_seed_brokers

  clickhouse_url            = dependency.clickhouse.outputs.https_url
  clickhouse_database       = "binbon_analytics"
  clickhouse_admin_password = local.clickhouse_admin_password

  opensearch_endpoint = "https://${dependency.opensearch.outputs.endpoint}"

  jwt_secret       = local.jwt_secret
  internal_api_key = local.internal_api_key

  media_url_signing_key = local.media_url_signing_key

  keyspaces_endpoint      = dependency.data.outputs.keyspaces_endpoint
  keyspaces_keyspace_name = dependency.data.outputs.keyspace_name
  keyspaces_username      = dependency.data.outputs.keyspaces_username
  keyspaces_password      = dependency.data.outputs.keyspaces_password

  s3_bucket             = dependency.media.outputs.bucket_name
  s3_region             = local.env.locals.region
  s3_access_key_id      = dependency.media.outputs.s3_access_key_id
  s3_secret_access_key  = dependency.media.outputs.s3_secret_access_key
  cdn_domain_name       = dependency.media.outputs.cloudfront_domain_name

  tags = local.tags
}
