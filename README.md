# Morpheus TF All-in-One Deployment Guide

## Overview

This guide outlines the process for deploying a Morpheus application on a single VMware server using the Morpheus Terraform provider.

## Prerequisites

1. **VMware Cloud Integration:** a VMware cloud integration on your existing appliance is required.
2. **Morpheus License Key**: Required to activate your newly deployed appliance.
3. **Access Token Configuration**: Increase the "morpheus-terraform" access token validity interval to at least 3600 seconds (default is 1440 seconds) to prevent authentication errors.

## Deployment Preparation

### Updating Terraform Data Resources

Modify the `main.tf` file to update the following data resources according to your environment:

1. `morpheus_cloud` (e.g., `name = "VMware"`)
2. `morpheus_network` (e.g., `name = "VLAN-060-Morpheus"`)
3. `morpheus_group` (e.g., `name = "All"`)
4. `morpheus_resource_pool` (e.g., `name = "Sandbox"`)

The following resources typically use default values and may not require changes:

- `morpheus_instance_type` (e.g., `name = "Ubuntu"`)
- `morpheus_instance_layout` (e.g., `name = "VMware VM"`)
- `morpheus_plan` (e.g., `name = "2 CPU, 16GB Memory"`)

## Deployment Process

1. In Morpheus, navigate to **Administration > Integrations** and create a Git-type integration using the repository URL: `https://github.com/dev-mihai/morpheus-install`.
2. Go to **Library > Blueprints > App Blueprints** and create a Terraform app blueprint. Reference the SCM integration you created in Step 1, as shown in this [example](https://d.pr/i/4WAHjk).
3. Deploy the app. When prompted under the **Terraform Variables** dropdown, add your Morpheus License.

## Disclaimer

This package is provided as-is, without warranty of any kind. By using these resources, you agree to the following:

1. **No Morpheus Support**: Official support for Morpheus usage, configuration, or troubleshooting is not included. For Morpheus-specific issues, consider a professional services engagement.
2. **Risk Assumption**: You accept full responsibility for any consequences arising from the implementation or execution of the provided materials.
3. **Liability Limitation**: We are not liable for any damages (direct or indirect) resulting from the use of this package.
4. **No Guarantees**: While efforts have been made to ensure accuracy and security, we cannot guarantee suitability for all environments or purposes.
