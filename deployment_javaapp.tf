resource "kubernetes_deployment_v1" "javaapp" {
  metadata {
    name      = "javaapp"
    namespace = "development"
    labels = {
      app = "javaapp"
    }
  }

  spec {
    replicas               = 2
    revision_history_limit = 3
    selector {
      match_labels = {
        app = "javaapp"
      }
    }

    template {
      metadata {
        labels = {
          app = "javaapp"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.javaapp.metadata[0].name
        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          fs_group        = 1000
          seccomp_profile {
            type = "RuntimeDefault"
          }
          se_linux_options {
            level = "s0:c123,c456"
            role  = "system_r"
            type  = "container_t"
            user  = "system_u"
          }
        }

        container {
          image = var.javaapp_image
          name  = "javaapp"

          env {
            name  = "AWS_REGION"
            value = var.region
          }

          env {
            name  = "COGNITO_USER_POOL_ID"
            value = var.cognito_user_pool_id
          }

          env {
            name  = "COGNITO_CLIENT_ID"
            value = var.cognito_client_id
          }

          env {
            name  = "threadsCount"
            value = var.threads_count
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
          liveness_probe {
            http_get {
              path = "/api/test"
              port = 8888
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }
          readiness_probe {
            http_get {
              path = "/api/test"
              port = 8888
            }
            initial_delay_seconds = 10
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
          }
          security_context {
            allow_privilege_escalation = false
            privileged                 = false
            read_only_root_filesystem  = false
            run_as_non_root            = true
            capabilities {
              drop = ["ALL"]
            }
            se_linux_options {
              level = "s0:c123,c456"
              role  = "system_r"
              type  = "container_t"
              user  = "system_u"
            }
          }
          port {
            container_port = 8888
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "javaapp" {
  metadata {
    name      = "javaapp"
    namespace = "development"
  }

  depends_on = [module.eks]

  spec {
    selector = {
      app = "javaapp"
    }

    port {
      port        = 80
      target_port = 8888
    }

    type = "ClusterIP"
  }
}

resource "aws_iam_role" "javaapp" {
  name = "javaapp-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "javaapp_dynamodb" {
  name        = "javaapp-dynamodb-policy"
  description = "Limited DynamoDB access for javaapp"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/Tasks",
          "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/Tasks/index/*"
        ]
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "javaapp_dynamodb" {
  role       = aws_iam_role.javaapp.name
  policy_arn = aws_iam_policy.javaapp_dynamodb.arn
}


resource "kubernetes_service_account_v1" "javaapp" {
  metadata {
    name      = "javaapp"
    namespace = "development"
  }

  depends_on = [module.eks]
}

resource "aws_eks_pod_identity_association" "javaapp" {
  cluster_name    = module.eks.cluster_name
  namespace       = "development"
  service_account = kubernetes_service_account_v1.javaapp.metadata[0].name
  role_arn        = aws_iam_role.javaapp.arn
}



