variable "name" {
  type = string
}
variable "scope" {
  type = string
  validation {
    condition     = contains(["CLOUDFRONT", "REGIONAL"], var.scope)
    error_message = "scope must be CLOUDFRONT or REGIONAL."
  }
}
variable "rate_limit" {
  description = "Max requests per 5-minute window per IP before blocking"
  type        = number
  default     = 2000
}
variable "common_rules_count_only" {
  description = "Rules of AWSManagedRulesCommonRuleSet to count instead of block, e.g. SizeRestrictions_BODY where requests legitimately carry bodies over 8 KB."
  type        = list(string)
  default     = []
}
variable "tags" {
  type    = map(string)
  default = {}
}
