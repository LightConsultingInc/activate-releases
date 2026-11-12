# The worker's /data: marketplace clones and work trees. Remotes are the source of truth, so this is a
# cache that survives task replacement rather than a store that needs backups.

resource "aws_security_group" "efs" {
  name        = "${var.name}-efs"
  description = "NFS from the server tasks"
  vpc_id      = var.vpc_id
  tags        = var.tags

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.server.id]
  }
}

resource "aws_efs_file_system" "data" {
  creation_token   = "${var.name}-data"
  encrypted        = true
  throughput_mode  = "elastic"
  performance_mode = "generalPurpose"
  tags             = merge(var.tags, { Name = "${var.name}-data" })

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
}

resource "aws_efs_mount_target" "data" {
  # Keyed by position: subnet ids created in the same apply are unknown at plan time.
  for_each        = { for i, id in var.private_subnet_ids : tostring(i) => id }
  file_system_id  = aws_efs_file_system.data.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

# Owned by uid 1001, the only user in the image.
resource "aws_efs_access_point" "data" {
  file_system_id = aws_efs_file_system.data.id
  tags           = var.tags

  posix_user {
    uid = 1001
    gid = 1001
  }
  root_directory {
    path = "/activate"
    creation_info {
      owner_uid   = 1001
      owner_gid   = 1001
      permissions = "0750"
    }
  }
}

resource "aws_iam_role_policy" "task_efs" {
  name = "efs"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
      Resource = aws_efs_file_system.data.arn
      Condition = {
        StringEquals = { "elasticfilesystem:AccessPointArn" = aws_efs_access_point.data.arn }
      }
    }]
  })
}
