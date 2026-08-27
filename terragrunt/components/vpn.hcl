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
source=dirname(find_in_parent_folders("modules/vpn/main.tf"))
}
dependency "network" {
config_path="../network"
 mock_outputs={vpc_id="vpc-00000000",public_subnet_ids=["subnet-00000000","subnet-00000001"]
}
 mock_outputs_allowed_terraform_commands=["init","validate","plan","destroy"]
}
dependency "alb" {
config_path="../alb"
 mock_outputs={task_security_group_id="sg-00000000"
}
 mock_outputs_allowed_terraform_commands=["init","validate","plan","destroy"]
}
inputs={
name="binbon-${local.env.locals.environment}",vpc_id=dependency.network.outputs.vpc_id,public_subnet_id=dependency.network.outputs.public_subnet_ids[0],app_security_group_id=dependency.alb.outputs.task_security_group_id,ami_id=local.env.locals.vpn.ami_id,instance_type=local.env.locals.vpn.instance_type,key_name=local.env.locals.vpn.key_name,admin_cidrs=local.env.locals.vpn.admin_cidrs,tags=local.tags
}
