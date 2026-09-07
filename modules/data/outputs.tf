output "security_group_id" {
  value = aws_security_group.data.id
}
output "aurora_endpoint" {
  value = aws_rds_cluster.aurora.endpoint
}
output "aurora_database_name" {
  value = aws_rds_cluster.aurora.database_name
}
output "aurora_secret_arn" {
  value = aws_rds_cluster.aurora.master_user_secret[0].secret_arn
}
output "redis_endpoint" {
  value = aws_elasticache_serverless_cache.redis.endpoint[0].address
}
output "keyspace_name" {
  value = aws_keyspaces_keyspace.this.name
}
output "keyspaces_endpoint" {
  value = "cassandra.${data.aws_region.current.name}.amazonaws.com:9142"
}
output "keyspaces_username" {
  value = aws_iam_service_specific_credential.keyspaces.service_user_name
}
output "keyspaces_password" {
  value     = aws_iam_service_specific_credential.keyspaces.service_password
  sensitive = true
}
output "aurora_cluster_arn" {
  description = "Cluster ARN, needed to run admin SQL over the RDS Data API."
  value       = aws_rds_cluster.aurora.arn
}
