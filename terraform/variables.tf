variable "linode_token" {
  type      = string
  sensitive = true
  description = "Linode Personal Access Token"
}

variable "region" {
  type        = string
  default     = "ap-southeast"
  description = "Linode region (ap-southeast = Singapore, closest to Taiwan)"
}

variable "k8s_version" {
  type        = string
  default     = "1.32"
  description = "LKE Kubernetes version"
}

variable "node_count" {
  type        = number
  default     = 2
  description = "Number of worker nodes"
}

variable "node_type" {
  type        = string
  default     = "g6-standard-1"
  description = "Linode instance type (g6-standard-1 = 1 vCPU / 2GB RAM)"
}

variable "letsencrypt_email" {
  type        = string
  description = "Email for Let's Encrypt certificate notifications"
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub Personal Access Token - needs repo read permission for ArgoCD"
}

variable "github_username" {
  type        = string
  description = "GitHub username"
  default     = "vup4k0806"
}

variable "infra_repo_url" {
  type        = string
  description = "HTTPS URL of the infra repo that ArgoCD watches"
  default     = "https://github.com/KK-Huang86/Find_Coffee-infra"
}
