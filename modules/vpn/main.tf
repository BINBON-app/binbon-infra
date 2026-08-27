# OpenVPN Access Server on a public-subnet EC2 instance, giving operators a
# proper standing route into the VPC (psql/DBeaver/etc. against Aurora,
# Redis, OpenSearch) instead of ad-hoc SSM/ECS-Exec tunnels that die with
# every task redeploy and require IAM access to this AWS account itself.
#
# AMI subscription (AWS Marketplace terms/billing) has to be accepted once,
# manually, via https://aws.amazon.com/marketplace/pp?sku=<product-code> -
# Terraform can't do that step; `aws ec2 run-instances --dry-run` against
# the AMI returns OptInRequired until it's done.

resource "aws_security_group" "vpn" {
  name        = "${var.name}-vpn"
  description = "OpenVPN Access Server - public VPN entry point"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "openvpn_udp" {
  security_group_id = aws_security_group.vpn.id
  description       = "OpenVPN tunnel (UDP) - open to any client"
  cidr_ipv4          = "0.0.0.0/0"
  from_port          = 1194
  to_port            = 1194
  ip_protocol        = "udp"
}

resource "aws_vpc_security_group_ingress_rule" "openvpn_tcp" {
  security_group_id = aws_security_group.vpn.id
  description       = "OpenVPN tunnel (TCP fallback) + client web portal"
  cidr_ipv4          = "0.0.0.0/0"
  from_port          = 443
  to_port            = 443
  ip_protocol        = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "admin_web" {
  for_each           = toset(var.admin_cidrs)
  security_group_id  = aws_security_group.vpn.id
  description        = "OpenVPN admin web UI"
  cidr_ipv4          = each.value
  from_port          = 943
  to_port            = 943
  ip_protocol        = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each           = toset(var.admin_cidrs)
  security_group_id  = aws_security_group.vpn.id
  description        = "SSH admin access"
  cidr_ipv4          = each.value
  from_port          = 22
  to_port            = 22
  ip_protocol        = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.vpn.id
  cidr_ipv4          = "0.0.0.0/0"
  ip_protocol        = "-1"
}

resource "aws_instance" "this" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.vpn.id, var.app_security_group_id]

  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
  }

  tags = merge(var.tags, { Name = "${var.name}-vpn" })
}

resource "aws_eip" "vpn" {
  instance = aws_instance.this.id
  domain   = "vpc"
  tags     = merge(var.tags, { Name = "${var.name}-vpn" })
}
