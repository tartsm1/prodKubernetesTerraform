variable "region" {
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnets" {
  description = "List of public subnet CIDRs"
  type        = list(string)
}

variable "private_subnets" {
  description = "List of private subnet CIDRs"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "desired_size" {
  description = "Desired number of worker nodes"
  type        = number
}

variable "max_size" {
  description = "Maximum number of worker nodes"
  type        = number
}

variable "min_size" {
  description = "Minimum number of worker nodes"
  type        = number
}

variable "instance_types" {
  description = "List of instance types for the worker nodes"
  type        = list(string)
}

variable "javaapp_image" {
  description = "ECR image for the javaapp application"
  type        = string
}

variable "reactapp_image" {
  description = "ECR image for the reactapp application"
  type        = string
}

variable "public_access_cidrs" {
  description = "List of CIDR blocks that can access the EKS cluster public endpoint"
  type        = list(string)
}

variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID for authentication"
  type        = string
}

variable "cognito_client_id" {
  description = "Cognito Client ID for authentication"
  type        = string
}

variable "threads_count" {
  description = "Number of threads for the javaapp application"
  type        = string
}