terraform {
  source = "../../modules/bootstrap"
}
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = "provider \"aws\" { region = \"eu-central-1\" }"
}
inputs = {
  name = "binbon-bootstrap", tags = { ManagedBy = "Terraform", Project = "binbon"
  }
}
