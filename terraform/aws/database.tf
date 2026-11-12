# RDS for PostgreSQL: encrypted, Multi-AZ, TLS required. The API verifies the RDS CA with the bundle
# it ships (DB_SSL_MODE=verify-full), and rds.force_ssl refuses anything that connects in the clear.

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "PostgreSQL from the server tasks"
  vpc_id      = var.vpc_id
  tags        = var.tags

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.server.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.private_subnet_ids
  tags       = var.tags
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.name}-pg"
  family = "postgres${split(".", var.db_engine_version)[0]}"
  tags   = var.tags

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "random_password" "db" {
  length      = 32
  special     = false
  min_lower   = 2
  min_upper   = 2
  min_numeric = 2
}

resource "aws_db_instance" "this" {
  identifier                      = "${var.name}-db"
  engine                          = "postgres"
  engine_version                  = var.db_engine_version
  instance_class                  = var.db_instance_class
  parameter_group_name            = aws_db_parameter_group.this.name
  allocated_storage               = var.db_allocated_storage
  max_allocated_storage           = var.db_max_allocated_storage
  storage_type                    = "gp3"
  storage_encrypted               = true
  kms_key_id                      = var.db_kms_key_id
  multi_az                        = var.db_multi_az
  username                        = "activate"
  password                        = random_password.db.result
  db_name                         = "activate"
  port                            = 5432
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.db.id]
  publicly_accessible             = false
  backup_retention_period         = var.db_backup_retention_days
  copy_tags_to_snapshot           = true
  deletion_protection             = var.db_deletion_protection
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${var.name}-db-final"
  auto_minor_version_upgrade      = true
  performance_insights_enabled    = true
  enabled_cloudwatch_logs_exports = ["postgresql"]
  apply_immediately               = false
  tags                            = var.tags

  lifecycle {
    ignore_changes = [password]
  }
}

# The API reads the whole secret as the DB env var ({host, port, username, password, dbname}).
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.name}/db"
  recovery_window_in_days = 7
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = aws_db_instance.this.username
    password = random_password.db.result
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    dbname   = aws_db_instance.this.db_name
  })
}
