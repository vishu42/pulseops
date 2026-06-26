provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = local.tags
  }
}

data "aws_eks_cluster_auth" "this" {
  count = 0

  name = module.eks_cluster[0].cluster_name
}

provider "kubernetes" {
  host                   = try(module.eks_cluster[0].cluster_endpoint, null)
  cluster_ca_certificate = try(base64decode(module.eks_cluster[0].cluster_certificate_authority_data), null)
  token                  = try(data.aws_eks_cluster_auth.this[0].token, null)
}

provider "helm" {
  kubernetes {
    host                   = try(module.eks_cluster[0].cluster_endpoint, null)
    cluster_ca_certificate = try(base64decode(module.eks_cluster[0].cluster_certificate_authority_data), null)
    token                  = try(data.aws_eks_cluster_auth.this[0].token, null)
  }
}
