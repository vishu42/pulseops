output "aws_region" {
  value = var.aws_region
}

output "cluster_name" {
  value = try(module.eks[0].cluster_name, null)
}

output "cluster_endpoint" {
  value = try(module.eks[0].cluster_endpoint, null)
}

output "vpc_id" {
  value = try(module.network[0].vpc_id, null)
}

output "public_subnet_ids" {
  value = try(module.network[0].public_subnet_ids, [])
}

output "private_subnet_ids" {
  value = try(module.network[0].private_subnet_ids, [])
}

output "db_subnet_ids" {
  value = try(module.network[0].db_subnet_ids, [])
}

output "archive_bucket" {
  value = try(module.data[0].archive_bucket, null)
}

output "rds_endpoint" {
  value = try(module.data[0].rds_endpoint, null)
}

output "rds_secret_arn" {
  value     = try(module.data[0].rds_secret_arn, null)
  sensitive = true
}

output "ecr_repository_urls" {
  value = try(module.ecr[0].repository_urls, {})
}

output "kafka_bootstrap_service" {
  value = try(module.kubernetes_addons[0].kafka_bootstrap_service, null)
}
