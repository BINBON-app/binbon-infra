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
  description = "Default certificate for :443. Null builds no HTTPS listener and makes :80 answer 503."
  type        = string
  default     = null
}
variable "additional_certificate_arns" {
  description = "More certificates on :443, served by SNI (e.g. a wildcard next to the default host's)."
  type        = list(string)
  default     = []
}
variable "ssl_policy" {
  type    = string
  default = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
}
variable "tags" {
  type    = map(string)
  default = {}
}
variable "waf_web_acl_arn" {
  description = "Regional WAF web ACL to attach to the load balancer. Null attaches none."
  type        = string
  default     = null
}
