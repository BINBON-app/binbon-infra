remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = { bucket = "binbon-bootstrap-tfstate-20260820142237684300000001", key = "${local.env.locals.environment}/${local.env.locals.region}/${basename(get_original_terragrunt_dir())}/terraform.tfstate", region = "eu-central-1", encrypt = true, dynamodb_table = "binbon-bootstrap-tf-lock"
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
    aurora_endpoint = "mock", aurora_secret_arn = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:mock", aurora_database_name = "app", redis_endpoint = "mock",
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

  aurora_endpoint      = dependency.data.outputs.aurora_endpoint
  aurora_secret_arn    = dependency.data.outputs.aurora_secret_arn
  aurora_database_name = dependency.data.outputs.aurora_database_name
  redis_endpoint       = dependency.data.outputs.redis_endpoint

  kafka_brokers = dependency.redpanda.outputs.kafka_private_seed_brokers

  clickhouse_url       = dependency.clickhouse.outputs.https_url
  clickhouse_database  = "binbon_analytics"

  opensearch_endpoint = "https://${dependency.opensearch.outputs.endpoint}"

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
