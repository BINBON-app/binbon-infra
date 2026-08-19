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
variable "engine_version" {
  type    = string
  default = "OpenSearch_2.15"
}
variable "instance_type" {
  type    = string
  default = "t3.small.search"
}
variable "instance_count" {
  type    = number
  default = 1
}
variable "volume_size_gb" {
  type    = number
  default = 10
}
variable "tags" {
  type    = map(string)
  default = {}
}
