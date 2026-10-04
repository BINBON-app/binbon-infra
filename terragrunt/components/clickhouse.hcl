remote_state {
backend="s3"


  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
config={bucket=local.backend.locals.state_bucket,key = "${local.env.locals.environment}/${local.env.locals.region}/${basename(get_original_terragrunt_dir())}/terraform.tfstate",region=local.backend.locals.state_region,encrypt=true,dynamodb_table=local.backend.locals.lock_table
}
}
locals {
 backend=read_terragrunt_config(find_in_parent_folders("backend.hcl"))
env=read_terragrunt_config(find_in_parent_folders("env.hcl"))
 tags={Project="binbon",Environment=local.env.locals.environment,ManagedBy="Terraform"
}
 clickhouse=local.env.locals.clickhouse
 # ClickHouse Cloud management API credentials for the provider block itself -
 # fetched directly from Secrets Manager (seeded once via
 # scripts/bootstrap-secrets.sh), never from a local file or
 # CLICKHOUSE_ORG_ID/CLICKHOUSE_CLOUD_API_KEY/CLICKHOUSE_CLOUD_API_SECRET env
 # var export.
 clickhouse_cloud_api=jsondecode(run_cmd(
   "--terragrunt-quiet",
   "aws", "secretsmanager", "get-secret-value",
   "--secret-id", "binbon-${local.env.locals.environment}-clickhouse-cloud-api",
   "--region", "eu-central-1",
   "--query", "SecretString",
   "--output", "text"
 ))
 # Same secret the `secrets` component publishes into the app-facing
 # CLICKHOUSE_PASSWORD - single source of truth, fetched here too so the
 # actual ClickHouse Cloud service's admin password is set from it instead of
 # a manually-exported TF_VAR_clickhouse_admin_password.
 clickhouse_admin_password=run_cmd(
   "--terragrunt-quiet",
   "aws", "secretsmanager", "get-secret-value",
   "--secret-id", "binbon-${local.env.locals.environment}-clickhouse-admin-password",
   "--region", "eu-central-1",
   "--query", "SecretString",
   "--output", "text"
 )
}
generate "provider" {
path="provider.tf"
 if_exists="overwrite_terragrunt"
 contents=<<EOF
provider "aws" {
  region              = "eu-central-1"
  allowed_account_ids = ["${local.backend.locals.account_id}"]
}
provider "clickhouse" {
  organization_id = "${local.clickhouse_cloud_api.org_id}"
  token_key        = "${local.clickhouse_cloud_api.api_key}"
  token_secret     = "${local.clickhouse_cloud_api.api_secret}"
}
EOF
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
name="binbon-${local.env.locals.environment}",region=local.clickhouse.region,num_replicas=local.clickhouse.num_replicas,min_replica_memory_gb=local.clickhouse.min_replica_memory_gb,max_replica_memory_gb=local.clickhouse.max_replica_memory_gb,idle_scaling=local.clickhouse.idle_scaling,allowed_cidrs=[for ip in dependency.network.outputs.nat_public_ips: "${ip}/32"],password_wo_version=local.clickhouse.password_wo_version,clickhouse_admin_password=local.clickhouse_admin_password,tags=local.tags
}
