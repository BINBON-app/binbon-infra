remote_state {
backend="s3"
 

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
config={bucket=local.backend.locals.state_bucket,key = "${local.env.locals.environment}/${local.env.locals.region}/${basename(get_original_terragrunt_dir())}/terraform.tfstate",region=local.backend.locals.state_region,encrypt=true,dynamodb_table=local.backend.locals.lock_table
} 
}
generate "provider" {
path="provider.tf"
 if_exists="overwrite_terragrunt"
 contents=<<EOF
provider "aws" {
  region              = "eu-central-1"
  allowed_account_ids = ["${local.backend.locals.account_id}"]
}
EOF 
}
locals {
 backend=read_terragrunt_config(find_in_parent_folders("backend.hcl"))
env=read_terragrunt_config(find_in_parent_folders("env.hcl"))
 tags={Project="binbon",Environment=local.env.locals.environment,ManagedBy="Terraform"
} 
}
terraform {
source=dirname(find_in_parent_folders("modules/alb/main.tf")) 
}
dependency "network" {
config_path="../network"
 mock_outputs={vpc_id="vpc-00000000",public_subnet_ids=["subnet-00000000","subnet-00000001"]
}
 mock_outputs_allowed_terraform_commands=["init","validate","plan","destroy"] 
}
dependency "waf_regional" {
config_path="../waf-regional"
 mock_outputs={web_acl_arn="arn:aws:wafv2:eu-central-1:123456789012:regional/webacl/mock/00000000-0000-0000-0000-000000000000"
}
 mock_outputs_allowed_terraform_commands=["init","validate","plan","destroy"]
}
inputs={
name="binbon-${local.env.locals.environment}",vpc_id=dependency.network.outputs.vpc_id,public_subnet_ids=dependency.network.outputs.public_subnet_ids,certificate_arn=local.env.locals.alb_certificate_arn,additional_certificate_arns=try(local.env.locals.alb_additional_certificate_arns,[]),waf_web_acl_arn=dependency.waf_regional.outputs.web_acl_arn,tags=local.tags 
}
