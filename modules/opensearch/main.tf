data "aws_caller_identity" "current" {}

locals {
  zone_awareness_enabled = var.instance_count > 1
  az_count               = min(var.instance_count, length(var.data_subnet_ids))
  subnet_ids             = local.zone_awareness_enabled ? slice(var.data_subnet_ids, 0, local.az_count) : [var.data_subnet_ids[0]]
}

resource "aws_security_group" "opensearch" {
  name        = "${var.name}-opensearch"
  vpc_id      = var.vpc_id
  description = "OpenSearch access from ECS tasks"
  tags        = var.tags
}
resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id            = aws_security_group.opensearch.id
  referenced_security_group_id = var.app_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.opensearch.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# A brand-new AWS account has no OpenSearch service-linked role, and without it
# CreateDomain fails with "you must enable a service-linked role to give Amazon
# OpenSearch Service permissions to access your VPC". The role is account-global
# and can only be created once, so set create_service_linked_role = false for any
# environment sharing an account with one that already created it.
resource "aws_iam_service_linked_role" "opensearch" {
  count            = var.create_service_linked_role ? 1 : 0
  aws_service_name = "opensearchservice.amazonaws.com"
}

resource "aws_opensearch_domain" "this" {
  domain_name    = "${var.name}-search"
  engine_version = var.engine_version

  depends_on = [aws_iam_service_linked_role.opensearch]

  cluster_config {
    instance_type          = var.instance_type
    instance_count         = var.instance_count
    zone_awareness_enabled = local.zone_awareness_enabled

    dynamic "zone_awareness_config" {
      for_each = local.zone_awareness_enabled ? [1] : []
      content {
        availability_zone_count = local.az_count
      }
    }
  }

  vpc_options {
    subnet_ids         = local.subnet_ids
    security_group_ids = [aws_security_group.opensearch.id]
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = var.volume_size_gb
  }

  encrypt_at_rest {
    enabled    = true
    kms_key_id = var.kms_key_arn
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  tags = var.tags
}

resource "aws_opensearch_domain_policy" "this" {
  domain_name = aws_opensearch_domain.this.domain_name
  # The domain is VPC-only (see vpc_options above) - the security group is
  # already the real access boundary, so requests aren't SigV4-signed and an
  # account-root-only policy just rejects every caller as "anonymous". Open
  # access here, same as any other VPC-private-only AWS resource.
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "es:ESHttp*"
      Resource  = "${aws_opensearch_domain.this.arn}/*"
    }]
  })
}
