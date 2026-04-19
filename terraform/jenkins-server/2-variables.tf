variable "region" {
  description = "The AWS region for Jenkins server"
  type = string
}

variable "key_name" {
  description = "The private key for instance launch"
  type = string
}

variable "instance_type" {
  description = "The instance type used for Jenkins server"
  type = string
}

variable "name_prefix" {
  description = "Prefix used for resources"
  type = string
}

variable "ami_id" {
  description = "The AMI ID used to launch the instance"
  type = string
}