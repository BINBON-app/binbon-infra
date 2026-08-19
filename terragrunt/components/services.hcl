remote_state {
backend="s3"
 

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
config={bucket="binbon-bootstrap-tfstate-20260818130211924200000001",key = "${local.env.locals.environment}/${local.env.locals.region}/${basename(get_original_terragrunt_dir())}/terraform.tfstate",region="eu-central-1",encrypt=true,dynamodb_table="binbon-bootstrap-tf-lock"
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
}
terraform {
source=dirname(find_in_parent_folders("modules/ecs-services/main.tf")) 
}
dependency "network" {
config_path="../network"
 mock_outputs={vpc_id="vpc-00000000",app_subnet_ids=["subnet-00000000","subnet-00000001"]
}
 mock_outputs_allowed_terraform_commands=["init","validate","plan","destroy"] 
}
dependency "foundation" {
config_path="../foundation"
 mock_outputs={kms_key_arn="arn:aws:kms:eu-central-1:123456789012:key/mock"
}
 mock_outputs_allowed_terraform_commands=["init","validate","plan","destroy"]
}
dependency "alb" {
config_path="../alb"
 mock_outputs={task_security_group_id="sg-00000000",listener_arn="arn:aws:elasticloadbalancing:eu-central-1:123456789012:listener/app/mock/mock"
}
 mock_outputs_allowed_terraform_commands=["init","validate","plan","destroy"] 
}
dependency "data" {
config_path="../data"
 mock_outputs={aurora_endpoint="mock",redis_endpoint="mock",aurora_secret_arn="arn:aws:secretsmanager:eu-central-1:123456789012:secret:mock",keyspace_name="mock"
}
 mock_outputs_allowed_terraform_commands=["init","validate","plan","destroy"] 
}
dependency "cognito" {
config_path="../cognito"
 mock_outputs={user_pool_id="eu-central-1_mock",client_id="mock-client-id",issuer_url="https://cognito-idp.eu-central-1.amazonaws.com/eu-central-1_mock"
}
 mock_outputs_allowed_terraform_commands=["init","validate","plan","destroy"] 
}
dependency "redpanda" {
  config_path = "../redpanda"

  mock_outputs = {
    cluster_api_url = "https://mock.redpanda.cloud"

    service_usernames = {
      for username, config in local.env.locals.redpanda.service_users :
      username => "mock-${username}"
    }
  }

  mock_outputs_allowed_terraform_commands = [
    "init",
    "validate",
    "plan",
    "destroy"
  ]
}
inputs = {
  name                   = "binbon-${local.env.locals.environment}"
  vpc_id                 = dependency.network.outputs.vpc_id
  app_subnet_ids         = dependency.network.outputs.app_subnet_ids
  task_security_group_id = dependency.alb.outputs.task_security_group_id
  listener_arn           = dependency.alb.outputs.listener_arn
  kms_key_arn            = dependency.foundation.outputs.kms_key_arn

  services = {
    for name, service in local.env.locals.services :
    name => merge(service, {
      environment = merge(
        service.environment,
        {
          COGNITO_USER_POOL_ID     = dependency.cognito.outputs.user_pool_id
          COGNITO_CLIENT_ID        = dependency.cognito.outputs.client_id
          COGNITO_ISSUER           = dependency.cognito.outputs.issuer_url
          REDPANDA_CLUSTER_API_URL = dependency.redpanda.outputs.cluster_api_url
        },
        service.redpanda_user == null ? {} : {
          REDPANDA_SASL_USERNAME = dependency.redpanda.outputs.service_usernames[service.redpanda_user]
        }
      )
    })
  }

  tags = local.tags
}
