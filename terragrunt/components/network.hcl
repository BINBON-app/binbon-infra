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
source=dirname(find_in_parent_folders("modules/network/main.tf")) 
}
inputs={
name="binbon-${local.env.locals.environment}",cidr_block=local.env.locals.environment == "dev" ? "10.20.0.0/16" : local.env.locals.environment == "staging" ? "10.30.0.0/16" : "10.40.0.0/16",azs=["eu-central-1a","eu-central-1b","eu-central-1c"],single_nat_gateway=local.env.locals.environment == "dev",tags=local.tags 
}
