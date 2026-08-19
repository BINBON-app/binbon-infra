variable "name" {
  type = string
}
variable "region" {
  description = "ClickHouse Cloud region name within the aws cloud_provider (e.g. eu-central-1)"
  type        = string
}
variable "num_replicas" {
  type    = number
  default = 1
}
variable "min_replica_memory_gb" {
  type    = number
  default = 8
}
variable "max_replica_memory_gb" {
  type    = number
  default = 8
}
variable "idle_scaling" {
  type    = bool
  default = true
}
variable "idle_timeout_minutes" {
  description = "Minimum idle duration before scaling to zero. Required by the provider whenever idle_scaling is true."
  type        = number
  default     = 5
}
variable "allowed_cidrs" {
  description = "CIDRs allowed to reach the service, e.g. the environment's NAT gateway public IP(s) as /32"
  type        = list(string)
}
variable "clickhouse_admin_password" {
  description = "Initial admin password, supplied as a CI write-only variable (e.g. TF_VAR_clickhouse_admin_password). Not stored in Terraform state."
  type        = string
  sensitive   = true
}
variable "password_wo_version" {
  type    = number
  default = 1
}
variable "tags" {
  type    = map(string)
  default = {}
}
