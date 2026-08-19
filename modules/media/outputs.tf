output "bucket_name" {
  value = aws_s3_bucket.media.id
}
output "bucket_arn" {
  value = aws_s3_bucket.media.arn
}
output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.media.domain_name
}
output "mediaconvert_role_arn" {
  value = aws_iam_role.mediaconvert.arn
}
