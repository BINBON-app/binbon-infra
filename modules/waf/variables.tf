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
variable "tags" {
  type    = map(string)
  default = {}
}
