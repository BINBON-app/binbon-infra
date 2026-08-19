output "vpc_endpoint_id" {
  description = "Redpanda VPC endpoint ID"
  value       = aws_vpc_endpoint.this.id
}

output "security_group_id" {
  description = "Security group attached to the Redpanda interface endpoint"
  value       = aws_security_group.endpoint.id
}

output "dns_entries" {
  description = "DNS entries assigned to the Redpanda VPC endpoint"
  value       = aws_vpc_endpoint.this.dns_entry
}

output "service_name" {
  description = "Redpanda PrivateLink endpoint service name"
  value       = var.service_name
}

output "supported_availability_zone_ids" {
  description = "AZ IDs supported by the Redpanda PrivateLink service"
  value       = var.service_availability_zone_ids
}

output "candidate_subnets" {
  description = "All candidate application subnets with AZ name and AZ ID"

  value = {
    for subnet_id, subnet in data.aws_subnet.candidate :
    subnet_id => {
      availability_zone    = subnet.availability_zone
      availability_zone_id = subnet.availability_zone_id
    }
  }
}

output "selected_subnets" {
  description = "Application subnets selected for Redpanda PrivateLink"
  value       = local.endpoint_subnets
}

output "selected_subnet_ids" {
  description = "Subnet IDs selected for the Redpanda interface endpoint"
  value       = local.endpoint_subnet_ids
}