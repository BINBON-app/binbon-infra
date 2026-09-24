variable "name" {
  type = string
}
variable "kms_key_arn" {
  type = string
}
variable "aurora_endpoint" {
  type = string
}
variable "aurora_secret_arn" {
  type = string
}
variable "postgres_service_databases" {
  type = map(string)
}
variable "redis_endpoint" {
  type = string
}
variable "kafka_brokers" {
  type = list(string)
}
variable "clickhouse_url" {
  type = string
}
variable "clickhouse_database" {
  type = string
}
# Not readable back from the clickhouse_service resource (password_wo is
# write-only by design), so the same value the clickhouse unit receives via
# TF_VAR_clickhouse_admin_password is duplicated into this secret.
variable "clickhouse_admin_password" {
  type      = string
  sensitive = true
}
variable "opensearch_endpoint" {
  type = string
}
# Shared HS256 signing key for platform access tokens. Every service both mints
# (auth-service) and verifies with this ONE symmetric secret, so all services
# must receive the identical value or cross-service auth breaks. Seeded once via
# scripts/bootstrap-secrets.sh; without it each service silently falls back to
# the insecure DEV_JWT_SECRET constant compiled into the backend, and refuses to
# boot at all once APP_ENV=production.
variable "jwt_secret" {
  type      = string
  sensitive = true
}
# Shared secret guarding internal service-to-service calls (payment / payout /
# live -> wallet, auth -> rbac, and the other privileged internal endpoints).
# Same all-or-nothing rule as jwt_secret: caller and callee compare it directly.
variable "internal_api_key" {
  type      = string
  sensitive = true
}
variable "media_url_signing_key" {
  type      = string
  sensitive = true
}
variable "keyspaces_endpoint" {
  type = string
}
variable "keyspaces_keyspace_name" {
  type = string
}
variable "keyspaces_username" {
  type      = string
  sensitive = true
}
variable "keyspaces_password" {
  type      = string
  sensitive = true
}
variable "s3_bucket" {
  type = string
}
variable "s3_region" {
  type = string
}
variable "s3_access_key_id" {
  type      = string
  sensitive = true
}
variable "s3_secret_access_key" {
  type      = string
  sensitive = true
}
variable "cdn_domain_name" {
  type = string
}
variable "tags" {
  type    = map(string)
  default = {}
}

variable "aurora_cluster_arn" {
  type        = string
  description = "Aurora cluster ARN, used to create the per-service databases over the RDS Data API."
}

variable "create_service_databases" {
  type        = bool
  default     = true
  description = <<-EOT
    Create one database per service inside the Aurora cluster.

    Aurora is provisioned with a single database, but the design is
    database-per-service so each service's sqlx migration history stays
    independent. Those databases were historically created by hand, which meant
    a fresh account came up with every Postgres-backed service crash-looping on
    'database "binbon_x" does not exist' - with nothing in the codebase saying
    the step existed. Driving them from postgres_service_databases makes that
    map the single source of truth.

    Requires the AWS CLI on the machine running Terraform (the RDS Data API is
    used because Aurora sits in a private subnet).
  EOT
}
