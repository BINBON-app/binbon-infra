variable "name" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "data_subnet_ids" {
  type = list(string)
}
variable "app_security_group_id" {
  type = string
}
variable "kms_key_arn" {
  type = string
}
variable "aurora_database_name" {
  type    = string
  default = "app"
}
variable "aurora_master_username" {
  type    = string
  default = "platformadmin"
}
variable "aurora_min_acu" {
  type    = number
  default = 0.5
}
variable "aurora_max_acu" {
  type    = number
  default = 4
}
variable "enable_deletion_protection" {
  type    = bool
  default = false
}
variable "keyspaces_tables" {
  type = map(object({
    columns = list(object({
      name = string, type = string
    })),
    partition_key = list(string),
    clustering_key = optional(list(object({
      name = string, order = optional(string, "ASC")
    })), [])
    static_columns = optional(list(string), [])
    # Keyspaces options. A table missing one still PREPAREs, then fails the
    # service's capability probe and keeps that feature at 503.
    default_time_to_live   = optional(number)
    ttl_enabled            = optional(bool, false)
    client_side_timestamps = optional(bool, false)
  }))
  default = {}
}
variable "tags" {
  type    = map(string)
  default = {}
}
