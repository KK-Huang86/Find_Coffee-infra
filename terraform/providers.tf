terraform {
  required_version = ">= 1.5"
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }
}

provider "linode" {
  token       = var.linode_token
  api_version = "v4beta"
}

# These providers reference the LKE cluster output.
# Terraform will create the cluster first, then configure these providers.
locals {
  kubeconfig = yamldecode(base64decode(linode_lke_cluster.find_coffee.kubeconfig))
  k8s_host   = local.kubeconfig.clusters[0].cluster.server
  k8s_ca     = base64decode(local.kubeconfig.clusters[0].cluster["certificate-authority-data"])
  k8s_token  = local.kubeconfig.users[0].user.token
}

provider "helm" {
  kubernetes {
    host                   = local.k8s_host
    cluster_ca_certificate = local.k8s_ca
    token                  = local.k8s_token
  }
}

provider "kubernetes" {
  host                   = local.k8s_host
  cluster_ca_certificate = local.k8s_ca
  token                  = local.k8s_token
}
