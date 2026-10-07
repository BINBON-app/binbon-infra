variable "name" {
  type = string
}
variable "region" {
  type = string
  validation {
    condition     = var.region == "eu-central-1"
    error_message = "This platform is pinned to AWS Frankfurt (eu-central-1)."

  }
}
variable "aws_account_id" {
  type = string
}
variable "enable_private_link" {
  type    = bool
  default = true
}
variable "public_networking" {
  type    = string
  default = "STATE_DISABLED"
}
variable "private_networking" {
  type    = string
  default = "STATE_ENABLED"
}
variable "allow_cluster_deletion" {
  type    = bool
  default = false
}
variable "allow_private_link_deletion" {
  type    = bool
  default = false
}
variable "allow_topic_deletion" {
  type    = bool
  default = false
}
variable "allow_user_deletion" {
  type    = bool
  default = false
}
variable "allow_acl_deletion" {
  type    = bool
  default = false
}
variable "topics" {
  type = map(object({
    partitions         = number
    replication_factor = optional(number, null)
    configuration = optional(map(string), {
    })

  }))
  default = {
  }
}
variable "service_users" {
  description = "Kafka principals. Passwords are supplied as write-only CI variables, never in this configuration."
  type = map(object({
    password_wo_version = number
    topic_permissions = optional(map(list(string)), {
    })
    group_permissions = optional(map(list(string)), {
    })
    cluster_permissions = optional(list(string), [])

  }))
  default = {
  }
}
variable "service_user_passwords" {
  description = "Map of user passwords passed by CI as TF_VAR_service_user_passwords. Write-only values are not retained in Terraform state."
  type        = map(string)
  sensitive   = true
  default = {
  }
}
variable "tags" {
  type    = map(string)
  default = {}
}

variable "private_link_name" {
  description = "Overrides the PrivateLink's name (default <name>-private-link). Redpanda keeps a deleted link's name while its deletion runs, and a link whose AWS endpoint can't be removed (e.g. in a blocked old account) can stay deleting for good, so a new account may need a different name."
  type        = string
  default     = null
}
