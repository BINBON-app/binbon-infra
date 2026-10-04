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
variable "enable_cloudfront" {
  description = "Create the CloudFront distribution in front of the bucket. Off only while an account can't create CloudFront resources yet (a new account awaiting verification); services then get an empty CDN_BASE_URL and serve presigned S3 URLs."
  type        = bool
  default     = true
}
variable "waf_web_acl_arn" {
  type    = string
  default = null
}
variable "tags" {
  type    = map(string)
  default = {}
}
