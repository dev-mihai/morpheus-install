# Morpheus Appliance Deployment with Terraform

## Overview

This Terraform project automates the deployment of a Morpheus appliance on a VMware environment. It handles the VM provisioning, installation, initial configuration, and license application - all in one go.

## What's Included

- **main.tf** - The main Terraform configuration with resources for the appliance
- **morpheus-install.sh** - The installation and configuration script (loaded as a template)
- **variables.tf** - Define your deployment-specific values here
- **provider.tf** - Morpheus provider configuration

## Prerequisites

1. **Morpheus License Key** - You'll need a valid license key to activate the appliance (update in `variables.tf`)
2. **Morpheus Access Token** - With permissions to create instances and tasks
   - Pro tip: Increase the token validity to at least 3600 seconds (it defaults to 1440)
3. **VMware Environment** - With at least one cloud, network, and resource pool configured in Morpheus

## Quick Setup

### 1. Create Your tfvars File

Create a `terraform.tfvars` file in the root directory with your configuration:

```hcl
morpheus_url   = "https://your-morpheus-url"
access_token   = "your-api-token-here"
morph_version  = "8.0.13-2"
username       = "admin"
password       = "YourSecurePassword123!"
licenseKey     = "your-license-key-here"
```

**Important:** The `.tfvars` file is already in `.gitignore` to protect your secrets - never commit it to git!

### 2. Update the Data Sources in main.tf

Adjust the data sources to match your environment:

- `hpe_morpheus_cloud` - Set the cloud name (e.g., "VMware")
- `hpe_morpheus_network` - Set the network ID (find this in Morpheus: Infrastructure → Networks)
- `hpe_morpheus_service_plan` - Set the plan ID (find in Morpheus: Admin → Plans)
- `hpe_morpheus_resource_pool` - Set the resource pool ID (find in Morpheus: Infrastructure → Clouds → Resource Pools)

### 3. Deploy

```bash
terraform init
terraform plan
terraform apply --auto-approve
```

## Required Variables Explained

Here's what you need to define in `terraform.tfvars`:

| Variable          | Required | Description                                          | Example                                   |
| ----------------- | -------- | ---------------------------------------------------- | ----------------------------------------- |
| `morpheus_url`  | Yes      | URL of your Morpheus appliance                       | `https://morpheus.company.com`          |
| `access_token`  | Yes      | API token with instance creation permissions         | Get from → Users Settings → API Access |
| `morph_version` | Yes      | Morpheus appliance version to install                | `8.0.13-2`                              |
| `username`      | Yes      | Admin username for the new appliance                 | `admin`                                 |
| `password`      | Yes      | Admin password (must have uppercase, number, symbol) | `Morpheus123!`                          |
| `licenseKey`    | Yes      | Morpheus license key                                 | Your enterprise or community license      |

## Environment Requirements

Before you deploy, make sure you have in Morpheus:

1. **A Vmware Cloud**
   - Note the cloud name or ID
2. **At least one Network** in that cloud
   - Navigate to: Infrastructure → Networks
   - Get the network ID from the URL or list
3. **At least one Resource Pool** in that cloud
   - Navigate to: Infrastructure → Clouds → [Your Cloud] → Resource Pools
   - Get the pool ID
4. **At least one Service Plan**
   - Navigate to: Admin → Service Plans
   - Get the plan ID (we default to ID 252, adjust if needed)

Then update these IDs in `main.tf` under the data sources section.

## How It Works

1. **VM Provisioning** - Terraform creates an Ubuntu VM in your specified resource pool
2. **Script Injection** - The `morpheus-install.sh` script runs post-provisioning via a provisioning workflow
3. **Installation** - The script downloads and installs Morpheus, configures networking
4. **Initialization** - Sets up the appliance, creates the admin user, applies the license
5. **Configuration** - Updates cloud-init and user settings via the API

The installation script logs everything to `/tmp/morph_install_log.txt` on the deployed VM for troubleshooting.

## Installation Script Details

The `morpheus-install.sh` script handles:

- Removing unattended upgrades that could interfere
- Downloading the Morpheus .deb package
- Installing and reconfiguring Morpheus
- Waiting for the UI to come up (with smart logging)
- Running the initial setup API call
- Applying the license
- Configuring cloud-init and user settings

**Smart Logging**: Instead of spamming your logs, the script:

- Logs progress every 5 minutes while waiting for UI startup
- Shows only success/failure for API calls (not entire JSON responses)
- Provides a summary at the end with completion time

## Troubleshooting

If things go sideways, SSH into the deployed VM and check:

```bash
tail -f /tmp/morph_install_log.txt
```

This log file has all the details about what happened during installation.

## Notes

- The VM name will be auto-generated (e.g., `morph-install-1000`)
- The admin user credentials are taken from your variables
- The script waits up to 25 minutes for the UI to start - if it times out, check resource pool capacity

## Disclaimer

This package is provided as-is, without warranty of any kind. By using these resources, you agree to:

1. **No Support** - Official support for Morpheus usage, configuration, or troubleshooting is not included. For Morpheus-specific issues, consider a professional services engagement.
2. **Your Risk** - You own any consequences from using this
3. **No Liability** - I'm not responsible for any issues this causes
4. **As-Is** - I try to make it work, but no guarantees it'll work for everything
