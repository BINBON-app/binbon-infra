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
 redpanda=local.env.locals.redpanda 
}
terraform {
source=dirname(find_in_parent_folders("modules/redpanda-vpc-endpoint/main.tf")) 
}
dependency "network" {
  config_path = "../network"

  mock_outputs = {
    vpc_id = "vpc-00000000000000000"

    app_subnet_ids = [
      "subnet-00000000000000001",
      "subnet-00000000000000002",
      "subnet-00000000000000003"
    ]
  }

  mock_outputs_allowed_terraform_commands = [
    "init",
    "validate",
    "plan",
    "destroy"
  ]
}
dependency "alb" {
  config_path = "../alb"

  mock_outputs = {
    task_security_group_id = "sg-00000000000000000"
  }

  mock_outputs_allowed_terraform_commands = [
    "init",
    "validate",
    "plan",
    "destroy"
  ]
}
dependency "redpanda" {
  config_path = "../redpanda"

  mock_outputs = {
    private_link_service_name = "com.amazonaws.vpce.${local.env.locals.region}.vpce-svc-00000000000000000"

    private_link_availability_zones = [
      "mock-az-id"
    ]
  }

  mock_outputs_allowed_terraform_commands = [
    "init",
    "validate",
    "plan",
    "destroy"
  ]
}
inputs = {
  name = "binbon-${local.env.locals.environment}"

  vpc_id = dependency.network.outputs.vpc_id

  subnet_ids = dependency.network.outputs.app_subnet_ids

  task_security_group_id = dependency.alb.outputs.task_security_group_id

  service_name = dependency.redpanda.outputs.private_link_service_name

  service_availability_zone_ids = dependency.redpanda.outputs.private_link_availability_zones

  private_dns_enabled = true

  tags = local.tags
}