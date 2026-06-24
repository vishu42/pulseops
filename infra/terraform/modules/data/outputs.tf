output "archive_bucket" {
  value = aws_s3_bucket.archive.bucket
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.address
}

output "rds_secret_arn" {
  value     = aws_secretsmanager_secret.rds.arn
  sensitive = true
}

