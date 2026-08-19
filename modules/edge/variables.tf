variable "name" {
  type = string
}
variable "alb_dns_name" {
  type = string
}
variable "alb_uses_https" {
  type    = bool
  default = true
}
variable "cloudfront_acm_certificate_arn" {
  type    = string
  default = null
}
variable "waf_web_acl_arn" {
  type    = string
  default = null
}
variable "domain_name" {
  type    = string
  default = null
}
variable "route53_zone_id" {
  type    = string
  default = null
}
variable "tags" {
  type    = map(string)
  default = {}
}
