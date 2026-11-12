# Self-hosted Activate on AWS: ECS Fargate (web, api, worker), RDS for PostgreSQL, EFS for the
# marketplace clones, an internal ALB for people and a public ALB for Claude's MCP traffic.
# Keys follow the self-host guide at lightci.com/activate/self-host and the Helm chart's values.yaml.

variable "name" {
  description = "Prefix for every resource, e.g. \"activate\"."
  type        = string
  default     = "activate"
}

variable "region" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

# --- Network (yours) ----------------------------------------------------

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "Two or more private subnets for tasks, the database and the internal load balancer."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Two or more public subnets for the MCP load balancer (Claude reaches it from the internet)."
  type        = list(string)
}

variable "internal_alb_ingress_cidrs" {
  description = "Who may reach the web app and API: your office, VPN or peered ranges (0.0.0.0/0 for a public service)."
  type        = list(string)
}

variable "people_alb_internet_facing" {
  description = "Put the web/API load balancer on the public subnets. Self-hosted installs keep it internal (default); LightCI's cloud cells set true."
  type        = bool
  default     = false
}

# --- Images -------------------------------------------------------------

variable "image_registry" {
  description = "Registry path the two images live under (server, web)."
  type        = string
  default     = "ghcr.io/lightconsultinginc/activate"
}

variable "image_tag" {
  description = "Release to run, e.g. \"1.0.0\". Pin a version; upgrades are a change of this value plus the migrate task."
  type        = string
}

variable "registry_credentials_secret_arn" {
  description = "Secrets Manager secret ({\"username\",\"password\"}) for a private registry. Null for a public registry."
  type        = string
  default     = null
}

# --- Hosts and certificates ---------------------------------------------

variable "web_host" {
  description = "Public name of the web app, e.g. activate.example.com (resolves to the internal ALB)."
  type        = string
}

variable "api_host" {
  description = "Public name of the API, e.g. api.activate.example.com (internal ALB)."
  type        = string
}

variable "mcp_host" {
  description = "Name Claude connects to, e.g. mcp.activate.example.com (public ALB)."
  type        = string
}

variable "internal_certificate_arn" {
  description = "ACM certificate covering web_host and api_host."
  type        = string
}

variable "mcp_certificate_arn" {
  description = "ACM certificate covering mcp_host."
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 zone to create the three A records in. Null skips DNS."
  type        = string
  default     = null
}

variable "mcp_allowed_cidrs" {
  description = "Anthropic's published egress ranges, enforced by WAF on the MCP load balancer. Check them at install and at each upgrade: https://platform.claude.com/docs/en/api/ip-addresses"
  type        = list(string)
  default     = ["160.79.104.0/23"]
}

variable "mcp_alb_ip_address_type" {
  description = "ipv4, or dualstack when the public subnets carry an IPv6 CIDR (lets Claude reach the connector over IPv6 too; the WAF already allows Anthropic's IPv6 range)."
  type        = string
  default     = "ipv4"
  validation {
    condition     = contains(["ipv4", "dualstack"], var.mcp_alb_ip_address_type)
    error_message = "mcp_alb_ip_address_type must be ipv4 or dualstack."
  }
}

variable "mcp_allowed_ipv6_cidrs" {
  type    = list(string)
  default = ["2607:6bc0::/48"]
}

# --- Organisation and licence -------------------------------------------

variable "edition" {
  type    = string
  default = "self-hosted"
}

variable "license_secret_arn" {
  description = "Secrets Manager secret whose value is the licence JWT LightCI sent you. Required for the self-hosted edition."
  type        = string
  default     = null
}

variable "org" {
  description = "First-boot organisation (self-hosted). Null in the cloud edition, where leads provision organisations."
  type = object({
    name           = string
    slug           = string
    email_domains  = list(string)
    initial_admins = list(string)
    seats          = optional(number, 0)
  })
  default = null
}

variable "lead_email_domains" {
  description = "Email domains whose people are LightCI leads (cloud cells only). Empty for self-hosted."
  type        = list(string)
  default     = []
}

# --- Identity -----------------------------------------------------------

variable "auth_provider" {
  description = "oidc (your identity provider) or workos (a WorkOS environment you own)."
  type        = string
  default     = "oidc"
  validation {
    condition     = contains(["oidc", "workos"], var.auth_provider)
    error_message = "auth_provider must be oidc or workos."
  }
}

variable "oidc" {
  type = object({
    issuer            = string
    client_id         = string
    client_secret_arn = string
    scopes            = optional(string, "openid profile email")
    groups_claim      = optional(string, "groups")
  })
  default = null
}

variable "workos_secret_arn" {
  description = "Secrets Manager secret with keys api-key and client-id (workos mode)."
  type        = string
  default     = null
}

variable "workos_webhook_secret_arn" {
  description = "Secrets Manager secret holding the WorkOS webhook signing secret (workos mode). Null until the webhook endpoint is registered in WorkOS; role sync and deactivation webhooks are refused until then."
  type        = string
  default     = null
}

variable "role_mapping" {
  description = "IdP groups (names or ids) per Activate role. learner is implicit."
  type        = map(list(string))
  default = {
    admin    = ["activate-admin"]
    sponsor  = ["activate-sponsor"]
    champion = ["activate-champion"]
  }
}

variable "password_login" {
  type    = bool
  default = false
}

# --- Model provider, marketplace, encryption ----------------------------

variable "anthropic_api_key_secret_arn" {
  type = string
}

variable "anthropic_model" {
  type    = string
  default = "claude-opus-5"
}

variable "anthropic_fast_model" {
  type    = string
  default = "claude-sonnet-5"
}

variable "encryption_key_secret_arn" {
  description = "ACTIVATE_SECRETS_KEY: any string (openssl rand -base64 32). Back it up with the database."
  type        = string
}

variable "encryption_previous_key_secret_arn" {
  description = "Set during a key rotation (comma-separated old keys); remove after `activate secrets rotate`."
  type        = string
  default     = null
}

variable "marketplace" {
  description = "The organisation's marketplace remote (self-hosted). Null in the cloud edition, where each organisation connects its own under Settings."
  type = object({
    provider         = string # github | git
    repository       = optional(string, "")
    remote_url       = optional(string, "")
    default_branch   = optional(string, "main")
    git_token_secret = string
  })
  default = null
  validation {
    condition     = try(contains(["github", "git"], var.marketplace.provider), var.marketplace == null)
    error_message = "marketplace.provider must be github or git (a local folder is not a production marketplace)."
  }
}

variable "extra_secrets" {
  description = "Extra secret environment for the server containers: name -> Secrets Manager ARN."
  type        = map(string)
  default     = {}
}

variable "web_extra_environment" {
  type    = map(string)
  default = {}
}

variable "claude_enterprise_secret_arns" {
  description = "Optional platform keys: {analytics, admin, compliance} Secrets Manager ARNs."
  type        = map(string)
  default     = {}
}

variable "https_proxy" {
  type    = string
  default = ""
}

variable "no_proxy" {
  type    = string
  default = ""
}

variable "extra_environment" {
  description = "Extra plain environment for the server containers."
  type        = map(string)
  default     = {}
}

# --- Sizing -------------------------------------------------------------

variable "api_desired_count" {
  type    = number
  default = 2
}

variable "web_desired_count" {
  type    = number
  default = 2
}

variable "api_cpu" {
  type    = number
  default = 1024
}

variable "api_memory" {
  type    = number
  default = 2048
}

variable "worker_cpu" {
  type    = number
  default = 1024
}

variable "worker_memory" {
  type    = number
  default = 2048
}

variable "web_cpu" {
  type    = number
  default = 512
}

variable "web_memory" {
  type    = number
  default = 1024
}

variable "cpu_architecture" {
  description = "X86_64 or ARM64; the images are published for both."
  type        = string
  default     = "ARM64"
}

variable "worker_timezone" {
  type    = string
  default = "UTC"
}

variable "log_level" {
  type    = string
  default = "info"
}

variable "log_retention_days" {
  type    = number
  default = 90
}

# --- Database -----------------------------------------------------------

variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "db_engine_version" {
  type    = string
  default = "16"
}

variable "db_allocated_storage" {
  type    = number
  default = 50
}

variable "db_max_allocated_storage" {
  type    = number
  default = 500
}

variable "db_multi_az" {
  type    = bool
  default = true
}

variable "db_backup_retention_days" {
  type    = number
  default = 14
}

variable "db_deletion_protection" {
  type    = bool
  default = true
}

variable "db_kms_key_id" {
  description = "KMS key for storage encryption. Null uses the AWS-managed key."
  type        = string
  default     = null
}

variable "update_check_enabled" {
  description = "Daily read of LightCI's release index so admins see when a newer release exists. Nothing is sent. Set false on restricted networks."
  type        = bool
  default     = true
}
