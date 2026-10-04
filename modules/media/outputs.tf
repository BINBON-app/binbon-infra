output "bucket_name" {
  value = aws_s3_bucket.media.id
}
output "bucket_arn" {
  value = aws_s3_bucket.media.arn
}
# Empty, not null, when CloudFront is off, so consumers can test it as a string.
output "cloudfront_domain_name" {
  value = var.enable_cloudfront ? aws_cloudfront_distribution.media[0].domain_name : ""
}
output "mediaconvert_role_arn" {
  value = aws_iam_role.mediaconvert.arn
}
output "s3_access_key_id" {
  value = aws_iam_access_key.media.id
}
output "s3_secret_access_key" {
  value     = aws_iam_access_key.media.secret
  sensitive = true
}
