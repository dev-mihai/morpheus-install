terraform {
  # No required_version on purpose: any constraint makes Morpheus cap the
  # runtime at 1.5.5. Without one it uses the appliance default version.
  required_providers {
    hpe = {
      source  = "HPE/hpe"
      version = "~> 2.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "hpe" {
  morpheus {
    url          = var.morpheus_url
    access_token = var.access_token
  }
}
