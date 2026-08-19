output "service_id" {
  value = clickhouse_service.this.id
}
output "endpoints" {
  value = clickhouse_service.this.endpoints
}
