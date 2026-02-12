# ============================================================================
# Data Sources - Query existing Morpheus infrastructure
# ============================================================================

data "hpe_morpheus_group" "morph_install_group" {
  name = "All Clouds"
}

data "hpe_morpheus_cloud" "morph_install_cloud" {
  name = "VMware"
}

data "hpe_morpheus_resource_pool" "morph_install_resource_pool" {
  cloud_id = data.hpe_morpheus_cloud.morph_install_cloud.id
  id       = 775
}

data "hpe_morpheus_instance_type" "morph_install_instance_type" {
  name = "Ubuntu"
}

data "hpe_morpheus_instance_type_layout" "morph_install_layout" {
  name    = "VMware VM"
  version = "24.04"
}

data "hpe_morpheus_network" "morph_install_network" {
  id = 1074
}

data "hpe_morpheus_service_plan" "morph_install_plan" {
  id = 252
}

# ============================================================================
# Secrets - Store sensitive data in Morpheus Cypher
# ============================================================================

resource "hpe_morpheus_cypher_secret" "morph_install_user_password" {
  key   = format("morph_install_user_password-%s", timestamp())
  value = var.password
}

resource "hpe_morpheus_cypher_secret" "morph_install_license" {
  key   = format("morph_install_license-%s", timestamp())
  value = var.licenseKey
}

# ============================================================================
# Shell Script Task Resource - Morpheus Installation and Configuration
# ============================================================================
# The script content is read from morpheus-install.sh file in the same directory

resource "hpe_morpheus_task_shell_script" "morph_install_shell_task" {
  name                = format("morph_install-%s", timestamp())
  code                = "morph-app-deployment"
  labels              = ["morph_install"]
  source_type         = "local"
  script_content      = templatefile("${path.module}/morpheus-install.sh", {
    morph_version         = var.morph_version
    username              = var.username
    license_key_secret    = hpe_morpheus_cypher_secret.morph_install_license.key
    password_secret       = hpe_morpheus_cypher_secret.morph_install_user_password.key
  })
  sudo                = true
  retryable           = true
  retry_count         = 1
  retry_delay_seconds = 10
  allow_custom_config = true
}

# ============================================================================
# Provisioning Workflow - Orchestrates deployment tasks
# ============================================================================

resource "hpe_morpheus_workflow_provisioning" "morph_install_provisioning_workflow" {
  name        = format("morph_install-%s", timestamp())
  description = "Morpheus appliance installation and configuration workflow"
  labels      = ["morph_install"]
  platform    = "linux"
  visibility  = "private"
  
  task {
    task_id    = hpe_morpheus_task_shell_script.morph_install_shell_task.id
    task_phase = "postProvision"
  }
}

# ============================================================================
# Instance Resource - Launch Morpheus appliance VM
# ============================================================================

resource "hpe_morpheus_instance" "morph_install_cloud_instance" {
  name              = "morph-install-$${sequence + 1000}"
  cloud_id          = data.hpe_morpheus_cloud.morph_install_cloud.id
  group_id          = data.hpe_morpheus_group.morph_install_group.id
  instance_type_id  = data.hpe_morpheus_instance_type.morph_install_instance_type.id
  layout_id         = data.hpe_morpheus_instance_type_layout.morph_install_layout.id
  plan_id           = data.hpe_morpheus_service_plan.morph_install_plan.id
  task_set_id       = hpe_morpheus_workflow_provisioning.morph_install_provisioning_workflow.id
  
  network_interfaces = [
    {
      network_id = data.hpe_morpheus_network.morph_install_network.id
    }
  ]

  # Storage configuration
  volumes = [
    {
      root_volume              = true
      name                     = "root"
      size                     = 50
      storage_type_id          = 1
      datastore_auto_selection = "auto"
    }
  ]

  # Metadata tags
  tags = [
    {
      name  = "application"
      value = "morph_install"
    }
  ]

  # Additional VM configuration
  config = {
    resourcePoolId       = "pool-775"
    nestedVirtualization = "off"
    noAgent              = true
    createUser           = true
  }

  # Ignore name changes - Morpheus resolves ${sequence} at provisioning time
  # which causes the provider to see a different value than what Terraform planned
  lifecycle {
    ignore_changes = [name]
  }
}
