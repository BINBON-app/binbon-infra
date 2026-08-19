output "cluster_id" {
  value = redpanda_serverless_cluster.this.id
}
output "cluster_api_url" {
  value = redpanda_serverless_cluster.this.cluster_api_url
}
output "kafka_private_seed_brokers" {
  value = redpanda_serverless_cluster.this.kafka_api.private_seed_brokers
}
output "private_link_id" {
  value = try(redpanda_serverless_private_link.this[0].id, null)
}
output "private_link_service_name" {
  value = try(redpanda_serverless_private_link.this[0].status.aws.vpc_endpoint_service_name, null)
}
output "private_link_availability_zones" {
  value = try(redpanda_serverless_private_link.this[0].status.aws.availability_zones, [])
}
output "service_usernames" {
  value = {
    for name, user in redpanda_user.this : name => user.name
  }
}
