data "aws_region" "current" {
}
resource "aws_ecs_cluster" "this" {
  name = var.name
  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"
      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.exec.name
      }
    }
  }
  tags = var.tags
}
resource "aws_cloudwatch_log_group" "exec" {
  name              = "/ecs/${var.name}/exec"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}
resource "aws_cloudwatch_log_group" "service" {
  for_each          = var.services
  name              = "/ecs/${var.name}/${each.key}"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}
resource "aws_iam_role" "execution" {
  name = "${var.name}-ecs-execution"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com"
    }, Action = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}
resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy" "execution_secrets" {
  role = aws_iam_role.execution.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["secretsmanager:GetSecretValue", "kms:Decrypt"], Resource = "*"
    }]
  })
}
resource "aws_iam_role" "task" {
  for_each           = var.services
  name               = "${var.name}-${each.key}-task"
  assume_role_policy = aws_iam_role.execution.assume_role_policy
  tags = merge(var.tags, { Service = each.key
  })
}
resource "aws_iam_role_policy" "task" {
  for_each = { for k, v in var.services : k => v if v.task_policy_json != null
  }
  name   = "service-access"
  role   = aws_iam_role.task[each.key].id
  policy = each.value.task_policy_json
}
# ECS Exec (aws ecs execute-command) needs the TASK role - not the execution
# role - to open an SSM Session Manager channel, plus KMS access to the
# exec log group's key (execute_command_configuration below). Without this,
# every exec attempt fails with "execute command was not enabled... or the
# agent isn't running", regardless of enable_execute_command on the service.
resource "aws_iam_role_policy" "task_exec" {
  for_each = var.services
  name     = "ecs-exec"
  role     = aws_iam_role.task[each.key].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    {
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      Resource = "*"
    },
    {
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
      Resource = var.kms_key_arn
    },
  ] })
}
resource "aws_lb_target_group" "this" {
  for_each    = { for k, v in var.services : k => v if length(v.path_patterns) > 0 }
  name        = substr("${var.name}-${each.key}", 0, 32)
  port        = each.value.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id
  health_check {
    path    = each.value.health_check_path
    matcher = "200-399"
  }
  tags = merge(var.tags, { Service = each.key
  })
}
resource "aws_lb_listener_rule" "this" {
  for_each     = aws_lb_target_group.this
  listener_arn = var.listener_arn
  priority     = 100 + index(sort(keys(var.services)), each.key)
  action {
    type             = "forward"
    target_group_arn = each.value.arn
  }
  condition {
    path_pattern {
      values = var.services[each.key].path_patterns
    }
  }
}
# ECS Service Connect namespace: gives every service in this cluster a
# private DNS name (its own service key) reachable from any other service
# with Service Connect enabled, without a separate service-mesh to run.
# Fixes synchronous HTTP/gRPC calls between services, which previously had
# no way to resolve each other's address from inside an awsvpc-networked
# Fargate task (each service's own default fell back to localhost).
resource "aws_service_discovery_http_namespace" "this" {
  name = "${var.name}.internal"
  tags = var.tags
}
resource "aws_ecs_task_definition" "this" {
  for_each = var.services

  # Must match the "<service>-<environment>" family name the backend repo's
  # deploy workflow looks up via `aws ecs describe-task-definition`.
  family                   = "${each.key}-${var.environment}"
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn      = aws_iam_role.task[each.key].arn

  container_definitions = jsonencode([
    {
      name      = each.key
      image     = each.value.image
      essential = true

      portMappings = [
        {
          name          = each.key
          containerPort = each.value.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        for k, v in each.value.environment : {
          name  = k
          value = v
        }
      ]

      secrets = [
        for k, v in each.value.secret_arns : {
          name      = k
          valueFrom = v
        }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${each.value.container_port}${each.value.health_check_path} || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }

      logConfiguration = {
        logDriver = "awslogs"

        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.service[each.key].name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = merge(
    var.tags,
    {
      Service = each.key
    }
  )
}
resource "aws_ecs_service" "this" {
  for_each = var.services
  # Matches the "<service>-<environment>" task-definition family pattern
  # (see aws_ecs_task_definition.this.family above) and what the backend
  # repo's deploy workflow looks up.
  name                   = "${each.key}-${var.environment}"
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.this[each.key].arn
  desired_count          = each.value.desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [var.task_security_group_id]
    assign_public_ip = false
  }
  # Every service is discoverable at http://<service-key>:<container_port>
  # from any other service in the cluster - see aws_service_discovery_http_namespace.this.
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.this.arn
    service {
      port_name      = each.key
      discovery_name = each.key
      client_alias {
        port     = each.value.container_port
        dns_name = each.key
      }
    }
  }
  dynamic "load_balancer" {
    for_each = contains(keys(aws_lb_target_group.this), each.key) ? [aws_lb_target_group.this[each.key]] : []
    content {
      target_group_arn = load_balancer.value.arn
      container_name   = each.key
      container_port   = each.value.container_port
    }
  }
  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }
  tags = merge(var.tags, { Service = each.key
  })
}
resource "aws_appautoscaling_target" "this" {
  for_each           = var.services
  max_capacity       = each.value.max_count
  min_capacity       = each.value.min_count
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}
resource "aws_appautoscaling_policy" "cpu" {
  for_each           = var.services
  name               = "${each.key}-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  target_tracking_scaling_policy_configuration {
    target_value = 60
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
