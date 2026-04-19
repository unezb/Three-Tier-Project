terraform {
  backend "s3" {
    bucket = "three-tier-tfstate-bucket-barmvw"
    key = "vpc/terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "three-tier-terraform-lock-table"
  }
}

provider "aws" {
  region = var.region
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = "${var.name_prefix}-vpc"
  
  cidr = var.vpc_cidr
  
  azs = var.vpc_azs
  public_subnets = var.public_subnets
  private_subnets = var.private_subnets

  enable_nat_gateway = true
  single_nat_gateway = true

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"              = 1
    "kubernetes.io/role/elb"                       = 1
    "kubernetes.io/cluster/${var.name_prefix}-eks" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/role/internal-elb"              = 1
    "kubernetes.io/role/elb"                       = 1
    "kubernetes.io/cluster/${var.name_prefix}-eks" = "shared"
  }

  tags = {
    Project = "${var.name_prefix}-vpc"
  }
}