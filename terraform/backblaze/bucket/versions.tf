terraform {
  required_providers {
    b2 = {
      source  = "registry.terraform.io/Backblaze/b2"
      version = "~> 0.14"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
