remote_state {
backend="s3"
 

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
config={bucket="binbon-bootstrap-tfstate-20260818130211924200000001",key = "${local.env.locals.environment}/${local.env.locals.region}/${basename(get_original_terragrunt_dir())}/terraform.tfstate",region="eu-central-1",encrypt=true,dynamodb_table="binbon-bootstrap-tf-lock"
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
source=dirname(find_in_parent_folders("modules/alb/main.tf")) 
}
dependency "network" {
config_path="../network"
 mock_outputs={vpc_id="vpc-00000000",public_subnet_ids=["subnet-00000000","subnet-00000001"]
}
 mock_outputs_allowed_terraform_commands=["init","validate","plan","destroy"] 
}
inputs={
name="binbon-${local.env.locals.environment}",vpc_id=dependency.network.outputs.vpc_id,public_subnet_ids=dependency.network.outputs.public_subnet_ids,certificate_arn=local.env.locals.alb_certificate_arn,tags=local.tags 
}
