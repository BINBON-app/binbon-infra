resource "aws_s3_bucket" "state" {
  bucket_prefix = "${var.name}-tfstate-"
  force_destroy = false
  tags          = var.tags
}
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_dynamodb_table" "lock" {
  name         = "${var.name}-tf-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
  tags = var.tags
}

# Account-global service-linked roles. Each exists once per account and a
# service only creates its own the first time it's used, so a fresh account's
# first apply failed: OpenSearch's CreateDomain answered "you must enable a
# service-linked role ... to access your VPC". Bootstrap runs once per account
# before any component, so the roles live here. In an account where a role
# already exists, import it instead of creating it:
#   terragrunt import 'aws_iam_service_linked_role.this["<service>"]' <role ARN>
resource "aws_iam_service_linked_role" "this" {
  for_each         = var.service_linked_roles
  aws_service_name = each.value
  tags             = var.tags
}
