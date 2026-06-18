output "cluster_endpoint" {
  value       = local.k8s_host
  description = "LKE API server endpoint"
}

output "kubeconfig" {
  value       = linode_lke_cluster.find_coffee.kubeconfig
  sensitive   = true
  description = "Base64-encoded kubeconfig"
}

output "get_kubeconfig" {
  value       = "terraform output -raw kubeconfig | base64 -d > ~/.kube/find-coffee.yaml && export KUBECONFIG=~/.kube/find-coffee.yaml"
  description = "Command to export kubeconfig locally"
}

output "argocd_initial_password_command" {
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  description = "Command to get ArgoCD initial admin password"
}

output "argocd_port_forward" {
  value       = "kubectl port-forward svc/argocd-server -n argocd 8080:443"
  description = "Command to access ArgoCD UI at https://localhost:8080"
}
