variable "name" {
  type = string
}
variable "kms_key_arn" {
  type = string
}
variable "cloudfront_acm_certificate_arn" {
  type    = string
  default = null
}
variable "waf_web_acl_arn" {
  type    = string
  default = null
}
variable "tags" {
  type    = map(string)
  default = {}
}
