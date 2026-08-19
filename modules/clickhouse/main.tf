provider "clickhouse" {
}

resource "clickhouse_service" "this" {
  name                  = var.name
  cloud_provider        = "aws"
  region                = var.region
  idle_scaling          = var.idle_scaling
  idle_timeout_minutes  = var.idle_scaling ? var.idle_timeout_minutes : null
  autoscaling_mode      = "vertical"
  num_replicas          = var.num_replicas
  min_replica_memory_gb = var.min_replica_memory_gb
  max_replica_memory_gb = var.max_replica_memory_gb

  ip_access = [
    for cidr in var.allowed_cidrs : {
      source      = cidr
      description = "ECS NAT egress"
    }
  ]

  password_wo         = var.clickhouse_admin_password
  password_wo_version = var.password_wo_version

  tags = var.tags

  lifecycle {
    precondition {
      condition     = length(var.allowed_cidrs) > 0
      error_message = "Pass at least one CIDR (e.g. the NAT gateway EIP) in allowed_cidrs."
    }
  }
}
