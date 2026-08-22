remote_state {
backend="s3"
 

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
config={bucket="binbon-bootstrap-tfstate-20260822072816113700000001",key = "${local.env.locals.environment}/${local.env.locals.region}/${basename(get_original_terragrunt_dir())}/terraform.tfstate",region="eu-central-1",encrypt=true,dynamodb_table="binbon-bootstrap-tf-lock"
} 
}
generate "provider" {
path="provider.tf"
 if_exists="overwrite_terragrunt"
 contents="provider \"aws\" { region = \"eu-central-1\" }" 
}
locals {
env=read_terragrunt_config(find_in_parent_folders("env.hcl"))
 tags={Project="binbon",Environment=local.env.locals.environment,ManagedBy="Terraform"
} 
}
terraform {
source=dirname(find_in_parent_folders("modules/edge/main.tf")) 
}
dependency "alb" {
config_path="../alb"
 mock_outputs={dns_name="internal-example.elb.amazonaws.com"
}
 mock_outputs_allowed_terraform_commands=["init","validate","plan","destroy"]
}
dependency "waf_cloudfront" {
config_path="../waf-cloudfront"
 mock_outputs={web_acl_arn="arn:aws:wafv2:us-east-1:123456789012:global/webacl/mock/00000000-0000-0000-0000-000000000000"
}
 mock_outputs_allowed_terraform_commands=["init","validate","plan","destroy"]
}
inputs={
name="binbon-${local.env.locals.environment}",alb_dns_name=dependency.alb.outputs.dns_name,alb_uses_https=local.env.locals.alb_certificate_arn != null,cloudfront_acm_certificate_arn=local.env.locals.cloudfront_certificate_arn,waf_web_acl_arn=dependency.waf_cloudfront.outputs.web_acl_arn,domain_name=local.env.locals.domain_name,route53_zone_id=local.env.locals.route53_zone_id,tags=local.tags
}
