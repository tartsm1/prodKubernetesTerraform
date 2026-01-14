# Kubernetes resources moved from modules/eks to root
# This fixes the destroy ordering issue by ensuring these resources
# are managed at the root level where the provider is configured

# GP3 StorageClass - more cost-effective and performant than gp2
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }

  depends_on = [module.eks]
}

# Remove default annotation from gp2 if it exists
resource "kubernetes_annotations" "remove_gp2_default" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }
  force = true

  depends_on = [kubernetes_storage_class_v1.gp3]
}

resource "kubernetes_namespace_v1" "development" {
  metadata {
    name = "development"
    labels = {
      name = "development"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_labels" "development_namespace_pss" {
  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = "development"
  }
  labels = {
    "pod-security.kubernetes.io/enforce" = "restricted"
    "pod-security.kubernetes.io/audit"   = "restricted"
    "pod-security.kubernetes.io/warn"    = "restricted"
  }

  depends_on = [kubernetes_namespace_v1.development]
}

resource "kubernetes_network_policy_v1" "javaapp_policy" {
  metadata {
    name      = "javaapp-network-policy"
    namespace = "default"
  }

  depends_on = [module.eks]

  spec {
    pod_selector {
      match_labels = {
        app = "javaapp"
      }
    }

    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "reactapp"
          }
        }
      }
      ports {
        port     = "8888"
        protocol = "TCP"
      }
    }

    egress {
      # Allow DNS
      to {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
    }

    egress {
      # Allow AWS services (DynamoDB via VPC endpoint)
      to {
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }
    }
  }
}
