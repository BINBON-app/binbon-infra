locals {
  topic_acls = flatten([
    for user_name, user in var.service_users : [
      for topic_name, operations in user.topic_permissions : [
        for operation in operations : {
          key           = "${user_name}:topic:${topic_name}:${operation}"
          user_name     = user_name
          resource_name = topic_name
          operation     = operation

        }
      ]
    ]
  ])
  group_acls = flatten([
    for user_name, user in var.service_users : [
      for group_name, operations in user.group_permissions : [
        for operation in operations : {
          key           = "${user_name}:group:${group_name}:${operation}"
          user_name     = user_name
          resource_name = group_name
          operation     = operation

        }
      ]
    ]
  ])
  cluster_acls = flatten([
    for user_name, user in var.service_users : [
      for operation in user.cluster_permissions : {
        key       = "${user_name}:cluster:${operation}"
        user_name = user_name
        operation = operation

      }
    ]
  ])
}

resource "redpanda_resource_group" "this" {
  name = var.name
}

resource "redpanda_serverless_private_link" "this" {
  count             = var.enable_private_link ? 1 : 0
  name              = "${var.name}-private-link"
  resource_group_id = redpanda_resource_group.this.id
  cloud_provider    = "aws"
  serverless_region = var.region
  allow_deletion    = var.allow_private_link_deletion
  aws_config = {
    allowed_principals = ["arn:aws:iam::${var.aws_account_id}:root"]
  }
}

resource "redpanda_serverless_cluster" "this" {
  name              = var.name
  resource_group_id = redpanda_resource_group.this.id
  serverless_region = var.region
  allow_deletion    = var.allow_cluster_deletion
  private_link_id   = var.enable_private_link ? redpanda_serverless_private_link.this[0].id : null
  networking_config = {
    public  = var.public_networking
    private = var.enable_private_link ? var.private_networking : "STATE_DISABLED"

  }
}

resource "redpanda_topic" "this" {
  for_each           = var.topics
  name               = each.key
  partition_count    = each.value.partitions
  replication_factor = each.value.replication_factor
  configuration      = each.value.configuration
  cluster_api_url    = redpanda_serverless_cluster.this.cluster_api_url
  allow_deletion     = var.allow_topic_deletion
}

resource "redpanda_user" "this" {
  for_each            = var.service_users
  name                = each.key
  password_wo         = var.service_user_passwords[each.key]
  password_wo_version = each.value.password_wo_version
  mechanism           = "scram-sha-256"
  cluster_api_url     = redpanda_serverless_cluster.this.cluster_api_url
  allow_deletion      = var.allow_user_deletion
  lifecycle {
    precondition {
      condition     = contains(keys(var.service_user_passwords), each.key)
      error_message = "Pass a password for every service user using TF_VAR_service_user_passwords."

    }

  }
}

resource "redpanda_acl" "topic" {
  for_each = {
    for acl in local.topic_acls : acl.key => acl
  }
  resource_type         = "TOPIC"
  resource_name         = each.value.resource_name
  resource_pattern_type = each.value.resource_name == "*" ? "LITERAL" : "LITERAL"
  principal             = "User:${redpanda_user.this[each.value.user_name].name}"
  host                  = "*"
  operation             = each.value.operation
  permission_type       = "ALLOW"
  cluster_api_url       = redpanda_serverless_cluster.this.cluster_api_url
  allow_deletion        = var.allow_acl_deletion
}

resource "redpanda_acl" "group" {
  for_each = {
    for acl in local.group_acls : acl.key => acl
  }
  resource_type         = "GROUP"
  resource_name         = each.value.resource_name
  resource_pattern_type = "LITERAL"
  principal             = "User:${redpanda_user.this[each.value.user_name].name}"
  host                  = "*"
  operation             = each.value.operation
  permission_type       = "ALLOW"
  cluster_api_url       = redpanda_serverless_cluster.this.cluster_api_url
  allow_deletion        = var.allow_acl_deletion
}

resource "redpanda_acl" "cluster" {
  for_each = {
    for acl in local.cluster_acls : acl.key => acl
  }
  resource_type         = "CLUSTER"
  resource_name         = "kafka-cluster"
  resource_pattern_type = "LITERAL"
  principal             = "User:${redpanda_user.this[each.value.user_name].name}"
  host                  = "*"
  operation             = each.value.operation
  permission_type       = "ALLOW"
  cluster_api_url       = redpanda_serverless_cluster.this.cluster_api_url
  allow_deletion        = var.allow_acl_deletion
}
