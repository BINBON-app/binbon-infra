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
    image = string, container_port = number, cpu = number, memory = number, desired_count = number, min_count = number, max_count = number, health_check_path = optional(string, "/health"), path_patterns = optional(list(string), []), environment = optional(map(string), {
      }), secret_arns = optional(map(string), {
    }), redpanda_user = optional(string, null), task_policy_json = optional(string, null)
  }))
}
variable "tags" {
  type    = map(string)
  default = {}
}
