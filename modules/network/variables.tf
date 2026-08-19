variable "name" {
  type = string
}
variable "cidr_block" {
  type = string
}
variable "azs" {
  type = list(string)
}
variable "single_nat_gateway" {
  type    = bool
  default = false
}
variable "tags" {
  type    = map(string)
  default = {}
}