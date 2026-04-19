variable "region" {
  description = "AWS region for EKS"
  type = string
}

variable "name_prefix" {
  description = "Prefix for the resources"
  type = string
}

variable "instance_type" {
  description = "The type of instance for the node group"
  type = list(string)
}

variable "min_size" {
  description = "The minimum capacity of instances for the node group"
  type = number
}

variable "max_size" {
  description = "The maximum capacity of instances for the node group"
  type = number
}

variable "desired_size" {
  description = "The desired capacity of instances for the node group"
  type = number
}