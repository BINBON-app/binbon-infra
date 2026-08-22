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
