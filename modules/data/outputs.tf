output "security_group_id" {
  value = aws_security_group.data.id
}
output "aurora_endpoint" {
  value = aws_rds_cluster.aurora.endpoint
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
