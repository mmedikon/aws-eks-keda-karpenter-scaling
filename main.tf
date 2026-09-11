provider "aws"{
    region=var.region
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

data "aws_availability_zones" "available" {}

locals {
  #cluster_name = "myEKSMo-${random_string.suffix.result}"
  cluster_name = "demoECOMIN"
}

#resource "random_string" "suffix" {
 # length  = 8
 # special = false
#}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~>6.0"

  name = "demoECOMIN-vpc"

  cidr = "10.0.0.0/16"
  azs  = data.aws_availability_zones.available.names

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.4.0/24", "10.0.5.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~>21.0"

  name    = local.cluster_name
  
  kubernetes_version = "1.33"

  endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true
  
  addons={
     coredns={}
     eks-pod-identity-agent={
        before_compute=true
     }
     kube-proxy={}
     vpc-cni={
        before_compute=true
     }
     aws-ebs-csi-driver = {
      before_compute=true
      service_account_role_arn = aws_iam_role.ebs_csi.arn
    }
  }
  
  vpc_id=module.vpc.vpc_id
  subnet_ids=module.vpc.private_subnets
  
 

  eks_managed_node_groups = {
    
    demoECOMNG = {
      name = "demoECOMIN-nodepool"
      ami_type="AL2023_x86_64_STANDARD"
      instance_types = ["t3.small"]
    
      min_size     = 1
      max_size     = 3
      desired_size = 2
    }

   
  }
}
data "aws_iam_policy_document" "ebs_csi_irsa" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"

      values = [
        "system:serviceaccount:kube-system:ebs-csi-controller-sa"
      ]
    }

    effect = "Allow"
  }
}
resource "aws_iam_role" "ebs_csi" {
  name               = "ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_irsa.json
}

resource "aws_iam_role_policy_attachment" "AmazonEBSCSIDriverPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi.name
}

# IAM Assume Role Policy for Pod Identity
data "aws_iam_policy_document" "keda_demoeks_role" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# The IAM Role KEDA will assume
resource "aws_iam_role" "keda_operator" {
  name               = "keda-operator-pod-identity-role"
  assume_role_policy = data.aws_iam_policy_document.keda_demoeks_role.json
}

# Attach permissions needed by your KEDA scalers (e.g., SQS read access)
resource "aws_iam_role_policy_attachment" "keda_sqs" {
  role       = aws_iam_role.keda_operator.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSReadOnlyAccess" # Example policy
}

resource "aws_eks_pod_identity_association" "keda" {
  cluster_name    = module.eks.cluster_name
  namespace       = "keda"
  service_account = "keda-operator"
  role_arn        = aws_iam_role.keda_operator.arn
}
module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"
  version="~>21.25.0"

  cluster_name = module.eks.cluster_name
  enable_inline_policy = true
  # Name needs to match role name passed to the EC2NodeClass
  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = "demoECOMNG-ng112"
  create_pod_identity_association = true

  # Used to attach additional IAM policies to the Karpenter node IAM role
  create_access_entry = true
   tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}
resource "helm_release" "karpenter" {
  namespace           = "kube-system"
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter" 
  chart               = "karpenter"
  version             = "1.12.1"
  wait                = false

  values = [
    <<-EOT
    nodeSelector:
      kubernetes.io/os: linux
    dnsPolicy: Default
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name} 
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
           nodeSelectorTerms:
              - matchExpressions:
                   - key: karpenter.sh/nodepool
                     operator: DoesNotExist    
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - topologyKey: "kubernetes.io/hostname"   

    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule

    tolerations:
      - key: CriticalAddonsOnly
        operator: Exists        
  
    EOT
  ]
}

resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  namespace        = "keda"
  version          = "2.20.2"
  create_namespace = true

  # Ensure the Pod Identity Agent is active before KEDA starts running
  #EKS Pod identity as addon

  set=[{
    name  = "serviceAccount.name"
    value = "keda-operator"
  },{
    name  = "podIdentity.provider"
    value = "aws-eks"
  }]

}
resource "aws_sqs_queue" "demo_app" {
         name = "demo-app-sqs"
}