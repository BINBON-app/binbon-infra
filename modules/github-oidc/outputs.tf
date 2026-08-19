output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}
output "ecs_deploy_role_arn" {
  value = aws_iam_role.ecs_deploy.arn
}
output "terraform_apply_role_arn" {
  value = aws_iam_role.terraform_apply.arn
}
