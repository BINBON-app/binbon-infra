output "kms_key_arn" {
  value = aws_kms_key.this.arn
}
output "repository_urls" {
  value = {
    for name, repo in aws_ecr_repository.this : name => repo.repository_url
  }
}
