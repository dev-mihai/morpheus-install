# ---- Look up existing infrastructure on the source appliance ---------------

data "hpe_morpheus_group" "morph_install_group" {
  name = local.group_name
}

data "hpe_morpheus_cloud" "morph_install_cloud" {
  name = local.cloud_name
}

data "hpe_morpheus_resource_pool" "morph_install_resource_pool" {
  cloud_id = data.hpe_morpheus_cloud.morph_install_cloud.id
  id       = local.resource_pool_id
}

data "hpe_morpheus_instance_type" "morph_install_instance_type" {
  name = "Ubuntu"
}

data "hpe_morpheus_instance_type_layout" "morph_install_layout" {
  name    = "VMware VM"
  version = local.layout_version
}

data "hpe_morpheus_network" "morph_install_network" {
  id = local.network_id
}

data "hpe_morpheus_service_plan" "morph_install_plan" {
  name                = local.plan_name
  provision_type_code = "vmware"
}

# ---- Per-deployment name suffix, generated once and kept in state ---------

resource "random_id" "deployment" {
  byte_length = 3
}

locals {
  deployment_id = "${local.instance_name_prefix}-${random_id.deployment.hex}"
}

# ---- Secrets the install script reads at run time via cypher.read() -------

resource "hpe_morpheus_cypher_secret" "morph_install_user_password" {
  key   = "${local.deployment_id}-user-password"
  value = var.password
}

resource "hpe_morpheus_cypher_secret" "morph_install_license" {
  key   = "${local.deployment_id}-license"
  value = var.licenseKey
}

# ---- Install script task (morpheus-install.sh, rendered by templatefile) --
# The script is idempotent and exits non-zero on failure so the retries apply.

resource "hpe_morpheus_task_shell_script" "morph_install_shell_task" {
  name        = local.deployment_id
  code        = "${local.deployment_id}-task"
  labels      = ["morph_install"]
  source_type = "local"
  script_content = templatefile("${path.module}/morpheus-install.sh", {
    morph_version       = var.morph_version
    download_base_url   = trimsuffix(local.download_base_url, "/")
    appliance_name      = var.appliance_name
    username            = var.username
    license_key_secret  = hpe_morpheus_cypher_secret.morph_install_license.key
    password_secret     = hpe_morpheus_cypher_secret.morph_install_user_password.key
    cloud_init_username = local.cloud_init_username
    ui_timeout_seconds  = local.ui_timeout_minutes * 60
  })
  sudo                = true
  retryable           = true
  retry_count         = 2
  retry_delay_seconds = 60
  allow_custom_config = true
}

# ---- Workflow that runs the task after the VM is provisioned ---------------

resource "hpe_morpheus_workflow_provisioning" "morph_install_provisioning_workflow" {
  name        = local.deployment_id
  description = "Morpheus appliance installation and configuration workflow"
  labels      = ["morph_install"]
  platform    = "linux"
  visibility  = "private"

  task {
    task_id    = hpe_morpheus_task_shell_script.morph_install_shell_task.id
    task_phase = "postProvision"
  }
}

# ---- The new appliance VM ---------------------------------------------------

resource "hpe_morpheus_instance" "morph_install_cloud_instance" {
  name             = local.deployment_id
  description      = "Morpheus ${var.morph_version} all-in-one appliance"
  cloud_id         = data.hpe_morpheus_cloud.morph_install_cloud.id
  group_id         = data.hpe_morpheus_group.morph_install_group.id
  instance_type_id = data.hpe_morpheus_instance_type.morph_install_instance_type.id
  layout_id        = data.hpe_morpheus_instance_type_layout.morph_install_layout.id
  plan_id          = data.hpe_morpheus_service_plan.morph_install_plan.id
  task_set_id      = hpe_morpheus_workflow_provisioning.morph_install_provisioning_workflow.id

  network_interfaces = [
    {
      network_id = data.hpe_morpheus_network.morph_install_network.id
    }
  ]

  volumes = [
    {
      root_volume              = true
      name                     = "root"
      size                     = local.root_volume_size
      storage_type_id          = 1
      datastore_id             = local.datastore_id
      datastore_auto_selection = local.datastore_id == null ? "auto" : null
    }
  ]

  # Labels, not tags: tags round-trip through vCenter and can come back
  # incomplete, which fails the apply and drops the VM from state.
  labels = ["morph_install", "morpheus-${var.morph_version}"]

  config_vmware = {
    resource_pool_id      = "pool-${data.hpe_morpheus_resource_pool.morph_install_resource_pool.id}"
    nested_virtualization = "off"
    no_agent              = false
    create_user           = true
  }

  # Provision + install + reconfigure often exceeds the 45 min default.
  timeouts = {
    create = "90m"
    delete = "30m"
  }
}

# ---- Outputs ---------------------------------------------------------------

output "instance_name" {
  value = hpe_morpheus_instance.morph_install_cloud_instance.name
}

output "instance_id" {
  value = hpe_morpheus_instance.morph_install_cloud_instance.id
}

output "appliance_url" {
  description = "URL of the new appliance (internal IP, self-signed cert)."
  value       = try("https://${hpe_morpheus_instance.morph_install_cloud_instance.connection_info[0]}", null)
}

output "admin_username" {
  description = "Login username for the new appliance. The password is the one from the tfvar secret."
  value       = var.username
}
