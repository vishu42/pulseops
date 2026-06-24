resource "aws_s3_bucket" "archive" {
  bucket = var.archive_bucket
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "archive" {
  bucket = aws_s3_bucket.archive.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id

  rule {
    id     = "archive-history-cost-optimization"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER_IR"
    }
  }
}

resource "random_password" "db" {
  length           = 32
  special          = false
  override_special = ""
}

resource "aws_secretsmanager_secret" "rds" {
  name        = var.rds_secret_name
  description = "PulseOps RDS credentials"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    dbname   = var.db_name
  })
}

resource "aws_db_subnet_group" "this" {
  name        = var.db_subnet_group_name
  description = "PulseOps RDS subnet group"
  subnet_ids  = var.db_subnet_ids
  tags        = var.tags
}

resource "aws_db_instance" "postgres" {
  identifier                = var.db_identifier
  engine                    = "postgres"
  engine_version            = "16.4"
  instance_class            = var.db_instance_class
  allocated_storage         = var.db_allocated_storage_gb
  max_allocated_storage     = var.db_max_storage_gb
  storage_type              = "gp3"
  db_name                   = var.db_name
  username                  = var.db_username
  password                  = random_password.db.result
  db_subnet_group_name      = aws_db_subnet_group.this.name
  vpc_security_group_ids    = [var.rds_security_group_id]
  backup_retention_period   = var.backup_retention_period
  multi_az                  = true
  publicly_accessible       = false
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.db_identifier}-final"
  tags                      = var.tags
}
