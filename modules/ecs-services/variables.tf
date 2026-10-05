
variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "app_subnet_ids" {
  type = list(string)
}

variable "task_security_group_id" {
  type = string
}

variable "listener_arn" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "services" {
  type = map(object({
    image          = string
    container_port = number
    cpu            = number
    memory         = number
    desired_count  = number
    min_count      = number
    max_count      = number

    health_check_path = optional(string, "/health")
    path_patterns     = optional(list(string), [])

    environment = optional(map(string), {})

    secret_arns = optional(map(string), {})

    redpanda_user   = optional(string, null)
    task_policy_json = optional(string, null)
  }))
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "redpanda_secret_name_prefix" {
  type        = string
  default     = null
  description = <<-EOT
    Name prefix of the per-service Redpanda password secrets, e.g.
    "binbon-dev-redpanda-". When set, each service with a redpanda_user gets
    REDPANDA_SASL_PASSWORD resolved from "<prefix><redpanda_user>" by lookup.

    Resolving by NAME rather than ARN is what keeps this account-agnostic:
    Secrets Manager appends a random six-character suffix to every ARN, so a
    literal ARN is valid in exactly one account and has to be rewritten by hand
    on every migration. The names are deterministic.
  EOT
}

variable "deployment_minimum_healthy_percent" {
  description = <<-EOT
    ECS deployment floor. 100 (ECS's default) starts each new task before the
    old one stops: zero downtime, but every rolling service briefly needs room
    for one more task. 0 stops the old task first, so a deploy needs no spare
    capacity, at the cost of the service being down while its new task starts,
    and until rollback if that task fails. Use 0 only where downtime is
    acceptable (dev) and capacity isn't (a small Fargate vCPU quota).
  EOT
  type        = number
  default     = 100
}

variable "deployment_maximum_percent" {
  description = "ECS deployment ceiling: 200 (the default) allows the overlap above; with a floor of 0, 100 means no extra task at all."
  type        = number
  default     = 200
}
