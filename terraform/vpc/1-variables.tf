variable "vpc_cidr" {
  description = "The CIDR range for the VPC"
  type = string
}

variable "name_prefix" {
  description = "Prefix used for resources"
  type = string
}

variable "vpc_azs" {
  description = "The availability zones used for our project"
  type = list(string)
}

variable "public_subnets" {
  description = "The CIDR range for the public subnet"
  type = list(string)
}

variable "private_subnets" {
  description = "The CIDR range for the public subnet"
  type = list(string)
}

variable "region" {
  description = "AWS region for VPC"
  type = string
}