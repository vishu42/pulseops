variable "name_prefix" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "archive_bucket" {
  type = string
}

variable "db_identifier" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_instance_class" {
  type = string
}

variable "db_allocated_storage_gb" {
  type = number
}

variable "db_max_storage_gb" {
  type = number
}

variable "db_subnet_group_name" {
  type = string
}

variable "db_subnet_ids" {
  type = list(string)
}

variable "rds_security_group_id" {
  type = string
}

variable "rds_secret_name" {
  type = string
}

variable "deletion_protection" {
  type = bool
}

variable "skip_final_snapshot" {
  type = bool
}

variable "backup_retention_period" {
  type = number
}

variable "tags" {
  type = map(string)
}

