output "cluster_name" {
  value = aws_ecs_cluster.this.name
}
output "task_security_group_id" {
  value = var.task_security_group_id
}
output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}
output "task_role_arns" {
  value = { for k, v in aws_iam_role.task : k => v.arn }
}
output "task_definition_arns" {
  description = "Terraform's current task definition revision per service. Useful for manually re-syncing a service after an infra-only change (see README)."
  value       = { for k, v in aws_ecs_task_definition.this : k => v.arn }
}
