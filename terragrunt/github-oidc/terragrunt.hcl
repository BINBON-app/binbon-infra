locals {
  backend = read_terragrunt_config(find_in_parent_folders("backend.hcl"))
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = local.backend.locals.state_bucket
    key            = "github-oidc/terraform.tfstate"
    region         = local.backend.locals.state_region
    encrypt        = true
    dynamodb_table = local.backend.locals.lock_table
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region              = "eu-central-1"
      allowed_account_ids = ["${local.backend.locals.account_id}"]
    }
    provider "tls" {}
  EOF
}

terraform {
  source = "../../modules/github-oidc"
}

inputs = {
  name = "binbon"

  github_org      = "BINBON-app"
  monorepo_name   = "official-backend-rust"
  infra_repo_name = "binbon-infra"

  tags = { Project = "binbon", ManagedBy = "Terraform" }
}
