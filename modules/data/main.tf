resource "aws_security_group" "data" {
  name        = "${var.name}-data"
  vpc_id      = var.vpc_id
  description = "Aurora and Redis access from ECS"
  tags        = var.tags
}
resource "aws_vpc_security_group_ingress_rule" "postgres" {
  security_group_id            = aws_security_group.data.id
  referenced_security_group_id = var.app_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}
resource "aws_vpc_security_group_ingress_rule" "redis" {
  security_group_id            = aws_security_group.data.id
  referenced_security_group_id = var.app_security_group_id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.data.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.name}-aurora"
  subnet_ids = var.data_subnet_ids
  tags       = var.tags
}
resource "aws_rds_cluster" "aurora" {
  cluster_identifier          = "${var.name}-aurora"
  engine                      = "aurora-postgresql"
  engine_mode                 = "provisioned"
  database_name               = var.aurora_database_name
  master_username             = var.aurora_master_username
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.aurora.name
  vpc_security_group_ids      = [aws_security_group.data.id]
  storage_encrypted           = true
  kms_key_id                  = var.kms_key_arn
  backup_retention_period     = 7
  deletion_protection         = var.enable_deletion_protection
  skip_final_snapshot         = !var.enable_deletion_protection
  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_min_acu
    max_capacity = var.aurora_max_acu
  }
  tags = var.tags
}
resource "aws_rds_cluster_instance" "aurora" {
  identifier          = "${var.name}-aurora-1"
  cluster_identifier  = aws_rds_cluster.aurora.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.aurora.engine
  publicly_accessible = false
  tags                = var.tags
}
resource "aws_elasticache_serverless_cache" "redis" {
  name                 = "${var.name}-redis"
  engine               = "redis"
  major_engine_version = "7"
  subnet_ids           = var.data_subnet_ids
  security_group_ids   = [aws_security_group.data.id]
  cache_usage_limits {
    data_storage {
      maximum = 1
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = 5000
    }
  }
  tags = var.tags
}
resource "aws_keyspaces_keyspace" "this" {
  name = replace("${var.name}_app", "-", "_")
  tags = var.tags
}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
# CQL driver access to Keyspaces authenticates via IAM service-specific
# credentials (SigV4), not a native username/password - this is the
# mechanism AWS provides in place of a Cassandra superuser.
resource "aws_iam_user" "keyspaces" {
  name = "${var.name}-keyspaces-app"
  tags = var.tags
}
resource "aws_iam_user_policy" "keyspaces" {
  name = "keyspaces-access"
  user = aws_iam_user.keyspaces.name
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["cassandra:Select", "cassandra:Modify"], Resource = "arn:aws:cassandra:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:/keyspace/${aws_keyspaces_keyspace.this.name}/*"
    }]
  })
}
resource "aws_iam_service_specific_credential" "keyspaces" {
  user_name    = aws_iam_user.keyspaces.name
  service_name = "cassandra.amazonaws.com"
}
resource "aws_keyspaces_table" "this" {
  for_each = var.keyspaces_tables

  keyspace_name = aws_keyspaces_keyspace.this.name
  table_name    = each.key

  capacity_specification {
    throughput_mode = "PAY_PER_REQUEST"
  }

  schema_definition {
    dynamic "column" {
      for_each = each.value.columns

      content {
        name = column.value.name
        type = column.value.type
      }
    }

    dynamic "partition_key" {
      for_each = each.value.partition_key

      content {
        name = partition_key.value
      }
    }

    dynamic "clustering_key" {
      for_each = each.value.clustering_key

      content {
        name     = clustering_key.value
        order_by = "ASC"
      }
    }
  }

  tags = var.tags
}