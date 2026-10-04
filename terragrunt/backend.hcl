# The AWS account this tree deploys to, and that account's Terraform state
# backend. Every component and github-oidc read it with
# find_in_parent_folders("backend.hcl"), so moving to another account means
# changing this file, not 16 copies of the bucket name.
#
# - account_id: the generated aws providers carry allowed_account_ids, so a
#   shell pointed at a different account fails at plan time instead of
#   building there. It also builds the ECR image URIs and Redpanda's
#   PrivateLink principal.
# - state_bucket / lock_table: the outputs of terragrunt/bootstrap, applied
#   once per account.
#
# An environment in a different account can carry its own backend.hcl in
# terragrunt/envs/<env>/; the nearest file wins.
locals {
  account_id   = "922640336342"
  state_bucket = "binbon-bootstrap-tfstate-20261004100200286800000001"
  lock_table   = "binbon-bootstrap-tf-lock"
  state_region = "eu-central-1"
}
