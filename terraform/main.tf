resource "linode_lke_cluster" "find_coffee" {
  label       = "find-coffee"
  region      = var.region
  k8s_version = var.k8s_version
  tier        = "standard"

  pool {
    type  = var.node_type
    count = var.node_count
  }
}
