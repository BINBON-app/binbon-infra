remote_state {
backend="s3"
 

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
config={bucket="binbon-bootstrap-tfstate-20260906083634558300000001",key = "${local.env.locals.environment}/${local.env.locals.region}/${basename(get_original_terragrunt_dir())}/terraform.tfstate",region="eu-central-1",encrypt=true,dynamodb_table="binbon-bootstrap-tf-lock"
} 
}
locals {
env=read_terragrunt_config(find_in_parent_folders("env.hcl"))
 tags={Project="binbon",Environment=local.env.locals.environment,ManagedBy="Terraform"
}
 redpanda=local.env.locals.redpanda
 # Redpanda Cloud API credentials for the provider block itself - fetched
 # directly from Secrets Manager (seeded once via
 # scripts/bootstrap-secrets.sh), never from a local file or
 # REDPANDA_CLIENT_ID/REDPANDA_CLIENT_SECRET env var export.
 redpanda_creds=jsondecode(run_cmd(
   "--terragrunt-quiet",
   "aws", "secretsmanager", "get-secret-value",
   "--secret-id", "binbon-${local.env.locals.environment}-redpanda-cloud-api",
   "--region", "eu-central-1",
   "--query", "SecretString",
   "--output", "text"
 ))
 # Every service_user's password, fetched by name from its own
 # binbon-<env>-redpanda-<service> secret (created by
 # scripts/bootstrap-secrets.sh) - eliminates the local *.auto.tfvars.json /
 # TF_VAR_service_user_passwords file this used to require.
 service_user_passwords={
   for name in keys(local.redpanda.service_users) :
   name => run_cmd(
     "--terragrunt-quiet",
     "aws", "secretsmanager", "get-secret-value",
     "--secret-id", "binbon-${local.env.locals.environment}-redpanda-${name}",
     "--region", "eu-central-1",
     "--query", "SecretString",
     "--output", "text"
   )
 }
}
generate "provider" {
path="provider.tf"
 if_exists="overwrite_terragrunt"
 contents=<<EOF
provider "aws" { region = "eu-central-1" }
provider "redpanda" {
  client_id     = "${local.redpanda_creds.client_id}"
  client_secret = "${local.redpanda_creds.client_secret}"
}
EOF
}
terraform {
source=dirname(find_in_parent_folders("modules/redpanda/main.tf"))
}
inputs={
name="binbon-${local.env.locals.environment}",region=local.redpanda.region,aws_account_id=local.env.locals.account_id,enable_private_link=local.redpanda.enable_private_link,public_networking=local.redpanda.public_networking,private_networking=local.redpanda.private_networking,allow_cluster_deletion=local.redpanda.allow_cluster_deletion,allow_private_link_deletion=local.redpanda.allow_private_link_deletion,allow_topic_deletion=local.redpanda.allow_topic_deletion,allow_user_deletion=try(local.redpanda.allow_user_deletion,false),allow_acl_deletion=try(local.redpanda.allow_acl_deletion,false),topics=local.redpanda.topics,service_users=local.redpanda.service_users,service_user_passwords=local.service_user_passwords,tags=local.tags
}
