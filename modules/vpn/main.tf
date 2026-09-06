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

# Break-glass access. Without an instance profile the SSM agent cannot register,
# and since key_name is optional there is otherwise NO way into the host at all -
# which is exactly the state the first build of this module produced: a healthy
# instance nobody could log in to.
resource "aws_iam_role" "vpn" {
  name = "${var.name}-vpn"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "vpn_ssm" {
  role       = aws_iam_role.vpn.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "vpn" {
  name = "${var.name}-vpn"
  role = aws_iam_role.vpn.name
  tags = var.tags
}

# The Marketplace AMI does not self-configure: it ships with the service
# disabled and no config.db, and expects `ovpn-init` to be run once. Terraform
# reports a healthy instance either way, so without this the apply "succeeds"
# and leaves a VPN that refuses every connection on 443/943/1194.
#
# The public address is read from IMDS rather than interpolated, because the EIP
# is associated *after* the instance exists - referencing aws_eip here would be a
# dependency cycle. The loop waits for the association to land.
data "aws_vpc" "this" {
  id = var.vpc_id
}

locals {
  vpn_user_data = <<-EOT
    #!/bin/bash
    set -uo pipefail
    exec > >(tee /var/log/vpn-bootstrap.log) 2>&1

    BIN=/usr/local/openvpn_as/bin
    IMDS=http://169.254.169.254/latest

    token() { curl -sS -m 5 -X PUT "$IMDS/api/token" \
                -H "X-aws-ec2-metadata-token-ttl-seconds: 300" 2>/dev/null; }

    # Wait for the Elastic IP to be associated so the server's advertised host
    # is the stable address clients will actually use, not the launch-time one.
    HOST=""
    for _ in $(seq 1 30); do
      T=$(token)
      IP=$(curl -sS -m 5 -H "X-aws-ec2-metadata-token: $T" \
             "$IMDS/meta-data/public-ipv4" 2>/dev/null)
      if [ -n "$IP" ]; then HOST="$IP"; fi
      sleep 5
      T=$(token)
      IP2=$(curl -sS -m 5 -H "X-aws-ec2-metadata-token: $T" \
              "$IMDS/meta-data/public-ipv4" 2>/dev/null)
      # Two consecutive identical reads means the EIP swap has settled.
      if [ -n "$IP2" ] && [ "$IP2" = "$HOST" ]; then HOST="$IP2"; break; fi
    done

    if [ ! -f /usr/local/openvpn_as/etc/db/config.db ]; then
      # --batch constitutes acceptance of the OpenVPN Access Server EULA, which
      # the account owner also accepts when subscribing to the AMI in Marketplace.
      if [ -n "$HOST" ]; then
        "$BIN/ovpn-init" --batch --local_auth --host="$HOST"
      else
        "$BIN/ovpn-init" --batch --local_auth
      fi
    fi

    systemctl enable --now openvpnas

    # ovpn-init advertises the server's OWN subnet as the private network, which
    # is a /20 here - so clients get a route to the VPN's subnet and nothing
    # else, and Aurora/Redis/OpenSearch in the other /20s are unreachable. The
    # symptom is a connection timeout that looks like a firewall problem.
    # Advertise the whole VPC instead.
    SACLI=/usr/local/openvpn_as/scripts/sacli
    "$SACLI" --key "vpn.server.routing.private_network.0" \
             --value "${data.aws_vpc.this.cidr_block}" ConfigPut
    "$SACLI" start
  EOT
}

resource "aws_instance" "this" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.vpn.id, var.app_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.vpn.name

  associate_public_ip_address = true

  user_data = local.vpn_user_data
  # Editing the bootstrap script must never destroy a working VPN. cloud-init
  # only runs user_data on an instance's first boot, so a change here applies to
  # the next instance built, not this one - replace deliberately if you need it.
  user_data_replace_on_change = false

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

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
