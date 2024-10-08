terraform {
  required_providers {
    morpheus    = {
    source      = "gomorpheus/morpheus"
    version     = "0.9.10"
    }
  }
}

provider "morpheus" {
  url           = var.morpheus_url
  access_token  = var.access_token
}