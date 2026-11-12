output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "internal_alb_dns_name" {
  description = "Point web_host and api_host here when you manage DNS yourself."
  value       = aws_lb.internal.dns_name
}

output "mcp_alb_dns_name" {
  description = "Point mcp_host here when you manage DNS yourself (A and AAAA)."
  value       = aws_lb.mcp.dns_name
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.db.arn
}

output "db_endpoint" {
  value = aws_db_instance.this.address
}

output "migrate_command" {
  description = "Run this before each upgrade (after `terraform apply` with the new image_tag, before the services roll)."
  value       = "aws ecs run-task --region ${var.region} --cluster ${aws_ecs_cluster.this.name} --launch-type FARGATE --task-definition ${aws_ecs_task_definition.migrate.family} --network-configuration 'awsvpcConfiguration={subnets=[${join(",", var.private_subnet_ids)}],securityGroups=[${aws_security_group.server.id}],assignPublicIp=DISABLED}'"
}

output "doctor_command" {
  description = "activate doctor inside a running api task (ECS Exec)."
  value       = "aws ecs execute-command --region ${var.region} --cluster ${aws_ecs_cluster.this.name} --task $(aws ecs list-tasks --region ${var.region} --cluster ${aws_ecs_cluster.this.name} --service-name ${aws_ecs_service.api.name} --query 'taskArns[0]' --output text) --container api --interactive --command 'activate doctor'"
}

output "metrics_targets" {
  description = "Prometheus scrapes port 9464 on every api and worker task (ECS service discovery or a sidecar)."
  value       = { port = 9464, path = "/metrics", security_group = aws_security_group.server.id }
}
