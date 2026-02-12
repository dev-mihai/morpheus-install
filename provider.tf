terraform {
  required_providers {
    hpe = {
      source = "HPE/hpe"
      version = "1.0.0"
    }
  }
}

provider "hpe" {
  morpheus {
    url              = var.morpheus_url
    access_token     = var.access_token
  }
}