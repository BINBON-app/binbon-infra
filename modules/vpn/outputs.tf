output "public_ip" {
  value = aws_eip.vpn.public_ip
}
output "instance_id" {
  value = aws_instance.this.id
}
output "admin_url" {
  value = "https://${aws_eip.vpn.public_ip}:943/admin"
}
output "client_url" {
  value = "https://${aws_eip.vpn.public_ip}/"
}
output "security_group_id" {
  value = aws_security_group.vpn.id
}
