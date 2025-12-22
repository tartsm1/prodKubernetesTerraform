output "cluster_id" {
  value = aws_eks_cluster.main.id
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "oidc_provider_url" {
  value = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "cluster_arn" {
  value = aws_eks_cluster.main.arn
}

output "development_namespace" {
  value       = kubernetes_namespace_v1.development.metadata[0].name
  description = "Development namespace name"
}
