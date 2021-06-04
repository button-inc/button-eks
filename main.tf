locals {
  cluster_name = "button-eks"
  # see https://docs.amazonaws.cn/en_us/AmazonECS/latest/developerguide/AWS_Fargate.html
  # aws ec2 describe-availability-zones
  vpc_available_zones = ["ca-central-1a", "ca-central-1b"]
  vpc_cidr            = "10.0.0.0/16"
  vpc_private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  vpc_public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.0.0"

  name = "eks-${local.cluster_name}-vpc"
  azs  = local.vpc_available_zones

  cidr                 = local.vpc_cidr
  private_subnets      = local.vpc_private_subnets
  public_subnets       = local.vpc_public_subnets
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

# see https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
# see https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html
# see https://aws.amazon.com/ec2/instance-types/t3/
# see https://aws.amazon.com/ec2/instance-types/m5/
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = local.cluster_name
  cluster_version = "1.20"
  subnets         = module.vpc.private_subnets

  cluster_enabled_log_types     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cluster_log_retention_in_days = 30

  manage_aws_auth                   = false
  manage_cluster_iam_resources      = true
  manage_worker_iam_resources       = true
  create_fargate_pod_execution_role = true
  enable_irsa                       = true

  tags = {
    "managed-by" = "terraform"
  }

  vpc_id = module.vpc.vpc_id

  fargate_profiles = {
    argocd = {
      tags = {
        "managed-by" = "terraform"
      },

      selectors = [
        {
          namespace = "argocd"
        }
      ]
    },
    youtrack = {
      tags = {
        "managed-by" = "terraform"
      },
      selectors = [
        {
          namespace = "youtrack"
        }
      ]
    }
  }

  node_groups_defaults = {
    ami_type  = "AL2_x86_64"
    disk_size = 50
  }

  node_groups = {
    node_group = {
      desired_capacity = 2
      max_capacity     = 5
      min_capacity     = 1

      instance_types = ["m5.large"]
      capacity_type  = "SPOT"
      k8s_labels = {
        Environment = "test"
        GithubRepo  = "terraform-aws-eks"
        GithubOrg   = "terraform-aws-modules"
      }
      additional_tags = {
        "managed-by" = "terraform"
      }
    }
  }
}

module "eks_tools" {
  source  = "button-inc/tools/eks"
  version = "0.4.0"

  cluster_name                  = module.eks.cluster_id
  create_alb_ingress_controller = true
  create_external_dns           = true
  create_metrics_server         = true
  cluster_namespaces            = ["argocd", "youtrack"]
}

module "acm" {
  source           = "button-inc/acm/aws"
  hosted_zone_name = "buttoncloud.ca."
  subdomain_names  = ["argocd", "youtrack"]
}

resource "aws_efs_file_system" "youtrack-efs" {
  creation_token = "youtrack-efs"
}
