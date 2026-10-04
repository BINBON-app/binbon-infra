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
source=dirname(find_in_parent_folders("modules/waf/main.tf"))
}
# Attached to the ALB (components/alb.hcl). SizeRestrictions_BODY only counts:
# it blocks bodies over 8 KB, and multipart uploads go through api-gateway.
inputs={
name="binbon-${local.env.locals.environment}-regional",scope="REGIONAL",rate_limit=2000,common_rules_count_only=["SizeRestrictions_BODY"],tags=local.tags
}
