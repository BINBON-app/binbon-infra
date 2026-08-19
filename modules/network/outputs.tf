output "vpc_id" {
  value = aws_vpc.this.id
}
output "public_subnet_ids" {
  value = [for s in aws_subnet.public : s.id]
}
output "app_subnet_ids" {
  value = [for s in aws_subnet.app : s.id]
}
output "data_subnet_ids" {
  value = [for s in aws_subnet.data : s.id]
}
output "nat_public_ips" {
  value = [for eip in aws_eip.nat : eip.public_ip]
}
output "app_subnet_ids_by_az" {
  description = "Application subnet IDs keyed by Availability Zone"

  value = {
    for az, subnet in aws_subnet.app :
    az => subnet.id
  }
}