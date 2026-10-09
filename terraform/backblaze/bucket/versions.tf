terraform {
  required_providers {
    b2 = {
      source  = "Backblaze/b2"
      version = "~> 0.14"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
