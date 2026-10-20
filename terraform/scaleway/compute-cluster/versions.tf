# ADR-0145: this module now creates its own scaleway_vpc_private_network/
# scaleway_vpc_public_gateway* resources directly (previously composition-
# only), so it needs a real required_providers block. move_to_ipam/
# ipam_config (the Public Gateway v2/IPAM-mode arguments) need provider
# >= 2.52 -- every .terraform.lock.hcl in this repo is already locked to
# 2.86.0, comfortably above that floor, so ~> 2.0 is left as-is.
terraform {
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.0"
    }
  }
}
