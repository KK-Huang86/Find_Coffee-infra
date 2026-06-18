# nginx Ingress Controller 
resource "helm_release" "ingress_nginx" {
  depends_on       = [linode_lke_cluster.find_coffee]
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.12.0"

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  # Wait for LoadBalancer IP to be assigned
  wait    = true
  timeout = 300
}

# cert-manager
resource "helm_release" "cert_manager" {
  depends_on       = [linode_lke_cluster.find_coffee]
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = "v1.17.2"

  set {
    name  = "crds.enabled"
    value = "true"
  }

  wait    = true
  timeout = 300
}

# ArgoCD 
resource "helm_release" "argocd" {
  depends_on       = [linode_lke_cluster.find_coffee]
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.8.23"

  wait    = true
  timeout = 600
}
