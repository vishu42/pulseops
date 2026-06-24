locals {
  name_prefix  = "${var.project}-${var.environment}"
  cluster_name = coalesce(var.cluster_name, "${local.name_prefix}-eks")

  tags = {
    Project     = var.project
    Environment = var.environment
  }

  ecr_repositories = coalesce(var.ecr_repositories, [
    "${local.name_prefix}/api-server",
    "${local.name_prefix}/scheduler",
    "${local.name_prefix}/status-checker",
    "${local.name_prefix}/status-writer",
  ])
}
