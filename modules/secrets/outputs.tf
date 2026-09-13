output "secret_arn" {
  value = aws_secretsmanager_secret.infra.arn
}

output "service_databases" {
  description = "Service name -> its database on the Aurora cluster. Exposed so the services component can set DB_NAME per service without duplicating the map."
  value       = var.postgres_service_databases
}
