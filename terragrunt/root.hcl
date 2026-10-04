locals {
 backend = read_terragrunt_config(find_in_parent_folders("backend.hcl"))
 state_bucket = local.backend.locals.state_bucket
 lock_table = local.backend.locals.lock_table
}
remote_state {
backend = "s3"
 config = {
bucket=local.state_bucket, key="${path_relative_to_include()}/terraform.tfstate", region="eu-central-1", encrypt=true, dynamodb_table=local.lock_table 
} 
}
generate "provider" {
path="provider.tf"
 if_exists="overwrite_terragrunt"
 contents=<<EOF
provider "aws" {
region = "eu-central-1" 
}
EOF
}
