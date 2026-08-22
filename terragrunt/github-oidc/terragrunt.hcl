remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = "binbon-bootstrap-tfstate-20260822072816113700000001"
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

  github_org      = "BINBON-app"
  monorepo_name   = "official-backend-rust"
  infra_repo_name = "binbon-infra"

  tags = { Project = "binbon", ManagedBy = "Terraform" }
}
