# Every variable here becomes a field in the App Blueprint form; keep it short.

variable "morpheus_url" {
  type        = string
  description = "URL of the Morpheus appliance that will provision the VM. Supplied via the tfvar secret."
}

variable "access_token" {
  type        = string
  sensitive   = true
  description = "API access token for the source appliance. Supplied via the tfvar secret."
}

variable "username" {
  type        = string
  description = "Admin username for the new appliance. Supplied via the tfvar secret."
}

variable "password" {
  type        = string
  sensitive   = true
  description = "Admin password for the new appliance. Needs at least 1 uppercase letter, 1 number and 1 symbol."

  validation {
    condition = (
      length(var.password) >= 8 &&
      can(regex("[A-Z]", var.password)) &&
      can(regex("[0-9]", var.password)) &&
      can(regex("[^A-Za-z0-9]", var.password))
    )
    error_message = "Password must be at least 8 characters with 1 uppercase letter, 1 number and 1 symbol."
  }
}

variable "licenseKey" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Morpheus license key. Leave empty to skip license activation."
}

variable "morph_version" {
  type        = string
  default     = "8.0.13-2"
  description = "Morpheus appliance package version to install, e.g. 8.0.13-2."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9]+)?$", var.morph_version))
    error_message = "morph_version must look like 8.0.13 or 8.0.13-2."
  }
}

variable "appliance_name" {
  type        = string
  default     = "The Matrix"
  description = "Display name for the new appliance."
}
