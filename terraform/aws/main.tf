locals {
  server_image = "${var.image_registry}/server:${var.image_tag}"
  web_image    = "${var.image_registry}/web:${var.image_tag}"

  web_url = "https://${var.web_host}"
  api_url = "https://${var.api_host}"
  mcp_url = "https://${var.mcp_host}"

  # Mirrors deploy/helm/activate/templates/_helpers.tpl (activate.serverEnv).
  server_environment = merge(
    {
      ACTIVATE_EDITION       = var.edition
      NODE_ENV               = "production"
      PORT                   = "3000"
      METRICS_PORT           = "9464"
      LOG_LEVEL              = var.log_level
      WEB_URL                = local.web_url
      PUBLIC_API_URL         = local.mcp_url
      CORS_ORIGINS           = local.web_url
      DB_SSL_MODE            = "verify-full"
      MIGRATIONS_RUN_ON_BOOT = "false"
      AUTH_PROVIDER          = var.auth_provider
      AUTH_ROLE_MAP          = jsonencode(var.role_mapping)
      AUTH_PASSWORD_LOGIN    = tostring(var.password_login)
      LEAD_EMAIL_DOMAINS     = join(",", var.lead_email_domains)
      AI_PROVIDER            = "live"
      ANTHROPIC_MODEL        = var.anthropic_model
      ANTHROPIC_FAST_MODEL   = var.anthropic_fast_model
      LIBRARY_CLONES_DIR     = "/data/marketplace-clones"
      LIBRARY_WORK_DIR       = "/data/marketplace-work"
      MCP_APP_HTML           = "/mcp-app/dist/app.html"
      WORKER_TIMEZONE        = var.worker_timezone
      TELEMETRY_ENABLED      = "false"
      UPDATE_CHECK_ENABLED   = tostring(var.update_check_enabled)
    },
    var.org == null ? {} : {
      ACTIVATE_ORG_NAME           = var.org.name
      ACTIVATE_ORG_SLUG           = var.org.slug
      ACTIVATE_ORG_EMAIL_DOMAINS  = join(",", var.org.email_domains)
      ACTIVATE_ORG_INITIAL_ADMINS = join(",", var.org.initial_admins)
      ACTIVATE_ORG_SEATS          = tostring(var.org.seats)
    },
    var.marketplace == null ? {} : {
      LIBRARY_PROVIDER       = var.marketplace.provider
      LIBRARY_REPOSITORY     = var.marketplace.repository
      LIBRARY_REMOTE_URL     = var.marketplace.remote_url
      LIBRARY_DEFAULT_BRANCH = var.marketplace.default_branch
    },
    var.auth_provider == "oidc" ? {
      AUTH_OIDC_ISSUER    = var.oidc.issuer
      AUTH_OIDC_CLIENT_ID = var.oidc.client_id
      AUTH_OIDC_SCOPES    = var.oidc.scopes
      AUTH_GROUPS_CLAIM   = var.oidc.groups_claim
    } : {},
    length(var.claude_enterprise_secret_arns) > 0 ? { ALLOW_PLATFORM_ENTERPRISE_KEYS = "true" } : {},
    var.https_proxy != "" ? { HTTPS_PROXY = var.https_proxy, NO_PROXY = var.no_proxy } : {},
    var.extra_environment,
  )

  # name -> Secrets Manager ARN (optionally with :json-key:: suffix) for the server containers.
  server_secrets = merge(
    {
      DB                   = aws_secretsmanager_secret.db.arn
      ACTIVATE_SECRETS_KEY = var.encryption_key_secret_arn
      ANTHROPIC_API_KEY    = var.anthropic_api_key_secret_arn
    },
    var.license_secret_arn == null ? {} : { ACTIVATE_LICENSE = var.license_secret_arn },
    var.marketplace == null ? {} : { LIBRARY_GIT_TOKEN = var.marketplace.git_token_secret },
    var.extra_secrets,
    var.encryption_previous_key_secret_arn == null ? {} : { ACTIVATE_SECRETS_KEY_PREVIOUS = var.encryption_previous_key_secret_arn },
    var.auth_provider == "oidc" ? { AUTH_OIDC_CLIENT_SECRET = var.oidc.client_secret_arn } : {
      WORKOS_API_KEY                                        = "${var.workos_secret_arn}:api-key::"
      WORKOS_CLIENT_ID                                      = "${var.workos_secret_arn}:client-id::"
    },
    var.workos_webhook_secret_arn == null ? {} : { WORKOS_WEBHOOK_SECRET = var.workos_webhook_secret_arn },
    { for k, v in var.claude_enterprise_secret_arns : upper("CLAUDE_${k}_API_KEY") => v },
  )

  secret_arns = distinct([for v in values(local.server_secrets) : split(":json-key:", replace(v, "/:([^:]*)::$/", ":json-key:$1"))[0]])

  web_environment = merge({
    NODE_ENV = "production"
    PORT     = "3000"
    HOSTNAME = "0.0.0.0"
    WEB_URL  = local.web_url
    # The web app proxies /api from its own origin. Internal balancer: plain HTTP inside the VPC. Internet-facing
    # balancer: the task's traffic leaves through the NAT gateway, so it goes to the public API host over HTTPS.
    API_URL        = var.people_alb_internet_facing ? local.api_url : "http://${aws_lb.internal.dns_name}"
    PUBLIC_API_URL = local.api_url # where the browser is sent to sign in (OIDC)
    AUTH_PROVIDER  = var.auth_provider
  }, var.web_extra_environment)
}

resource "aws_ecs_cluster" "this" {
  name = var.name
  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.edition != "self-hosted" || (var.license_secret_arn != null && var.marketplace != null && var.org != null)
      error_message = "The self-hosted edition needs license_secret_arn, marketplace and org."
    }
    precondition {
      condition     = var.auth_provider != "oidc" || var.oidc != null
      error_message = "auth_provider=oidc needs the oidc object."
    }
    precondition {
      condition     = var.auth_provider != "workos" || var.workos_secret_arn != null
      error_message = "auth_provider=workos needs workos_secret_arn."
    }
  }

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/activate/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# --- IAM ----------------------------------------------------------------

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_secrets" {
  name = "read-secrets"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = concat(local.secret_arns, var.registry_credentials_secret_arn == null ? [] : [var.registry_credentials_secret_arn])
    }]
  })
}

resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

# `activate doctor` and `support-bundle` are run through ECS Exec.
resource "aws_iam_role_policy" "task_exec" {
  name = "ecs-exec"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
      Resource = "*"
    }]
  })
}

# --- Security groups ----------------------------------------------------

resource "aws_security_group" "internal_alb" {
  name        = "${var.name}-internal-alb"
  description = "Web app and API for people on the private network"
  vpc_id      = var.vpc_id
  tags        = var.tags

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.internal_alb_ingress_cidrs
  }
  ingress {
    description = "The web app /api proxy reaches the API over the internal ALB"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "mcp_alb" {
  name        = "${var.name}-mcp-alb"
  description = "MCP and OAuth for Claude, restricted by WAF to Anthropic ranges"
  vpc_id      = var.vpc_id
  tags        = var.tags

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "server" {
  name        = "${var.name}-server"
  description = "api and worker tasks"
  vpc_id      = var.vpc_id
  tags        = var.tags

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.internal_alb.id, aws_security_group.mcp_alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "web" {
  name        = "${var.name}-web"
  description = "web tasks"
  vpc_id      = var.vpc_id
  tags        = var.tags

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.internal_alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_vpc" "this" {
  id = var.vpc_id
}
