# Activate on AWS (Terraform)

One module, one `terraform apply`: ECS Fargate services for the web app, the API and the worker, RDS
for PostgreSQL (Multi-AZ, encrypted, TLS required), EFS for the worker's marketplace clones, an
internal load balancer for your people and a public one for Claude's MCP traffic that WAF restricts
to Anthropic's published ranges. It mirrors the Helm chart in `deploy/helm/activate`: the same
images, the same environment, the same `activate migrate` step before an upgrade.

You bring: a VPC with private and public subnets, ACM certificates for your three hostnames, and
secrets in AWS Secrets Manager. Nothing sensitive is written into Terraform state except the
database password the module generates and stores in Secrets Manager.

## Secrets you create first

| Secret (any name)        | Value                                               | Variable                         |
| ------------------------ | --------------------------------------------------- | -------------------------------- |
| licence                  | the licence JWT LightCI sent you (plain string)     | `license_secret_arn`             |
| encryption key           | `openssl rand -base64 32` (plain string)            | `encryption_key_secret_arn`      |
| Anthropic API key        | plain string                                        | `anthropic_api_key_secret_arn`   |
| OIDC client secret       | plain string                                        | `oidc.client_secret_arn`         |
| Git token                | contents + pull-request write on the marketplace    | `marketplace.git_token_secret`   |
| WorkOS (workos mode)     | JSON `{"api-key": "...", "client-id": "..."}`       | `workos_secret_arn`              |
| registry (private mirror only) | JSON `{"username": "...", "password": "..."}`       | `registry_credentials_secret_arn`|

Back up the encryption key together with the database: the key decrypts the credentials your
admins enter under Settings › Integrations.

## Minimum configuration

```hcl
module "activate" {
  source = "github.com/LightConsultingInc/activate-releases//terraform/aws?ref=v1.0.5"

  name   = "activate"
  region = "eu-central-1"

  vpc_id                     = "vpc-0123"
  private_subnet_ids         = ["subnet-a", "subnet-b"]
  public_subnet_ids          = ["subnet-c", "subnet-d"]
  internal_alb_ingress_cidrs = ["10.0.0.0/8"]
  # For a public service instead: people_alb_internet_facing = true and ["0.0.0.0/0"] above.

  image_tag = "1.0.5" # same version as the ref above

  web_host                 = "activate.example.com"
  api_host                 = "api.activate.example.com"
  mcp_host                 = "mcp.activate.example.com"
  internal_certificate_arn = aws_acm_certificate.internal.arn
  mcp_certificate_arn      = aws_acm_certificate.mcp.arn
  hosted_zone_id           = aws_route53_zone.example.zone_id

  license_secret_arn = aws_secretsmanager_secret.license.arn
  org = {
    name           = "Example Corp"
    slug           = "example"
    email_domains  = ["example.com"]
    initial_admins = ["jane.doe@example.com"]
  }

  oidc = {
    issuer            = "https://login.microsoftonline.com/<tenant-id>/v2.0"
    client_id         = "00000000-0000-0000-0000-000000000000"
    client_secret_arn = aws_secretsmanager_secret.oidc.arn
  }

  anthropic_api_key_secret_arn = aws_secretsmanager_secret.anthropic.arn
  encryption_key_secret_arn    = aws_secretsmanager_secret.encryption.arn
  marketplace = {
    provider         = "github"
    repository       = "example-corp/claude-marketplace"
    git_token_secret = aws_secretsmanager_secret.git.arn
  }
}
```

## First boot

1. `terraform apply`.
2. Run the migrate task once: `terraform output -raw migrate_command | bash`, then wait for it to exit 0
   (`aws ecs describe-tasks`). The API and worker services only become healthy once the schema exists.
3. The worker runs first-boot bootstrap on its own: your organisation, email domains and initial
   admins from `org`. Sign in at `https://<web_host>` with one of the initial admins.
4. `terraform output -raw doctor_command | bash` runs `activate doctor` inside an API task.

## Upgrades

Read the release notes for the new version, then:

1. `terraform apply -var image_tag=1.1.0` (services keep running the old version until the next step).
2. Run the migrate task (`migrate_command`) and wait for it to succeed. Migrations are additive
   within a major version, so the old tasks keep working against the new schema.
3. `aws ecs update-service --force-new-deployment` for `-api`, `-worker` and `-web`, or let the apply
   roll them (the task definitions changed). Rolling deployments with circuit breakers roll back on
   failed health checks.

Rollback within a major: apply the previous `image_tag` and force a new deployment; no database restore
is needed.

## Anthropic's IP ranges

`mcp_allowed_cidrs` and `mcp_allowed_ipv6_cidrs` default to the ranges published at
<https://platform.claude.com/docs/en/api/ip-addresses>. Check them when you install and at each upgrade;
the WAF blocks everything else from reaching the MCP hostname.

## Monitoring

Every API and worker task serves Prometheus metrics on port 9464 (`/metrics`), never through a load
balancer. Scrape it with ECS service discovery or the CloudWatch agent with Prometheus support. Logs
are JSON in CloudWatch under `/activate/<name>`.
