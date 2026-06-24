variable "name_prefix" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "az_count" {
  type = number
}

variable "subnet_cidrs" {
  type = object({
    public  = list(string)
    private = list(string)
    db      = list(string)
  })
}

variable "tags" {
  type = map(string)
}

