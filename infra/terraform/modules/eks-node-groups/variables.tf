variable "name_prefix" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "cluster_security_group_id" {
  type = string
}

variable "app_node_instance_types" {
  type = list(string)
}

variable "kafka_node_instance_types" {
  type = list(string)
}

variable "tags" {
  type = map(string)
}
