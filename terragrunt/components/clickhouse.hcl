remote_state {
backend="s3"


  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
config={bucket="binbon-bootstrap-tfstate-20260820142237684300000001",key = "${local.env.locals.environment}/${local.env.locals.region}/${basename(get_original_terragrunt_dir())}/terraform.tfstate",region="eu-central-1",encrypt=true,dynamodb_table="binbon-bootstrap-tf-lock"
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
 clickhouse=local.env.locals.clickhouse
}
terraform {
source=dirname(find_in_parent_folders("modules/clickhouse/main.tf"))
}
dependency "network" {
config_path="../network"
 mock_outputs={nat_public_ips=["203.0.113.10"]
}
 mock_outputs_allowed_terraform_commands=["init","validate","plan","destroy"]
}
inputs={
name="binbon-${local.env.locals.environment}",region=local.clickhouse.region,num_replicas=local.clickhouse.num_replicas,min_replica_memory_gb=local.clickhouse.min_replica_memory_gb,max_replica_memory_gb=local.clickhouse.max_replica_memory_gb,idle_scaling=local.clickhouse.idle_scaling,allowed_cidrs=[for ip in dependency.network.outputs.nat_public_ips: "${ip}/32"],password_wo_version=local.clickhouse.password_wo_version,tags=local.tags
}
