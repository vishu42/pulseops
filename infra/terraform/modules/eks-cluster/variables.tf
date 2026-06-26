variable "name_prefix" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "cluster_version" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "admin_principal_arns" {
  type    = list(string)
  default = []
}

variable "user_principal_arns" {
  type    = list(string)
  default = []
}

variable "tags" {
  type = map(string)
}
