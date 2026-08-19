remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = "binbon-bootstrap-tfstate-20260818130211924200000001"
    key            = "github-oidc/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "binbon-bootstrap-tf-lock"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" { region = "eu-central-1" }
    provider "tls" {}
  EOF
}

terraform {
  source = "../../modules/github-oidc"
}

inputs = {
  name = "binbon"

  # REPLACE before applying — see README's CI/CD section.
  github_org      = "REPLACE_ME"
  monorepo_name   = "REPLACE_ME"
  infra_repo_name = "REPLACE_ME"

  tags = { Project = "binbon", ManagedBy = "Terraform" }
}
