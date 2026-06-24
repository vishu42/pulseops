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

variable "app_node_instance_types" {
  type = list(string)
}

variable "kafka_node_instance_types" {
  type = list(string)
}

variable "tags" {
  type = map(string)
}

