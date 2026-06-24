module "network" {
  source = "./modules/network"
  count  = 0

  name_prefix  = local.name_prefix
  cluster_name = local.cluster_name
  vpc_cidr     = var.vpc_cidr
  az_count     = var.az_count
  subnet_cidrs = var.subnet_cidrs
  tags         = local.tags
}

module "security" {
  source = "./modules/security"
  count  = 0

  name_prefix = local.name_prefix
  vpc_id      = module.network[0].vpc_id
  vpc_cidr    = var.vpc_cidr
  tags        = local.tags
}

module "eks" {
  source = "./modules/eks"
  count  = 0

  name_prefix               = local.name_prefix
  cluster_name              = local.cluster_name
  cluster_version           = var.eks_version
  private_subnet_ids        = module.network[0].private_subnet_ids
  app_node_instance_types   = var.app_node_instance_types
  kafka_node_instance_types = var.kafka_node_instance_types
  tags                      = local.tags
}

module "ecr" {
  source = "./modules/ecr"
  count  = 0

  repositories = local.ecr_repositories
  tags         = local.tags
}

module "data" {
  source = "./modules/data"
  count  = 0

  name_prefix             = local.name_prefix
  aws_region              = var.aws_region
  archive_bucket          = coalesce(var.archive_bucket, "${local.name_prefix}-history-${var.aws_region}")
  db_identifier           = coalesce(var.db_identifier, "${local.name_prefix}-postgres")
  db_name                 = var.db_name
  db_username             = var.db_username
  db_instance_class       = var.db_instance_class
  db_allocated_storage_gb = var.db_allocated_storage_gb
  db_max_storage_gb       = var.db_max_storage_gb
  db_subnet_group_name    = coalesce(var.db_subnet_group_name, "${local.name_prefix}-db-subnets")
  db_subnet_ids           = module.network[0].db_subnet_ids
  rds_security_group_id   = module.security[0].rds_security_group_id
  rds_secret_name         = coalesce(var.rds_secret_name, "/${local.name_prefix}/rds")
  deletion_protection     = var.rds_deletion_protection
  skip_final_snapshot     = var.rds_skip_final_snapshot
  backup_retention_period = var.rds_backup_retention_period
  tags                    = local.tags
}

module "kubernetes_addons" {
  source = "./modules/kubernetes-addons"
  count  = 0

  cluster_name      = module.eks[0].cluster_name
  cluster_endpoint  = module.eks[0].cluster_endpoint
  oidc_provider_arn = module.eks[0].oidc_provider_arn
  oidc_provider_url = module.eks[0].oidc_provider_url
  aws_region        = var.aws_region
  vpc_id            = module.network[0].vpc_id
  namespace         = var.kubernetes_namespace
  kafka_storage_gb  = var.kafka_storage_gb
  tags              = local.tags

  depends_on = [module.eks]
}
