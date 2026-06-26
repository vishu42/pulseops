variable "aws_profile" {
  description = "AWS CLI profile used by the AWS provider."
  type        = string
  default     = "default"
}

variable "aws_region" {
  description = "AWS region where PulseOps infrastructure is created."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project tag and resource-name component."
  type        = string
  default     = "pulseops"
}

variable "environment" {
  description = "Environment tag and resource-name component."
  type        = string
  default     = "prod"
}

variable "cluster_name" {
  description = "Optional explicit EKS cluster name."
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "CIDR block for the PulseOps VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to use."
  type        = number
  default     = 3
}

variable "subnet_cidrs" {
  description = "CIDR blocks for public, private, and DB subnets."
  type = object({
    public  = list(string)
    private = list(string)
    db      = list(string)
  })
  default = {
    public  = ["10.42.0.0/20", "10.42.16.0/20", "10.42.32.0/20"]
    private = ["10.42.48.0/20", "10.42.64.0/20", "10.42.80.0/20"]
    db      = ["10.42.96.0/24", "10.42.97.0/24", "10.42.98.0/24"]
  }
}

variable "eks_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.35"
}

variable "eks_admin_principal_arns" {
  description = "IAM principal ARNs to grant EKS cluster admin access."
  type        = list(string)
  default     = []
}

variable "eks_user_principal_arns" {
  description = "IAM principal ARNs to grant EKS cluster user/view access."
  type        = list(string)
  default     = []
}

variable "app_node_instance_types" {
  description = "EC2 instance types for the application node group."
  type        = list(string)
  default     = ["t3.large"]
}

variable "kafka_node_instance_types" {
  description = "EC2 instance types for the Kafka node group."
  type        = list(string)
  default     = ["m7i.large"]
}

variable "ecr_repositories" {
  description = "Optional explicit ECR repositories for PulseOps service images."
  type        = list(string)
  default     = null
}

variable "archive_bucket" {
  description = "Optional explicit S3 archive bucket name."
  type        = string
  default     = null
}

variable "db_identifier" {
  description = "Optional explicit RDS instance identifier."
  type        = string
  default     = null
}

variable "db_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "pulseops"
}

variable "db_username" {
  description = "RDS master username."
  type        = string
  default     = "pulseops"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.medium"
}

variable "db_allocated_storage_gb" {
  description = "Initial RDS storage in GB."
  type        = number
  default     = 50
}

variable "db_max_storage_gb" {
  description = "RDS autoscaling storage ceiling in GB."
  type        = number
  default     = 200
}

variable "db_subnet_group_name" {
  description = "Optional explicit DB subnet group name."
  type        = string
  default     = null
}

variable "rds_secret_name" {
  description = "Optional explicit Secrets Manager secret name for RDS credentials."
  type        = string
  default     = null
}

variable "rds_deletion_protection" {
  description = "Protect the RDS instance from accidental deletion."
  type        = bool
  default     = true
}

variable "rds_skip_final_snapshot" {
  description = "Skip the final RDS snapshot during destroy. Keep false for production."
  type        = bool
  default     = false
}

variable "rds_backup_retention_period" {
  description = "RDS backup retention period in days."
  type        = number
  default     = 7
}

variable "kubernetes_namespace" {
  description = "Namespace for PulseOps app and Kafka resources."
  type        = string
  default     = "pulseops"
}

variable "kafka_storage_gb" {
  description = "Kafka broker/controller PVC size in Gi."
  type        = number
  default     = 100
}
