remote_state {
backend="s3"
 

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
config={bucket="binbon-bootstrap-tfstate-20261004100200286800000001",key = "${local.env.locals.environment}/${local.env.locals.region}/${basename(get_original_terragrunt_dir())}/terraform.tfstate",region="eu-central-1",encrypt=true,dynamodb_table="binbon-bootstrap-tf-lock"
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
 cognito=local.env.locals.cognito 
}
terraform {
source=dirname(find_in_parent_folders("modules/cognito/main.tf"))
}
dependency "waf_regional" {
config_path="../waf-regional"
 mock_outputs={web_acl_arn="arn:aws:wafv2:eu-central-1:123456789012:regional/webacl/mock/00000000-0000-0000-0000-000000000000"
}
 mock_outputs_allowed_terraform_commands=["init","validate","plan","destroy"]
}
inputs={
name="binbon-${local.env.locals.environment}",hosted_domain_prefix=local.cognito.hosted_domain_prefix,custom_domain=local.cognito.custom_domain,custom_domain_certificate_arn=local.cognito.custom_domain_certificate_arn,callback_urls=local.cognito.callback_urls,logout_urls=local.cognito.logout_urls,mfa_configuration=local.cognito.mfa_configuration,allow_self_signup=local.cognito.allow_self_signup,generate_client_secret=local.cognito.generate_client_secret,create_identity_pool=local.cognito.create_identity_pool,waf_web_acl_arn=dependency.waf_regional.outputs.web_acl_arn,groups=local.cognito.groups,api_scopes=local.cognito.api_scopes,lambda_triggers=local.cognito.lambda_triggers,tags=local.tags
}
