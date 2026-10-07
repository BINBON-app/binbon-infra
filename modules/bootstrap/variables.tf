variable "name" {
  type = string
}
variable "tags" {
  type    = map(string)
  default = {}
}
variable "service_linked_roles" {
  description = "AWS services whose account-global service-linked role must exist before the first component apply."
  type        = set(string)
  default     = ["opensearchservice.amazonaws.com"]
}
