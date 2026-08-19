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
      name             = string, type = string
    })), partition_key = list(string), clustering_key = optional(list(string), [])
  }))
  default = {}
}
variable "tags" {
  type    = map(string)
  default = {}
}
