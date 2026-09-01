remote_state {
backend="s3"
 

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
config={bucket="binbon-bootstrap-tfstate-20260822072816113700000001",key = "${local.env.locals.environment}/${local.env.locals.region}/${basename(get_original_terragrunt_dir())}/terraform.tfstate",region="eu-central-1",encrypt=true,dynamodb_table="binbon-bootstrap-tf-lock"
} 
}
generate "provider" {
path="provider.tf"
 if_exists="overwrite_terragrunt"
 contents="provider \"aws\" { region = \"eu-central-1\" }" 
}
locals {
env=read_terragrunt_config(find_in_parent_folders("env.hcl"))
 tags={Project="binbon",Environment=local.env.locals.environment,ManagedBy="Terraform"
}
  # Which infra-derived secret keys (from the shared "<env>-infra-secrets"
  # Secrets Manager entry) each service actually reads, per its config.rs -
  # see binbon-backend-inventory.xlsx "ENV Arrays"/"ENV Detail" tabs.
  service_secret_keys = {
    "api-gateway"               = ["REDIS_URL"]
    "auth-service"              = ["DATABASE_URL", "KAFKA_BROKERS", "REDIS_URL"]
    "user-service"              = ["DATABASE_URL", "KAFKA_BROKERS", "REDIS_URL"]
    "device-service"            = ["DATABASE_URL", "REDIS_URL"]
    "rbac-service"              = ["DATABASE_URL", "REDIS_URL"]
    "media-service"             = ["DATABASE_URL", "KAFKA_BROKERS", "REDIS_URL", "S3_ACCESS_KEY", "S3_BUCKET", "S3_ENDPOINT", "S3_REGION", "S3_SECRET_KEY", "CDN_BASE_URL"]
    "video-processing-service"  = ["DATABASE_URL", "KAFKA_BROKERS", "REDIS_URL", "S3_ACCESS_KEY", "S3_BUCKET", "S3_ENDPOINT", "S3_REGION", "S3_SECRET_KEY", "CDN_BASE_URL"]
    "feed-service"              = ["KAFKA_BROKERS", "REDIS_URL", "SCYLLA_KEYSPACE", "SCYLLA_NODES", "SCYLLA_USERNAME", "SCYLLA_PASSWORD"]
    "engagement-service"        = ["KAFKA_BROKERS", "REDIS_URL", "SCYLLA_KEYSPACE", "SCYLLA_NODES", "SCYLLA_USERNAME", "SCYLLA_PASSWORD"]
    "recommendation-service"    = ["KAFKA_BROKERS", "REDIS_URL"]
    "comment-service"           = ["KAFKA_BROKERS", "REDIS_URL", "SCYLLA_KEYSPACE", "SCYLLA_NODES", "SCYLLA_USERNAME", "SCYLLA_PASSWORD"]
    "story-service"             = ["KAFKA_BROKERS", "REDIS_URL", "SCYLLA_KEYSPACE", "SCYLLA_NODES", "SCYLLA_USERNAME", "SCYLLA_PASSWORD"]
    "sticker-service"           = ["DATABASE_URL", "REDIS_URL"]
    "search-service"            = ["KAFKA_BROKERS", "OPENSEARCH_URL", "REDIS_URL"]
    "chat-service"              = ["KAFKA_BROKERS", "REDIS_URL", "SCYLLA_KEYSPACE", "SCYLLA_NODES", "SCYLLA_USERNAME", "SCYLLA_PASSWORD"]
    "presence-service"          = ["REDIS_URL"]
    "call-service"              = ["DATABASE_URL", "REDIS_URL"]
    "wallet-service"            = ["DATABASE_URL", "KAFKA_BROKERS", "REDIS_URL"]
    "payment-service"           = ["DATABASE_URL", "REDIS_URL"]
    "payout-service"            = ["DATABASE_URL", "REDIS_URL"]
    "live-service"              = ["DATABASE_URL", "REDIS_URL"]
    "notification-service"      = ["DATABASE_URL", "KAFKA_BROKERS", "REDIS_URL"]
    "analytics-service"         = ["CLICKHOUSE_DATABASE", "CLICKHOUSE_PASSWORD", "CLICKHOUSE_URL", "CLICKHOUSE_USER", "KAFKA_BROKERS", "REDIS_URL"]
    "admin-service"             = ["REDIS_URL"]
    "gift-service"              = ["DATABASE_URL", "KAFKA_BROKERS", "REDIS_URL"]
    "pk-service"                = ["DATABASE_URL", "KAFKA_BROKERS", "REDIS_URL"]
    "location-service"          = ["DATABASE_URL", "REDIS_URL"]
    "audit-service"             = ["DATABASE_URL", "KAFKA_BROKERS", "REDIS_URL"]
    "report-service"            = ["DATABASE_URL", "KAFKA_BROKERS", "REDIS_URL"]
    "moderation-service"        = ["DATABASE_URL", "KAFKA_BROKERS", "REDIS_URL"]
    "fraud-service"             = ["DATABASE_URL", "REDIS_URL"]
  }
  # Services on Amazon Keyspaces need SCYLLA_TLS=true (Keyspaces requires
  # TLS) - not a secret, just a fixed config flag.
  scylla_services = ["feed-service", "engagement-service", "comment-service", "story-service", "chat-service"]

  # The few services that make a synchronous HTTP/gRPC call to another
  # service (see binbon-backend-inventory.xlsx "Service Dependency Matrix"),
  # pointed at that service's ECS Service Connect DNS name
  # (http://<service-key>:<container_port>, see modules/ecs-services -
  # aws_service_discovery_http_namespace.this / service_connect_configuration).
  # Every other service's outbound traffic is async (Kafka via KAFKA_BROKERS),
  # which needs no per-pair wiring.
  internal_service_urls = {
    "payment-service" = { WALLET_SERVICE_URL = "http://wallet-service:8097" }
    "payout-service"  = { WALLET_SERVICE_URL = "http://wallet-service:8097" }
    "live-service"    = { WALLET_SERVICE_URL = "http://wallet-service:8097" }
    "admin-service" = {
      AUDIT_SERVICE_URL      = "http://audit-service:8107"
      REPORT_SERVICE_URL     = "http://report-service:8108"
      MODERATION_SERVICE_URL = "http://moderation-service:8109"
    }
    "auth-service" = { RBAC_GRPC_URL = "http://rbac-service:8084" }
  }
}
terraform {
source=dirname(find_in_parent_folders("modules/ecs-services/main.tf")) 
}
dependency "network" {
config_path="../network"
 mock_outputs={vpc_id="vpc-00000000",app_subnet_ids=["subnet-00000000","subnet-00000001"]
}
 mock_outputs_allowed_terraform_commands=["init","validate","plan","destroy"] 
}
dependency "foundation" {
config_path="../foundation"
 mock_outputs={kms_key_arn="arn:aws:kms:eu-central-1:123456789012:key/mock"
}
 mock_outputs_allowed_terraform_commands=["init","validate","plan","destroy"]
}
dependency "alb" {
config_path="../alb"
 mock_outputs={task_security_group_id="sg-00000000",listener_arn="arn:aws:elasticloadbalancing:eu-central-1:123456789012:listener/app/mock/mock"
}
 mock_outputs_allowed_terraform_commands=["init","validate","plan","destroy"] 
}
dependency "data" {
config_path="../data"
 mock_outputs={aurora_endpoint="mock",redis_endpoint="mock",aurora_secret_arn="arn:aws:secretsmanager:eu-central-1:123456789012:secret:mock",keyspace_name="mock"
}
 mock_outputs_allowed_terraform_commands=["init","validate","plan","destroy"] 
}
dependency "cognito" {
config_path="../cognito"
 mock_outputs={user_pool_id="eu-central-1_mock",client_id="mock-client-id",issuer_url="https://cognito-idp.eu-central-1.amazonaws.com/eu-central-1_mock"
}
 mock_outputs_allowed_terraform_commands=["init","validate","plan","destroy"] 
}
dependency "redpanda" {
  config_path = "../redpanda"

  mock_outputs = {
    cluster_api_url = "https://mock.redpanda.cloud"

    service_usernames = {
      for username, config in local.env.locals.redpanda.service_users :
      username => "mock-${username}"
    }
  }

  mock_outputs_allowed_terraform_commands = [
    "init",
    "validate",
    "plan",
    "destroy"
  ]
}
dependency "secrets" {
  config_path = "../secrets"
  mock_outputs = { secret_arn = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}
inputs = {
  name                   = "binbon-${local.env.locals.environment}"
  environment            = local.env.locals.environment
  vpc_id                 = dependency.network.outputs.vpc_id
  app_subnet_ids         = dependency.network.outputs.app_subnet_ids
  task_security_group_id = dependency.alb.outputs.task_security_group_id
  listener_arn           = dependency.alb.outputs.listener_arn
  kms_key_arn            = dependency.foundation.outputs.kms_key_arn

  services = {
    for name, service in local.env.locals.services :
    name => merge(service, {
      environment = merge(
        service.environment,
        {
          COGNITO_USER_POOL_ID = dependency.cognito.outputs.user_pool_id
          COGNITO_CLIENT_ID    = dependency.cognito.outputs.client_id
          COGNITO_ISSUER       = dependency.cognito.outputs.issuer_url
        },
        service.redpanda_user == null ? {} : {
          REDPANDA_SASL_USERNAME = dependency.redpanda.outputs.service_usernames[service.redpanda_user]
        },
        # SSL_CERT_FILE tells the vendored/statically-built OpenSSL (linked in
        # via the scylla "keyspaces" Cargo feature) where the runtime image's
        # CA bundle actually lives. The vendored build's compiled-in default
        # cert path doesn't match Ubuntu's /etc/ssl/certs, so without this,
        # set_default_verify_paths() finds no trusted CAs and every TLS
        # handshake to Amazon Keyspaces fails cert verification (surfacing as
        # a generic "Connection broken" IO error, not a cert error).
        contains(local.scylla_services, name) ? {
          SCYLLA_TLS    = "true"
          SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt"
          # Keyspaces schema (keyspace + tables) is provisioned by Terraform
          # (see modules/data: aws_keyspaces_keyspace/aws_keyspaces_table),
          # and the app's own IAM user intentionally has no cassandra:Create
          # grant. MIGRATE_ON_START defaults to true in the app, which makes
          # it try to self-bootstrap the schema on every start and crash with
          # a permissions error - must be forced false against Keyspaces.
          MIGRATE_ON_START = "false"
        } : {},
        lookup(local.internal_service_urls, name, {})
      )
      secret_arns = merge(
        service.secret_arns,
        {
          for key in lookup(local.service_secret_keys, name, []) :
          # DATABASE_URL is stored per-service (DATABASE_URL_<service>) in the
          # shared secret, since each service owns its own database - see
          # postgres_service_databases in components/secrets.hcl.
          key => key == "DATABASE_URL" ? "${dependency.secrets.outputs.secret_arn}:DATABASE_URL_${name}::" : "${dependency.secrets.outputs.secret_arn}:${key}::"
        }
      )
    })
  }

  tags = local.tags
}
