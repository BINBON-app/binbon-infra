variable "name" {
  description = "Prefix matching the ECR repository and IAM role naming convention (e.g. \"binbon\")"
  type        = string
}
variable "github_org" {
  description = "GitHub org or user that owns both repos. Must be set explicitly before applying — there is no default, so a placeholder can't accidentally grant access to nothing (safe) or everything (unsafe)."
  type        = string

  validation {
    condition     = length(trimspace(var.github_org)) > 0
    error_message = "github_org must be set to your real GitHub org or username."
  }
}
variable "monorepo_name" {
  description = "Name of the GitHub repo containing service source code and Dockerfiles. Trusted for the ECR push role only."
  type        = string
}
variable "infra_repo_name" {
  description = "Name of the GitHub repo containing this Terraform/Terragrunt codebase. Trusted for the Terraform-apply role only."
  type        = string
}
variable "tags" {
  type    = map(string)
  default = {}
}
