variable "cluster_name" {
  type = string
}

variable "cluster_endpoint" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "namespace" {
  type = string
}

variable "kafka_storage_gb" {
  type = number
}

variable "tags" {
  type = map(string)
}

