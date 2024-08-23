variable "morpheus_url" {
    type         = string
    default      = "<%= morpheus.applianceUrl %>"
    description  = "The Morpheus URL. This has a default value and typically should not be changed"
}

variable "access_token" {
    type         = string
    sensitive    = true
    default      = "<%= morpheus.apiAccessToken %>"
}

variable "morph_version" {
  type    = string
  default = "7.0.5-1"
}

variable "username" {
  type    = string
  default = "<%=morpheus.user.linuxUsername%>"
  description = "If not defined, the app will use the username from User Settings >> Linux Settings"
}

variable "password" {
  type    = string
  sensitive = true
  default = ""
  description = "Password must contain at least 1 uppercase letter(s), 1 number(s), and 1 symbol(s)"
}

variable "licenseKey" {
  type    = string
  default = ""
  sensitive = true
  description = "Specify your Morpheus License Key"
}

