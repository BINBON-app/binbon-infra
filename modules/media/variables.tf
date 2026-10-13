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

variable "public_read" {
  description = "Let anyone read every object in the bucket: turns Block Public Access off and adds a public s3:GetObject statement on /* to the bucket policy. This includes p/, so private media (private videos, view-once media, documents) becomes readable by anyone with its path. Default false."
  type        = bool
  default     = false
}

variable "sse_algorithm" {
  description = "Default bucket encryption: \"aws:kms\" with kms_key_arn (default), or \"AES256\" (SSE-S3, with an S3 bucket key). AES256 objects can be read anonymously when public_read is on; aws:kms objects can't."
  type        = string
  default     = "aws:kms"
  validation {
    condition     = contains(["aws:kms", "AES256"], var.sse_algorithm)
    error_message = "sse_algorithm must be \"aws:kms\" or \"AES256\"."
  }
}
