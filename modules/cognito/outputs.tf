output "user_pool_id" {
  value = aws_cognito_user_pool.this.id
}
output "user_pool_arn" {
  value = aws_cognito_user_pool.this.arn
}
output "issuer_url" {
  value = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.this.id}"
}
output "client_id" {
  value = aws_cognito_user_pool_client.app.id
}
output "client_secret" {
  value = aws_cognito_user_pool_client.app.client_secret

  sensitive = true
}
output "domain" {
  value = aws_cognito_user_pool_domain.this.domain
}
output "identity_pool_id" {
  value = try(aws_cognito_identity_pool.this[0].id, null)
}
