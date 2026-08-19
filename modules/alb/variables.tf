variable "name" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "public_subnet_ids" {
  type = list(string)
}
variable "certificate_arn" {
  type    = string
  default = null
}
variable "tags" {
  type    = map(string)
  default = {}
}
