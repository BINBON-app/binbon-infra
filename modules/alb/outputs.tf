output "dns_name" {
  value = aws_lb.this.dns_name
}
output "zone_id" {
  value = aws_lb.this.zone_id
}
output "security_group_id" {
  value = aws_security_group.alb.id
}
output "task_security_group_id" {
  value = aws_security_group.tasks.id
}
output "listener_arn" {
  value = try(aws_lb_listener.https[0].arn, aws_lb_listener.http.arn)
}
