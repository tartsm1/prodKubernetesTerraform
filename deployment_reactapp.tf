resource "kubernetes_config_map_v1" "reactapp_config" {
  metadata {
    name      = "reactapp-config"
    namespace = "development"
  }

  data = {
    "app-config.js" = <<-EOT
      window.APP_CONFIG = {
        "aws_region": "${var.region}",
        "cognito_user_pool_id": "${var.cognito_user_pool_id}",
        "cognito_client_id": "${var.cognito_client_id}"
      };
    EOT
  }
}

resource "kubernetes_deployment_v1" "reactapp" {
  metadata {
    name      = "reactapp"
    namespace = "development"
    labels = {
      app = "reactapp"
    }
  }

  spec {
    replicas               = 2
    revision_history_limit = 3
    selector {
      match_labels = {
        app = "reactapp"
      }
    }

    template {
      metadata {
        labels = {
          app = "reactapp"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.reactapp.metadata[0].name
        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          fs_group        = 1000
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          image = var.reactapp_image
          name  = "reactapp"
          security_context {
            allow_privilege_escalation = false
            privileged                 = false
            read_only_root_filesystem  = false
            run_as_non_root            = true
            capabilities {
              drop = ["ALL"]
            }
          }
          port {
            container_port = 80
          }
          volume_mount {
            name       = "nginx-cache"
            mount_path = "/var/cache/nginx"
          }
          volume_mount {
            name       = "nginx-run"
            mount_path = "/var/run"
          }
          volume_mount {
            name       = "app-config"
            mount_path = "/app/build/app-config.js"
            sub_path   = "app-config.js"
          }
        }
        volume {
          name = "nginx-cache"
          empty_dir {}
        }
        volume {
          name = "nginx-run"
          empty_dir {}
        }
        volume {
          name = "app-config"
          config_map {
            name = kubernetes_config_map_v1.reactapp_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "reactapp" {
  metadata {
    name      = "reactapp"
    namespace = "development"
  }

  depends_on = [module.eks]

  spec {
    selector = {
      app = "reactapp"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_service_account_v1" "reactapp" {
  metadata {
    name      = "reactapp"
    namespace = "development"
  }

  depends_on = [module.eks]
}

resource "kubernetes_ingress_v1" "main_ingress" {
  metadata {
    name      = "main-ingress"
    namespace = "development"
    annotations = {
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
    }
  }

  spec {
    ingress_class_name = "alb"
    rule {
      http {
        path {
          path      = "/api"
          path_type = "Prefix"
          backend {
            service {
              name = "javaapp"
              port {
                number = 80
              }
            }
          }
        }

        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "reactapp"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
