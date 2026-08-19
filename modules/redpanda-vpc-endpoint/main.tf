# -------------------------------------------------------------------
# Discover metadata for every candidate application subnet
# -------------------------------------------------------------------

data "aws_subnet" "candidate" {
  for_each = toset(var.subnet_ids)

  id = each.value
}

# -------------------------------------------------------------------
# Select only subnets whose AWS Availability Zone ID is supported
# by the Redpanda PrivateLink service.
#
# Example:
#
# subnet-aaa
#   AZ name = eu-central-1c
#   AZ ID   = euc1-az1
#
# Redpanda returns:
#   ["euc1-az1"]
#
# Therefore subnet-aaa is selected.
# -------------------------------------------------------------------

locals {
  endpoint_subnets = {
    for subnet_id, subnet in data.aws_subnet.candidate :
    subnet_id => {
      availability_zone    = subnet.availability_zone
      availability_zone_id = subnet.availability_zone_id
    }
    if contains(
      var.service_availability_zone_ids,
      subnet.availability_zone_id
    )
  }

  endpoint_subnet_ids = keys(local.endpoint_subnets)

  selected_availability_zone_ids = distinct([
    for subnet in values(local.endpoint_subnets) :
    subnet.availability_zone_id
  ])
}

# -------------------------------------------------------------------
# Security Group
# -------------------------------------------------------------------

resource "aws_security_group" "endpoint" {
  name = "${var.name}-redpanda-vpce"

  # Keep the old description so Terraform does NOT unnecessarily
  # replace the existing security group.
  description = "Permit ECS tasks to reach the Redpanda PrivateLink interface endpoint"

  vpc_id = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-redpanda-vpce"
    }
  )
}

# -------------------------------------------------------------------
# Redpanda ingress rules
# -------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "redpanda" {
  for_each = var.ingress_rules

  security_group_id = aws_security_group.endpoint.id

  referenced_security_group_id = var.task_security_group_id

  description = each.value.description

  ip_protocol = "tcp"

  from_port = each.value.from_port
  to_port   = each.value.to_port
}

# -------------------------------------------------------------------
# Endpoint egress
# -------------------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.endpoint.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# -------------------------------------------------------------------
# Redpanda PrivateLink Interface Endpoint
# -------------------------------------------------------------------

resource "aws_vpc_endpoint" "this" {
  vpc_id = var.vpc_id

  service_name      = var.service_name
  vpc_endpoint_type = "Interface"

  #
  # Dynamically filtered list.
  #
  # Only subnets whose AvailabilityZoneId matches an AZ ID
  # returned by Redpanda are passed to AWS.
  #
  subnet_ids = local.endpoint_subnet_ids

  security_group_ids = [
    aws_security_group.endpoint.id
  ]

  private_dns_enabled = var.private_dns_enabled

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-redpanda"
    }
  )

  lifecycle {
    precondition {
      condition = length(var.subnet_ids) > 0

      error_message = "At least one application subnet must be supplied to the Redpanda VPC endpoint module."
    }

    precondition {
      condition = length(var.service_availability_zone_ids) > 0

      error_message = <<-EOT
        Redpanda returned no Availability Zone IDs for the PrivateLink service.

        Ensure that the Redpanda PrivateLink resource is ready before
        creating the AWS interface endpoint.
      EOT
    }

    precondition {
      condition = length(local.endpoint_subnet_ids) > 0

      error_message = <<-EOT
        None of the supplied application subnets are located in an AWS
        Availability Zone ID supported by the Redpanda PrivateLink service.

        Candidate subnet AZ IDs:
        ${join(", ", [
  for subnet in values(data.aws_subnet.candidate) :
  subnet.availability_zone_id
])}

        Redpanda supported AZ IDs:
        ${join(", ", var.service_availability_zone_ids)}
      EOT
    }

    #
    # An Interface VPC endpoint cannot have multiple subnets from
    # the same Availability Zone.
    #
    precondition {
      condition = (
        length(local.endpoint_subnet_ids) ==
        length(local.selected_availability_zone_ids)
      )

      error_message = <<-EOT
        More than one selected subnet belongs to the same Availability Zone.

        AWS Interface VPC endpoints support at most one subnet per
        Availability Zone.
      EOT
    }
  }
}