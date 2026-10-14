# Environment settings hidden from the App Blueprint form.
# Values below are for the homelab appliance; use a branch per environment.

locals {
  # Placement
  group_name       = "All Clouds"
  cloud_name       = "VMware"
  resource_pool_id = 775  # MRPH-SANDBOX
  network_id       = 1074 # DPG-VLAN20-Compute
  plan_name        = "2 CPU, 16GB Memory"
  layout_version   = "24.04"
  root_volume_size = 50
  datastore_id     = null # null = let Morpheus auto-select; e.g. 364 = ESXi-HOST01-NVME01

  # Installer behaviour
  instance_name_prefix = "morph-install"
  download_base_url    = "https://downloads.morpheusdata.com/files"
  cloud_init_username  = "morpheusci"
  ui_timeout_minutes   = 25
}
