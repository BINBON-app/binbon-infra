output "service_id" {
  value = clickhouse_service.this.id
}
output "endpoints" {
  value = clickhouse_service.this.endpoints
}
output "https_url" {
  value = "https://${clickhouse_service.this.endpoints.https.host}:${clickhouse_service.this.endpoints.https.port}"
}
