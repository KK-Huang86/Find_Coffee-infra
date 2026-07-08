# ArgoCD Repository Secret
# Tells ArgoCD how to authenticate with the infra GitHub repo.
# ArgoCD discovers this secret via the label argocd.argoproj.io/secret-type=repository.
resource "kubernetes_secret" "argocd_repo" {
  depends_on = [helm_release.argocd]

  metadata {
    name      = "find-coffee-infra-repo"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type = "git"
    url  = var.infra_repo_url
  }
}
