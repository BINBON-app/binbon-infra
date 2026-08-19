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
source=dirname(find_in_parent_folders("modules/redpanda/main.tf")) 
}
inputs={
name="binbon-${local.env.locals.environment}",region=local.redpanda.region,aws_account_id=local.env.locals.account_id,enable_private_link=local.redpanda.enable_private_link,public_networking=local.redpanda.public_networking,private_networking=local.redpanda.private_networking,allow_cluster_deletion=local.redpanda.allow_cluster_deletion,allow_private_link_deletion=local.redpanda.allow_private_link_deletion,allow_topic_deletion=local.redpanda.allow_topic_deletion,allow_user_deletion=try(local.redpanda.allow_user_deletion,false),allow_acl_deletion=try(local.redpanda.allow_acl_deletion,false),topics=local.redpanda.topics,service_users=local.redpanda.service_users,tags=local.tags 
}
