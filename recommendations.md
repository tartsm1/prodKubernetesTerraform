# AWS EKS Infrastructure - Production Security & Performance Recommendations

## Executive Summary

This document provides comprehensive recommendations to improve the security posture and performance of your AWS EKS Terraform infrastructure for production environments. The analysis identified **critical security gaps** and **performance optimization opportunities** across IAM policies, networking, monitoring, high availability, and Kubernetes configurations.

## 🔴 Critical Security Issues
### Missing EKS Cluster Encryption

**Current State:** [modules/eks/main.tf:L23-L34]

> [!WARNING]
> **Risk:** EKS secrets are not encrypted at rest using KMS. This means sensitive data stored in Kubernetes secrets could be exposed if the underlying storage is compromised.

**Recommendation:**
Add KMS encryption for EKS secrets:

```terraform
resource "aws_kms_key" "eks" {
  description             = "EKS Secret Encryption Key"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true  # Consider restricting in production
  }
}
```

# Add to node group
resource "aws_eks_node_group" "main" {
  # ... existing config ...
```terraform
  remote_access {
    ec2_ssh_key               = var.ssh_key_name  # Only if needed
    source_security_group_ids = [aws_security_group.bastion.id]  # Restrict SSH
  }
}
```

## 🟡 Performance Optimization Recommendations

### Single NAT Gateway - High Availability Risk

**Current State:** [modules/vpc/main.tf]

> [!WARNING]
> **Risk:** Single NAT Gateway creates a single point of failure and limits throughput. If it fails, all private subnet resources lose internet connectivity.

**Recommendation:**
Deploy one NAT Gateway per availability zone for high availability:

```terraform
resource "aws_eip" "nat" {
  count  = length(var.availability_zones)
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-nat-eip-${var.availability_zones[count.index]}"
  }
}

resource "aws_nat_gateway" "main" {
  count         = length(var.availability_zones)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.cluster_name}-nat-${var.availability_zones[count.index]}"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt-${var.availability_zones[count.index]}"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
```

**Cost vs Benefit:** This increases costs (~$32/month per NAT Gateway) but provides critical redundancy for production.

---

### Insufficient Monitoring and Logging

**Current State:** No monitoring or logging infrastructure configured

> [!CAUTION]
> **Risk:** Cannot detect issues, debug problems, or meet compliance requirements without proper observability.

**Recommendation:**
Implement comprehensive monitoring and logging:

#### A. Enable EKS Control Plane Logging

```terraform
resource "aws_eks_cluster" "main" {
  # ... existing config ...
  
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]
}

# Create CloudWatch log group
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 30  # Adjust based on compliance requirements
  
  kms_key_id = aws_kms_key.eks.arn  # Encrypt logs
}
```

#### Deploy AWS CloudWatch Container Insights

```terraform
resource "helm_release" "aws_cloudwatch_metrics" {
  name       = "aws-cloudwatch-metrics"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-cloudwatch-metrics"
  namespace  = "amazon-cloudwatch"
  create_namespace = true

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  depends_on = [module.eks]
}

# IAM role for CloudWatch
resource "aws_iam_role" "cloudwatch_agent" {
  name = "${var.cluster_name}-cloudwatch-agent"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:amazon-cloudwatch:aws-cloudwatch-metrics"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.cloudwatch_agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
```

### Application Logging with Fluent Bit

```terraform
resource "helm_release" "aws_for_fluent_bit" {
  name       = "aws-for-fluent-bit"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-for-fluent-bit"
  namespace  = "kube-system"

  set {
    name  = "cloudWatch.region"
    value = var.region
  }

  set {
    name  = "cloudWatch.logGroupName"
    value = "/aws/eks/${var.cluster_name}/application"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.fluent_bit.arn
  }

  depends_on = [module.eks]
}
```

### Missing VPC Flow Logs

**Current State:** No VPC flow logs configured

> [!IMPORTANT]
> **Impact:** Cannot audit network traffic, detect anomalies, or troubleshoot connectivity issues.

**Recommendation:**
Enable VPC Flow Logs:

```terraform
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/${var.cluster_name}-flow-logs"
  retention_in_days = 7  # Adjust based on requirements
  kms_key_id        = aws_kms_key.eks.arn
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "${var.cluster_name}-vpc-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "${var.cluster_name}-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.vpc_flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-vpc-flow-logs"
  }
}
```

---

### Add More VPC Endpoints for AWS Services

**Current State:** Only DynamoDB VPC endpoint configured

> [!TIP]
> **Benefit:** Reduce NAT Gateway costs and improve performance by accessing AWS services privately.

**Recommendation:**
Add VPC endpoints for commonly used services:

```terraform
# S3 Gateway Endpoint (no cost)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.id}.s3"
  vpc_endpoint_type = "Gateway"

  tags = {
    Name = "${var.cluster_name}-s3-endpoint"
  }
}

resource "aws_vpc_endpoint_route_table_association" "s3_private" {
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
  route_table_id  = aws_route_table.private.id
}

# ECR API Interface Endpoint
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.cluster_name}-ecr-api-endpoint"
  }
}

# ECR Docker Interface Endpoint
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.cluster_name}-ecr-dkr-endpoint"
  }
}

# CloudWatch Logs Interface Endpoint
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.cluster_name}-logs-endpoint"
  }
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.cluster_name}-vpc-endpoints-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for VPC endpoints"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.cluster_name}-vpc-endpoints-sg"
  }
}
```

---

### Implement Pod Disruption Budgets

**Current State:** No Pod Disruption Budgets (PDBs) configured

> [!IMPORTANT]
> **Impact:** During node maintenance or upgrades, all pods could be terminated simultaneously, causing downtime.

**Recommendation:**
Add PDBs to ensure high availability during disruptions:

```terraform
resource "kubernetes_pod_disruption_budget_v1" "javaapp" {
  metadata {
    name = "javaapp-pdb"
  }

  spec {
    min_available = 1
    
    selector {
      match_labels = {
        app = "javaapp"
      }
    }
  }
}

resource "kubernetes_pod_disruption_budget_v1" "reactapp" {
  metadata {
    name = "reactapp-pdb"
  }

  spec {
    min_available = 1
    
    selector {
      match_labels = {
        app = "reactapp"
      }
    }
  }
}
```

---

### Enable EKS Add-ons with Managed Versions

**Current State:** Only pod-identity-agent addon configured with hardcoded version

> [!NOTE]
> **Benefit:** AWS manages updates and compatibility for critical cluster components.

**Recommendation:**
Add essential EKS managed add-ons:

```terraform
resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "vpc-cni"
  addon_version            = "v1.16.0-eksbuild.1"  # Check latest compatible version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  
  service_account_role_arn = aws_iam_role.vpc_cni.arn
}

resource "aws_eks_addon" "coredns" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "coredns"
  addon_version            = "v1.10.1-eksbuild.6"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "kube-proxy"
  addon_version            = "v1.28.2-eksbuild.2"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.26.0-eksbuild.1"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  
  service_account_role_arn = aws_iam_role.ebs_csi_driver.arn
}
```

---

### Optimize Instance Types and Use Spot Instances

**Current State:** Using `t4g.medium` instances only

> [!TIP]
> **Benefit:** Reduce costs by 60-90% using Spot instances for non-critical workloads.

**Recommendation:**
Create mixed instance type node groups with Spot instances:

```terraform
# On-Demand node group for critical workloads
resource "aws_eks_node_group" "on_demand" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-on-demand"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = 2
    max_size     = 5
    min_size     = 2
  }

  instance_types = ["t4g.medium", "t4g.small"]
  capacity_type  = "ON_DEMAND"

  labels = {
    workload-type = "critical"
  }

  tags = {
    Name = "${var.cluster_name}-on-demand-nodes"
  }
}

# Spot instance node group for cost savings
resource "aws_eks_node_group" "spot" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-spot"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = 1
    max_size     = 10
    min_size     = 0
  }

  instance_types = ["t4g.medium", "t4g.small", "t3.medium", "t3.small"]
  capacity_type  = "SPOT"

  labels = {
    workload-type = "flexible"
  }

  taint {
    key    = "spot"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  tags = {
    Name = "${var.cluster_name}-spot-nodes"
  }
}
```

Then update deployments to tolerate spot instances:

```terraform
spec {
  template {
    spec {
      toleration {
        key      = "spot"
        operator = "Equal"
        value    = "true"
        effect   = "NoSchedule"
      }
      
      node_selector = {
        workload-type = "flexible"
      }
    }
  }
}
```

---

## 🔵 Additional Best Practices

### Implement Backup Strategy

**Recommendation:**
Use Velero for cluster backup and disaster recovery:

```terraform
resource "helm_release" "velero" {
  name       = "velero"
  repository = "https://vmware-tanzu.github.io/helm-charts"
  chart      = "velero"
  namespace  = "velero"
  create_namespace = true

  set {
    name  = "configuration.provider"
    value = "aws"
  }

  set {
    name  = "configuration.backupStorageLocation.bucket"
    value = aws_s3_bucket.velero_backups.id
  }

  set {
    name  = "configuration.backupStorageLocation.config.region"
    value = var.region
  }

  set {
    name  = "serviceAccount.server.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.velero.arn
  }

  set {
    name  = "initContainers[0].name"
    value = "velero-plugin-for-aws"
  }

  set {
    name  = "initContainers[0].image"
    value = "velero/velero-plugin-for-aws:v1.8.0"
  }

  set {
    name  = "initContainers[0].volumeMounts[0].mountPath"
    value = "/target"
  }

  set {
    name  = "initContainers[0].volumeMounts[0].name"
    value = "plugins"
  }
}

resource "aws_s3_bucket" "velero_backups" {
  bucket = "${var.cluster_name}-velero-backups"
  
  tags = {
    Name = "${var.cluster_name}-velero-backups"
  }
}

resource "aws_s3_bucket_versioning" "velero_backups" {
  bucket = aws_s3_bucket.velero_backups.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero_backups" {
  bucket = aws_s3_bucket.velero_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
```

---

### Add ALB Access Logs

**Recommendation:**
Enable ALB access logs for security auditing and troubleshooting:

```terraform
resource "kubernetes_ingress_v1" "main_ingress" {
  metadata {
    name = "main-ingress"
    annotations = {
      # ... existing annotations ...
      
      "alb.ingress.kubernetes.io/load-balancer-attributes" = "access_logs.s3.enabled=true,access_logs.s3.bucket=${aws_s3_bucket.alb_logs.id},access_logs.s3.prefix=main-alb"
    }
  }
  # ... rest of config ...
}

resource "aws_s3_bucket" "alb_logs" {
  bucket = "${var.cluster_name}-alb-logs"
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::897822967062:root"  # ELB service account for eu-north-1
      }
      Action   = "s3:PutObject"
      Resource = "${aws_s3_bucket.alb_logs.arn}/*"
    }]
  })
}
```

---

### Implement AWS WAF for ALB Protection

**Recommendation:**
Add AWS WAF to protect against common web exploits:

```terraform
resource "aws_wafv2_web_acl" "main" {
  name  = "${var.cluster_name}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.cluster_name}-waf-metric"
    sampled_requests_enabled   = true
  }
}

# Add to ingress annotations
resource "kubernetes_ingress_v1" "main_ingress" {
  metadata {
    annotations = {
      # ... existing annotations ...
      "alb.ingress.kubernetes.io/wafv2-acl-arn" = aws_wafv2_web_acl.main.arn
    }
  }
}
```

---

### Enable GuardDuty for Threat Detection

**Recommendation:**
Enable Amazon GuardDuty for EKS:

```terraform
resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    kubernetes {
      audit_logs {
        enable = true
      }
    }
  }

  tags = {
    Name = "${var.cluster_name}-guardduty"
  }
}
```

---

## 🎯 Quick Wins (Implement First)


## 📝 Summary

Your current infrastructure has a solid foundation but requires critical security hardening and performance optimization for production use. The most urgent issues are:

- **Missing encryption** for secrets at rest
- **No resource management** leading to potential instability
- **Single points of failure** (NAT Gateway, no PDBs)
- **Lack of observability** (no logging, monitoring, or metrics)

---

## 📚 Additional Resources

- [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [AWS Load Balancer Controller Documentation](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/security-checklist/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
