terraform {
  backend "s3" {
    bucket         = "three-tier-tfstate-bucket-barmvw"
    key            = "eks/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "three-tier-terraform-lock-table"
  }

  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 6.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.0" }
    helm       = { source = "hashicorp/helm", version = "2.12.1" }
    http       = { source = "hashicorp/http", version = "~> 3.0" }
  }
}

provider "aws" {
  region = var.region
}

data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = "three-tier-tfstate-bucket-barmvw"
    key    = "vpc/terraform.tfstate"
    region = var.region
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.17.0"

  name               = "${var.name_prefix}-eks"
  kubernetes_version = "1.33"

  enable_cluster_creator_admin_permissions = true
  enable_irsa = true

  vpc_id     = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnets

  endpoint_public_access  = true
  endpoint_private_access = true

  eks_managed_node_groups = {
    app = {
      name           = "${var.name_prefix}-app"
      instance_types = var.instance_type
      min_size       = var.min_size
      max_size       = var.max_size
      desired_size   = var.desired_size

      labels = { role = "app" }
    }

    db = {
      name           = "${var.name_prefix}-db"
      instance_types = var.instance_type
      min_size       = var.min_size
      max_size       = var.max_size
      desired_size   = var.desired_size

      labels = { role = "db" }

      taints = {
        dedicated = {
          key    = "dedicated"
          value  = "db"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  tags = {
    Project = "${var.name_prefix}-eks"
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks", "get-token",
        "--region", var.region,
        "--cluster-name", module.eks.cluster_name
      ]
    }
  }
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.39.0"

  role_name = "ebs-csi-role"

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi_attach" {
  role       = module.ebs_csi_irsa.iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.39.0"

  role_name = "aws-load-balancer-controller"

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

data "http" "alb_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "alb" {
  name   = "alb-controller-policy"
  policy = data.http.alb_policy.response_body
}

resource "aws_iam_role_policy_attachment" "alb_attach" {
  role       = module.alb_controller_irsa.iam_role_name
  policy_arn = aws_iam_policy.alb.arn
}

module "external_secrets_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.39.0"

  role_name = "external-secrets-role"

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets-sa"] # FIXED
    }
  }
}

resource "aws_iam_policy" "external_secrets_policy" {
  name = "external-secrets-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "external_secrets_attach" {
  role       = module.external_secrets_irsa.iam_role_name
  policy_arn = aws_iam_policy.external_secrets_policy.arn
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name = module.eks.cluster_name
  addon_name   = "aws-ebs-csi-driver"

  service_account_role_arn = module.ebs_csi_irsa.iam_role_arn

  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.ebs_csi_attach
  ]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = module.eks.cluster_name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = module.eks.cluster_name
  addon_name   = "coredns"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = module.eks.cluster_name
  addon_name   = "kube-proxy"
}

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  depends_on = [
    module.eks,
    module.alb_controller_irsa,
    aws_iam_role_policy_attachment.alb_attach
  ]

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "region"
    value = var.region
  }

  set {
    name  = "vpcId"
    value = data.terraform_remote_state.vpc.outputs.vpc_id
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.alb_controller_irsa.iam_role_arn
  }
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  namespace  = "external-secrets"

  create_namespace = true

  depends_on = [
    module.eks,
    module.external_secrets_irsa,
    aws_iam_role_policy_attachment.external_secrets_attach
  ]

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "external-secrets-sa"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.external_secrets_irsa.iam_role_arn
  }
}