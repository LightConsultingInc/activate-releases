# Two load balancers: one for people (web app + API; internal by default, on the public subnets when
# people_alb_internet_facing is set) and a public one for the connector host, fronted by WAF: /mcp only from Anthropic's egress ranges, /oauth and /.well-known
# open because people sign in there.

resource "aws_lb" "internal" {
  name                       = "${var.name}-internal"
  load_balancer_type         = "application"
  internal                   = !var.people_alb_internet_facing
  security_groups            = [aws_security_group.internal_alb.id]
  subnets                    = var.people_alb_internet_facing ? var.public_subnet_ids : var.private_subnet_ids
  idle_timeout               = 300
  drop_invalid_header_fields = true
  tags                       = var.tags
}

resource "aws_lb_target_group" "web" {
  name        = "${var.name}-web"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id
  tags        = var.tags

  health_check {
    path                = "/api/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "api" {
  name        = "${var.name}-api"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id
  tags        = var.tags

  health_check {
    path                = "/api/ready"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
  deregistration_delay = 30
}

resource "aws_lb_listener" "internal_https" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.internal_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_lb_listener_rule" "api_host" {
  listener_arn = aws_lb_listener.internal_https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
  condition {
    host_header { values = [var.api_host] }
  }
}

# Plain HTTP inside the VPC for the web app's same-origin /api proxy (API_URL). Only reachable from the
# VPC range; an internet-facing people load balancer is reached over HTTPS on the API host instead.
resource "aws_lb_listener" "internal_http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

resource "aws_lb" "mcp" {
  name                       = "${var.name}-mcp"
  load_balancer_type         = "application"
  internal                   = false
  ip_address_type            = var.mcp_alb_ip_address_type
  security_groups            = [aws_security_group.mcp_alb.id]
  subnets                    = var.public_subnet_ids
  idle_timeout               = 1200 # long-lived MCP streams
  drop_invalid_header_fields = true
  tags                       = var.tags
}

resource "aws_lb_listener" "mcp_https" {
  load_balancer_arn = aws_lb.mcp.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.mcp_certificate_arn

  # Only the connector's paths exist on this hostname; everything else is refused.
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "not found"
      status_code  = "404"
    }
  }
}

# A target group can belong to one load balancer only, so the connector gets its own view of the
# api tasks; the api service registers with both.
resource "aws_lb_target_group" "mcp_api" {
  name        = "${var.name}-mcp-api"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id
  tags        = var.tags

  health_check {
    path                = "/api/ready"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
  deregistration_delay = 30
}

resource "aws_lb_listener_rule" "mcp_paths" {
  listener_arn = aws_lb_listener.mcp_https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mcp_api.arn
  }
  condition {
    path_pattern { values = ["/mcp", "/mcp/*", "/oauth/*", "/.well-known/*"] }
  }
}

# --- WAF: Anthropic's ranges only ---------------------------------------

resource "aws_wafv2_ip_set" "anthropic_v4" {
  name               = "${var.name}-anthropic-ipv4"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.mcp_allowed_cidrs
  tags               = var.tags
}

resource "aws_wafv2_ip_set" "anthropic_v6" {
  name               = "${var.name}-anthropic-ipv6"
  scope              = "REGIONAL"
  ip_address_version = "IPV6"
  addresses          = var.mcp_allowed_ipv6_cidrs
  tags               = var.tags
}

resource "aws_wafv2_web_acl" "mcp" {
  name  = "${var.name}-mcp"
  scope = "REGIONAL"
  tags  = var.tags

  default_action {
    block {}
  }

  # Sign-in and discovery are for people and for Claude alike: Claude sends the person's browser to
  # /oauth/authorize, the identity provider returns it to /oauth/callback, and /.well-known is read by
  # Claude. Those paths are open; everything else on this host is for Anthropic's ranges only.
  rule {
    name     = "allow-oauth-and-discovery"
    priority = 0
    action {
      allow {}
    }
    statement {
      or_statement {
        statement {
          byte_match_statement {
            search_string         = "/oauth/"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
        statement {
          byte_match_statement {
            search_string         = "/.well-known/"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "allow-oauth-and-discovery"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "allow-anthropic"
    priority = 1
    action {
      allow {}
    }
    statement {
      or_statement {
        statement {
          ip_set_reference_statement { arn = aws_wafv2_ip_set.anthropic_v4.arn }
        }
        statement {
          ip_set_reference_statement { arn = aws_wafv2_ip_set.anthropic_v6.arn }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "allow-anthropic"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-mcp"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "mcp" {
  resource_arn = aws_lb.mcp.arn
  web_acl_arn  = aws_wafv2_web_acl.mcp.arn
}

# --- DNS ----------------------------------------------------------------

resource "aws_route53_record" "internal" {
  for_each = var.hosted_zone_id == null ? {} : { web = var.web_host, api = var.api_host }
  zone_id  = var.hosted_zone_id
  name     = each.value
  type     = "A"
  alias {
    name                   = aws_lb.internal.dns_name
    zone_id                = aws_lb.internal.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "mcp" {
  for_each = var.hosted_zone_id == null ? {} : { A = "A", AAAA = "AAAA" }
  zone_id  = var.hosted_zone_id
  name     = var.mcp_host
  type     = each.value
  alias {
    name                   = aws_lb.mcp.dns_name
    zone_id                = aws_lb.mcp.zone_id
    evaluate_target_health = true
  }
}
