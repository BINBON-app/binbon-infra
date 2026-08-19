data "aws_region" "current" {
}

locals {
  domain                = var.custom_domain != null ? var.custom_domain : var.hosted_domain_prefix
  custom_domain_enabled = var.custom_domain != null
}

resource "aws_cognito_user_pool" "this" {
  name                     = var.name
  mfa_configuration        = var.mfa_configuration
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  user_pool_add_ons {
    advanced_security_mode = "AUDIT"
  }
  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7

  }
  software_token_mfa_configuration {
    enabled = var.mfa_configuration != "OFF"
  }
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1

    }

  }
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your verification code"
    email_message        = "Your verification code is {####}."

  }
  admin_create_user_config {
    allow_admin_create_user_only = !var.allow_self_signup
  }
  dynamic "lambda_config" {
    for_each = length(var.lambda_triggers) == 0 ? [] : [var.lambda_triggers]
    content {
      pre_sign_up          = lookup(lambda_config.value, "pre_sign_up", null)
      post_confirmation    = lookup(lambda_config.value, "post_confirmation", null)
      pre_token_generation = lookup(lambda_config.value, "pre_token_generation", null)
      custom_message       = lookup(lambda_config.value, "custom_message", null)

    }

  }
  tags = var.tags
}

resource "aws_cognito_resource_server" "api" {
  identifier   = "${var.name}-api"
  name         = "${var.name} API"
  user_pool_id = aws_cognito_user_pool.this.id
  dynamic "scope" {
    for_each = var.api_scopes
    content {
      scope_name        = scope.key
      scope_description = scope.value

    }

  }
}

resource "aws_cognito_user_pool_client" "app" {
  name                                          = "${var.name}-web-mobile"
  user_pool_id                                  = aws_cognito_user_pool.this.id
  generate_secret                               = var.generate_client_secret
  prevent_user_existence_errors                 = "ENABLED"
  enable_token_revocation                       = true
  enable_propagate_additional_user_context_data = false
  explicit_auth_flows                           = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_USER_PASSWORD_AUTH"]
  supported_identity_providers                  = ["COGNITO"]
  allowed_oauth_flows_user_pool_client          = length(var.callback_urls) > 0
  allowed_oauth_flows                           = length(var.callback_urls) > 0 ? ["code"] : []
  allowed_oauth_scopes                          = length(var.callback_urls) > 0 ? concat(["openid", "email", "profile"], [for scope in keys(var.api_scopes) : "${aws_cognito_resource_server.api.identifier}/${scope}"]) : []
  callback_urls                                 = var.callback_urls
  logout_urls                                   = var.logout_urls
  access_token_validity                         = 60
  id_token_validity                             = 60
  refresh_token_validity                        = 30
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"

  }
}

resource "aws_cognito_user_pool_domain" "this" {
  domain          = local.domain
  user_pool_id    = aws_cognito_user_pool.this.id
  certificate_arn = local.custom_domain_enabled ? var.custom_domain_certificate_arn : null
  lifecycle {
    precondition {
      condition     = local.domain != null
      error_message = "Set hosted_domain_prefix or custom_domain."

    }
    precondition {
      condition     = !local.custom_domain_enabled || var.custom_domain_certificate_arn != null
      error_message = "A us-east-1 ACM certificate ARN is required for a custom Cognito domain."

    }

  }
}

resource "aws_cognito_user_group" "this" {
  for_each     = var.groups
  user_pool_id = aws_cognito_user_pool.this.id
  name         = each.key
  description  = each.value.description
  precedence   = each.value.precedence
  role_arn     = each.value.role_arn
}

resource "aws_cognito_identity_pool" "this" {
  count                            = var.create_identity_pool ? 1 : 0
  identity_pool_name               = replace("${var.name}-identity", "-", "_")
  allow_unauthenticated_identities = false
  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.app.id
    provider_name           = aws_cognito_user_pool.this.endpoint
    server_side_token_check = true

  }
  tags = var.tags
}

resource "aws_wafv2_web_acl_association" "this" {
  count        = var.waf_web_acl_arn == null ? 0 : 1
  resource_arn = aws_cognito_user_pool.this.arn
  web_acl_arn  = var.waf_web_acl_arn
}
