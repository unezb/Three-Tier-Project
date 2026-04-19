terraform {
  backend "s3" {
    bucket         = "three-tier-tfstate-bucket-barmvw"
    key            = "jenkins/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "three-tier-terraform-lock-table"
  }
}

data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = "three-tier-tfstate-bucket-barmvw"
    key    = "vpc/terraform.tfstate"
    region = var.region
  }
}

module "jenkins_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"

  name   = "${var.name_prefix}-jenkins-sg"
  vpc_id = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "SSH"
    },
    {
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "Jenkins UI"
    },
    {
      from_port = 9000
      to_port = 9000
      protocol = "tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "SonarQube UI"
    }
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = "0.0.0.0/0"
      description = "Allow all outbound traffic"
    }
  ]
}

resource "aws_iam_role" "jenkins_role" {
  name = "${var.name_prefix}-jenkins-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_ec2_full_access" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "${var.name_prefix}-jenkins-instance-profile"
  role = aws_iam_role.jenkins_role.name
}

resource "aws_iam_role_policy_attachment" "jenkins_ecr_access" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

resource "aws_instance" "jenkins" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  subnet_id = data.terraform_remote_state.vpc.outputs.public_subnets[0]

  vpc_security_group_ids = [module.jenkins_sg.security_group_id]

  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.jenkins_profile.name

  root_block_device {
    volume_size           = 24
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${var.name_prefix}-jenkins-server"
  }
}