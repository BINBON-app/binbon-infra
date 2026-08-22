locals {
state_bucket = "binbon-bootstrap-tfstate-20260822072816113700000001"
 lock_table = "binbon-bootstrap-tf-lock" 
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
