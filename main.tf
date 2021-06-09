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
  subdomain_names  = ["argocd", "youtrack"] # , "youtrack-test"]
}

#######################################################################

locals {
  file_systems = [
    "youtrack_data",
    "youtrack_conf",
    "youtrack_logs",
    "youtrack_backups",
  ]
}

resource "aws_efs_file_system" "efs_youtrack" {
  for_each       = toset(local.file_systems)
  creation_token = each.key

  # encrypted   = true
  # kms_key_id  = ""

  performance_mode = "generalPurpose" #maxIO
  throughput_mode  = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
}

data "aws_efs_file_system" "efs_youtrack_data" {
  for_each       = aws_efs_file_system.efs_youtrack
  file_system_id = each.value.id
}

resource "aws_efs_access_point" "efs_youtrack_data" {
  for_each       = aws_efs_file_system.efs_youtrack
  file_system_id = each.value.id
}

# Mount to the subnets that will be using this efs volume
# Also attach sg's to restrict access to this volume
resource "aws_efs_mount_target" "subnet_mount_1" {
  for_each       = aws_efs_file_system.efs_youtrack
  file_system_id = each.value.id
  subnet_id      = module.vpc.private_subnets[0]

  security_groups = [
    aws_security_group.allow_eks_cluster.id
  ]
}

resource "aws_efs_mount_target" "subnet_mount_2" {
  for_each       = aws_efs_file_system.efs_youtrack
  file_system_id = each.value.id
  subnet_id      = module.vpc.private_subnets[1]

  security_groups = [
    aws_security_group.allow_eks_cluster.id
  ]
}

# Security Groups for this volume
resource "aws_security_group" "allow_eks_cluster" {
  name        = "eks nfs group"
  description = "This will allow the cluster to access this volume and use it."
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "NFS For EKS Cluster"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    security_groups = [
      module.eks.cluster_primary_security_group_id
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_tls"
  }
}
