# One server image, three roles: api (serves), worker (jobs, schedules, marketplace writes), and the
# migrate task that runs before pods roll on every upgrade. Plus the web app.

locals {
  log_config = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.this.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "ecs"
    }
  }
  repository_credentials = var.registry_credentials_secret_arn == null ? null : { credentialsParameter = var.registry_credentials_secret_arn }
  server_env_list        = [for k, v in local.server_environment : { name = k, value = v }]
  server_secret_list     = [for k, v in local.server_secrets : { name = k, valueFrom = v }]
  linux_parameters = {
    initProcessEnabled = true
    capabilities       = { drop = ["ALL"] }
  }
  data_mount = [{ sourceVolume = "data", containerPath = "/data", readOnly = false }]
  tmp_mount  = [{ sourceVolume = "tmp", containerPath = "/tmp", readOnly = false }]
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.name}-api"
  cpu                      = var.api_cpu
  memory                   = var.api_memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  tags                     = var.tags

  runtime_platform {
    cpu_architecture        = var.cpu_architecture
    operating_system_family = "LINUX"
  }

  volume { name = "tmp" }
  volume {
    name = "data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.data.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.data.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([{
    name                   = "api"
    image                  = local.server_image
    essential              = true
    readonlyRootFilesystem = true
    user                   = "1001:1001"
    linuxParameters        = local.linux_parameters
    repositoryCredentials  = local.repository_credentials
    portMappings           = [{ containerPort = 3000, protocol = "tcp" }, { containerPort = 9464, protocol = "tcp" }]
    environment            = concat(local.server_env_list, [{ name = "ACTIVATE_ROLE", value = "api" }])
    secrets                = local.server_secret_list
    mountPoints            = concat(local.tmp_mount, local.data_mount)
    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://127.0.0.1:3000/api/health >/dev/null || exit 1"]
      interval    = 15
      timeout     = 5
      retries     = 3
      startPeriod = 30
    }
    logConfiguration = local.log_config
  }])
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.name}-worker"
  cpu                      = var.worker_cpu
  memory                   = var.worker_memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  tags                     = var.tags

  runtime_platform {
    cpu_architecture        = var.cpu_architecture
    operating_system_family = "LINUX"
  }

  volume { name = "tmp" }
  volume {
    name = "data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.data.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.data.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([{
    name                   = "worker"
    image                  = local.server_image
    essential              = true
    readonlyRootFilesystem = true
    user                   = "1001:1001"
    linuxParameters        = local.linux_parameters
    repositoryCredentials  = local.repository_credentials
    portMappings           = [{ containerPort = 3000, protocol = "tcp" }, { containerPort = 9464, protocol = "tcp" }]
    environment            = concat(local.server_env_list, [{ name = "ACTIVATE_ROLE", value = "worker" }])
    secrets                = local.server_secret_list
    mountPoints            = concat(local.tmp_mount, local.data_mount)
    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://127.0.0.1:3000/api/health >/dev/null || exit 1"]
      interval    = 15
      timeout     = 5
      retries     = 3
      startPeriod = 30
    }
    logConfiguration = local.log_config
  }])
}

# Run before every upgrade: `aws ecs run-task` with this family (see outputs.migrate_command).
resource "aws_ecs_task_definition" "migrate" {
  family                   = "${var.name}-migrate"
  cpu                      = 512
  memory                   = 1024
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  tags                     = var.tags

  runtime_platform {
    cpu_architecture        = var.cpu_architecture
    operating_system_family = "LINUX"
  }

  volume { name = "tmp" }

  container_definitions = jsonencode([{
    name                   = "migrate"
    image                  = local.server_image
    essential              = true
    readonlyRootFilesystem = true
    user                   = "1001:1001"
    linuxParameters        = local.linux_parameters
    repositoryCredentials  = local.repository_credentials
    command                = ["activate", "migrate"]
    environment            = concat(local.server_env_list, [{ name = "ACTIVATE_ROLE", value = "api" }])
    secrets                = local.server_secret_list
    mountPoints            = local.tmp_mount
    logConfiguration       = local.log_config
  }])
}

resource "aws_ecs_task_definition" "web" {
  family                   = "${var.name}-web"
  cpu                      = var.web_cpu
  memory                   = var.web_memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  tags                     = var.tags

  runtime_platform {
    cpu_architecture        = var.cpu_architecture
    operating_system_family = "LINUX"
  }

  volume { name = "tmp" }

  container_definitions = jsonencode([{
    name                   = "web"
    image                  = local.web_image
    essential              = true
    readonlyRootFilesystem = true
    user                   = "1001:1001"
    linuxParameters        = local.linux_parameters
    repositoryCredentials  = local.repository_credentials
    portMappings           = [{ containerPort = 3000, protocol = "tcp" }]
    environment            = [for k, v in local.web_environment : { name = k, value = v }]
    secrets = concat(
      [{ name = "SESSION_SECRET", valueFrom = var.encryption_key_secret_arn }],
      var.auth_provider == "workos" ? [
        { name = "WORKOS_API_KEY", valueFrom = "${var.workos_secret_arn}:api-key::" },
        { name = "WORKOS_CLIENT_ID", valueFrom = "${var.workos_secret_arn}:client-id::" },
        { name = "WORKOS_COOKIE_PASSWORD", valueFrom = var.encryption_key_secret_arn }, # as the chart does
      ] : [],
    )
    mountPoints      = concat(local.tmp_mount, [{ sourceVolume = "tmp", containerPath = "/app/.next/cache", readOnly = false }])
    logConfiguration = local.log_config
  }])
}

resource "aws_ecs_service" "api" {
  name                   = "${var.name}-api"
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.api.arn
  desired_count          = var.api_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true
  propagate_tags         = "SERVICE"
  tags                   = var.tags

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 60

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.server.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 3000
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.mcp_api.arn
    container_name   = "api"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.internal_https, aws_lb_listener.mcp_https, aws_efs_mount_target.data]
}

resource "aws_ecs_service" "worker" {
  name                   = "${var.name}-worker"
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.worker.arn
  desired_count          = 1
  launch_type            = "FARGATE"
  enable_execute_command = true
  propagate_tags         = "SERVICE"
  tags                   = var.tags

  # One worker at a time: schedules fire once, and the marketplace work tree has one writer.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.server.id]
    assign_public_ip = false
  }

  depends_on = [aws_efs_mount_target.data]
}

resource "aws_ecs_service" "web" {
  name                   = "${var.name}-web"
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.web.arn
  desired_count          = var.web_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true
  propagate_tags         = "SERVICE"
  tags                   = var.tags

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 60

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.web.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "web"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.internal_https]
}
