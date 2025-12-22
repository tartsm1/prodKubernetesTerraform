# AWS EKS Terraform Configuration
# Copy this file to terraform.tfvars and customize values for your environment

#------------------------------------------------------------------------------
# AWS Region Configuration
#------------------------------------------------------------------------------
region             = "eu-north-1"
availability_zones = ["eu-north-1a", "eu-north-1b"]

#------------------------------------------------------------------------------
# EKS Cluster Configuration
#------------------------------------------------------------------------------
cluster_name        = "my-eks-cluster"
public_access_cidrs = ["12.34.56.78/32"]

#------------------------------------------------------------------------------
# VPC Network Configuration
#------------------------------------------------------------------------------
vpc_cidr        = "10.0.0.0/16"
public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

#------------------------------------------------------------------------------
# EKS Node Group Configuration
#------------------------------------------------------------------------------
desired_size   = 2
min_size       = 1
max_size       = 3
instance_types = ["t4g.medium"]

#------------------------------------------------------------------------------
# Container Images (ECR)
#------------------------------------------------------------------------------
javaapp_image  = "123456789098.dkr.ecr.eu-north-1.amazonaws.com/javaapp:123"
reactapp_image = "123456789098.dkr.ecr.eu-north-1.amazonaws.com/reactapp:123"

#------------------------------------------------------------------------------
# Cognito Configuration
#------------------------------------------------------------------------------
cognito_user_pool_id = "eu-north-1_xxxxxxxx"
cognito_client_id    = "xxxxxxxxxxxx"

#------------------------------------------------------------------------------
# Javaapp Configuration, number of threads to create on startup
#------------------------------------------------------------------------------
threads_count = "10"
