variable "morpheus_url" {
    type         = string
}

variable "access_token" {
    type         = string
    sensitive    = true
}

variable "username" {
  type    = string
  default = "mihai"
}

variable "password" {
  type    = string
  sensitive = true
}

variable "licenseKey" {
  type    = string
  sensitive = true
}

variable "morph_version" {
  type    = string
  default = "6.2.7-2"
}