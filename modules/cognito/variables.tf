variable "name" {
  type = string
}
variable "hosted_domain_prefix" {
  type    = string
  default = null
}
variable "custom_domain" {
  type    = string
  default = null
}
variable "custom_domain_certificate_arn" {
  type    = string
  default = null
}
variable "callback_urls" {
  type    = list(string)
  default = []
}
variable "logout_urls" {
  type    = list(string)
  default = []
}
variable "mfa_configuration" {
  type    = string
  default = "OPTIONAL"
}
variable "allow_self_signup" {
  type    = bool
  default = true
}
variable "generate_client_secret" {
  type    = bool
  default = false
}
variable "create_identity_pool" {
  type    = bool
  default = false
}
variable "waf_web_acl_arn" {
  type    = string
  default = null
}
variable "groups" {
  type = map(object({
    description = optional(string, null), precedence = optional(number, null), role_arn = optional(string, null)
  }))
  default = {}
}
variable "api_scopes" {
  type    = map(string)
  default = { read = "Read application data", write = "Write application data" }
}
variable "lambda_triggers" {
  type    = map(string)
  default = {}
}
variable "tags" {
  type    = map(string)
  default = {}
}
