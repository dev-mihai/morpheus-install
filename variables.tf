variable "morpheus_url" {
    type         = string
    description  = "If not defined, the app will use the URL from the Settings >> Appliance Settings"
}

variable "access_token" {
  type         = string
  sensitive    = true
  description  = "If not defined, the app will use the API access token from the User Settings >> API Access Token"
}

variable "morph_version" {
  type    = string
  default = "8.0.13-2"
}

variable "username" {
  type    = string
  description = "If not defined, the app will use the username from User Settings >> Linux Settings"
}

variable "password" {
  type    = string
  sensitive = true
  description = "Password must contain at least 1 uppercase letter(s), 1 number(s), and 1 symbol(s)"
}

variable "licenseKey" {
  type    = string
  sensitive = true
  description = "Provide a Morpheus License Key"
}

