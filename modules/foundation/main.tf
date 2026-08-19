data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

resource "aws_kms_key" "this" {
  description         = "${var.name} application encryption"
  enable_key_rotation = true

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"

        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }

        Action   = "kms:*"
        Resource = "*"
      },

      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"

        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }

        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]

        Resource = "*"

        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = var.name
    }
  )
}
resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}-app"
  target_key_id = aws_kms_key.this.key_id
}
resource "aws_ecr_repository" "this" {
  for_each             = var.repositories
  name                 = "${var.name}/${each.value}"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.this.arn
  }
  tags = var.tags
}
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name
  policy = jsonencode({ rules = [{ rulePriority = 1, description = "Keep last 30 images", selection = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 30
    }, action = { type = "expire"
    }
    }]
  })
}
