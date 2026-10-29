# LIB-0043: a workload's one Private Network. Its instances attach to it
# through compute-instance's private_network_id, and its Public Gateway through
# public-gateway's.
resource "scaleway_vpc_private_network" "this" {
  name       = var.name
  project_id = var.project_id
}
