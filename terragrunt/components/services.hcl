remote_state {
backend="s3"
 

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
config={bucket=local.backend.locals.state_bucket,key = "${local.env.locals.environment}/${local.env.locals.region}/${basename(get_original_terragrunt_dir())}/terraform.tfstate",region=local.backend.locals.state_region,encrypt=true,dynamodb_table=local.backend.locals.lock_table
} 
}
generate "provider" {
path="provider.tf"
 if_exists="overwrite_terragrunt"
 contents=<<EOF
provider "aws" {
  region              = "eu-central-1"
  allowed_account_ids = ["${local.backend.locals.account_id}"]
}
EOF 
}
locals {
 backend=read_terragrunt_config(find_in_parent_folders("backend.hcl"))
env=read_terragrunt_config(find_in_parent_folders("env.hcl"))
 tags={Project="binbon",Environment=local.env.locals.environment,ManagedBy="Terraform"
}
  # Which keys from the shared "<env>-infra-secrets" Secrets Manager entry each
  # service actually reads, per its config.rs - see binbon-backend-inventory.xlsx
  # "ENV Arrays"/"ENV Detail" tabs.
  #
  # JWT_SECRET goes to every service that validates or mints an access token -
  # that is all of them EXCEPT api-gateway, which is a pure reverse proxy and
  # never touches a token (its config.rs has no JWT_SECRET at all). The key is a
  # symmetric HS256 secret, so these must all resolve to the same value.
  #
  # INTERNAL_API_KEY goes only to the services whose config.rs reads it, i.e.
  # those on either end of a privileged internal call.
  service_secret_keys = {
    "api-gateway"               = ["REDIS_URL"]
    "auth-service"              = ["DATABASE_URL", "INTERNAL_API_KEY", "JWT_SECRET", "KAFKA_BROKERS", "REDIS_URL"]
    "user-service"              = ["DATABASE_URL", "INTERNAL_API_KEY", "JWT_SECRET", "KAFKA_BROKERS", "REDIS_URL"]
    "device-service"            = ["DATABASE_URL", "INTERNAL_API_KEY", "JWT_SECRET", "REDIS_URL"]
    "rbac-service"              = ["DATABASE_URL", "INTERNAL_API_KEY", "JWT_SECRET", "REDIS_URL"]
    "media-service"             = ["DATABASE_URL", "INTERNAL_API_KEY", "JWT_SECRET", "KAFKA_BROKERS", "MEDIA_URL_SIGNING_KEY", "REDIS_URL", "S3_ACCESS_KEY", "S3_BUCKET", "S3_ENDPOINT", "S3_REGION", "S3_SECRET_KEY", "CDN_BASE_URL"]
    "video-processing-service"  = ["DATABASE_URL", "JWT_SECRET", "KAFKA_BROKERS", "REDIS_URL", "S3_ACCESS_KEY", "S3_BUCKET", "S3_ENDPOINT", "S3_REGION", "S3_SECRET_KEY", "CDN_BASE_URL"]
    "feed-service"              = ["INTERNAL_API_KEY", "JWT_SECRET", "KAFKA_BROKERS", "REDIS_URL", "SCYLLA_KEYSPACE", "SCYLLA_NODES", "SCYLLA_USERNAME", "SCYLLA_PASSWORD"]
    "engagement-service"        = ["JWT_SECRET", "KAFKA_BROKERS", "REDIS_URL", "SCYLLA_KEYSPACE", "SCYLLA_NODES", "SCYLLA_USERNAME", "SCYLLA_PASSWORD"]
    "recommendation-service"    = ["INTERNAL_API_KEY", "JWT_SECRET", "KAFKA_BROKERS", "REDIS_URL"]
    "comment-service"           = ["JWT_SECRET", "KAFKA_BROKERS", "REDIS_URL", "SCYLLA_KEYSPACE", "SCYLLA_NODES", "SCYLLA_USERNAME", "SCYLLA_PASSWORD"]
    "story-service"             = ["INTERNAL_API_KEY", "JWT_SECRET", "KAFKA_BROKERS", "REDIS_URL", "SCYLLA_KEYSPACE", "SCYLLA_NODES", "SCYLLA_USERNAME", "SCYLLA_PASSWORD"]
    "sticker-service"           = ["DATABASE_URL", "INTERNAL_API_KEY", "JWT_SECRET", "REDIS_URL"]
    "search-service"            = ["JWT_SECRET", "KAFKA_BROKERS", "OPENSEARCH_URL", "REDIS_URL"]
    "chat-service"              = ["INTERNAL_API_KEY", "JWT_SECRET", "KAFKA_BROKERS", "REDIS_URL", "SCYLLA_KEYSPACE", "SCYLLA_NODES", "SCYLLA_USERNAME", "SCYLLA_PASSWORD"]
    "presence-service"          = ["INTERNAL_API_KEY", "JWT_SECRET", "REDIS_URL"]
    "call-service"              = ["DATABASE_URL", "JWT_SECRET", "REDIS_URL"]
    "wallet-service"            = ["DATABASE_URL", "INTERNAL_API_KEY", "JWT_SECRET", "KAFKA_BROKERS", "REDIS_URL"]
    "payment-service"           = ["DATABASE_URL", "INTERNAL_API_KEY", "JWT_SECRET", "REDIS_URL"]
    "payout-service"            = ["DATABASE_URL", "INTERNAL_API_KEY", "JWT_SECRET", "REDIS_URL"]
    "live-service"              = ["DATABASE_URL", "INTERNAL_API_KEY", "JWT_SECRET", "REDIS_URL"]
    "notification-service"      = ["DATABASE_URL", "INTERNAL_API_KEY", "JWT_SECRET", "KAFKA_BROKERS", "REDIS_URL"]
    "analytics-service"         = ["CLICKHOUSE_DATABASE", "CLICKHOUSE_PASSWORD", "CLICKHOUSE_URL", "CLICKHOUSE_USER", "INTERNAL_API_KEY", "JWT_SECRET", "KAFKA_BROKERS", "REDIS_URL"]
    "admin-service"             = ["JWT_SECRET", "REDIS_URL"]
    "gift-service"              = ["DATABASE_URL", "INTERNAL_API_KEY", "JWT_SECRET", "KAFKA_BROKERS", "REDIS_URL"]
    "pk-service"                = ["DATABASE_URL", "INTERNAL_API_KEY", "JWT_SECRET", "KAFKA_BROKERS", "REDIS_URL"]
    "location-service"          = ["DATABASE_URL", "INTERNAL_API_KEY", "JWT_SECRET", "REDIS_URL"]
    "audit-service"             = ["DATABASE_URL", "INTERNAL_API_KEY", "JWT_SECRET", "KAFKA_BROKERS", "REDIS_URL"]
    "report-service"            = ["DATABASE_URL", "JWT_SECRET", "KAFKA_BROKERS", "REDIS_URL"]
    "moderation-service"        = ["DATABASE_URL", "JWT_SECRET", "KAFKA_BROKERS", "REDIS_URL"]
    "fraud-service"             = ["DATABASE_URL", "INTERNAL_API_KEY", "JWT_SECRET", "REDIS_URL"]
  }
  # Services on Amazon Keyspaces need SCYLLA_TLS=true (Keyspaces requires
  # TLS) - not a secret, just a fixed config flag.
  scylla_services = ["feed-service", "engagement-service", "comment-service", "story-service", "chat-service"]

  # Services whose /health fails while they have NEVER reached the broker
  # (HEALTH_REQUIRES_KAFKA - see the backend's events::health). A service with no
  # Redpanda account used to deploy as "healthy" while every message send
  # returned 503; with this, the ECS health check fails, the deployment circuit
  # breaker rolls it back, and the deploy goes red instead.
  #
  # An EXPLICIT list, not "every service with a Redpanda user", on purpose:
  # api-gateway holds Redpanda credentials but never connects - it is a pure
  # proxy - so gating it would make it report "never connected" forever and
  # have ECS kill the gateway in a loop. Every service here opens a broker
  # connection at startup (a warm-up, the outbox relay, or a consumer loop),
  # which is what makes "never connected" mean "misconfigured" rather than
  # "has not needed Kafka yet". Only add a service after confirming that.
  #
  # Only the first connection matters. A broker blip after a successful connect
  # never fails /health, because the ECS check has kill semantics and failing it
  # would recycle the whole fleet on a Redpanda restart.
  kafka_health_services = [
    "analytics-service", "audit-service", "auth-service", "chat-service",
    "comment-service", "engagement-service", "feed-service", "gift-service",
    "media-service", "moderation-service", "notification-service", "pk-service",
    "recommendation-service", "report-service", "search-service", "story-service",
    "user-service", "video-processing-service", "wallet-service",
  ]

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
    "auth-service" = { RBAC_GRPC_URL = "http://rbac-grpc:9084", NOTIFICATION_INTERNAL_URL = "http://notification-service:8101" }
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
  mock_outputs = { secret_arn = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:mock", service_databases = {}
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
      # env.hcl carries only <repository>:<tag>; the registry comes from the
      # account in backend.hcl, so env.hcl holds no account ID.
      image = "${local.backend.locals.account_id}.dkr.ecr.${local.env.locals.region}.amazonaws.com/${service.image}"
      environment = merge(
        service.environment,
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
        lookup(local.internal_service_urls, name, {}),
        # Postgres connection is handed over as DISCRETE PARTS, not as a
        # pre-composed DATABASE_URL. The app composes the URL itself (see
        # shared::config::database_url).
        #
        # A composed URL has the password baked in at apply time, and RDS rotates
        # the master password on a 7-day schedule - so every copy goes stale on
        # rotation and services fail with "password authentication failed"
        # until `terragrunt apply` regenerates them. Passing the password as its
        # own secret lets ECS resolve it from the live RDS-managed secret at task
        # start, so a rotation costs a restart instead of an apply.
        contains(keys(dependency.secrets.outputs.service_databases), name) ? {
          DB_HOST = dependency.data.outputs.aurora_endpoint
          DB_PORT = "5432"
          DB_NAME = dependency.secrets.outputs.service_databases[name]
        } : {},
        # See kafka_health_services above for why this is an explicit list.
        contains(local.kafka_health_services, name) ? {
          HEALTH_REQUIRES_KAFKA = "true"
        } : {}
      )
      secret_arns = merge(
        service.secret_arns,
        {
          for key in lookup(local.service_secret_keys, name, []) :
          key => "${dependency.secrets.outputs.secret_arn}:${key}::"
          if key != "DATABASE_URL"
        },
        # Straight from the RDS-managed master secret, so these always resolve to
        # the CURRENT credentials rather than a snapshot of them.
        contains(keys(dependency.secrets.outputs.service_databases), name) ? {
          DB_USER     = "${dependency.data.outputs.aurora_secret_arn}:username::"
          DB_PASSWORD = "${dependency.data.outputs.aurora_secret_arn}:password::"
        } : {}
      )
    })
  }

  redpanda_secret_name_prefix = "binbon-${local.env.locals.environment}-redpanda-"

  tags = local.tags
}
