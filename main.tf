# Define Data Sources
data "morpheus_group" "morph_install_group" {
  name = "All"
}

data "morpheus_cloud" "morph_install_cloud" {
  name = "VMware"
}

data "morpheus_resource_pool" "morph_install_resource_pool" {
  id       = 199
  cloud_id = data.morpheus_cloud.morph_install_cloud.id
}

data "morpheus_instance_type" "morph_install_instance_type" {
  name = "Ubuntu"
}

data "morpheus_instance_layout" "morph_install_layout" {
  name    = "VMware VM"
  version = "22.04"
}

data "morpheus_network" "morph_install_network" {
  name = "VLAN-060-Morpheus"
}

data "morpheus_plan" "morph_install_plan" {
  name            = "2 CPU, 16GB Memory"
  provision_type  = "VMware"
}

resource "morpheus_cypher_secret" "morph_install_user_password" {
  key   = format("morph_install_user_password-%s", timestamp())
  value = var.password
}

resource "morpheus_cypher_secret" "morph_install_license" {
  key   = format("morph_install_license-%s", timestamp())
  value = var.licenseKey
}

# Define Shell Script Task Resource
resource "morpheus_shell_script_task" "morph_install_shell_task" {
  name                = format("morph_install-%s", timestamp())
  code                = "morph-app-deployment"
  labels              = ["morph_install"]
  source_type         = "local"
  script_content      = <<EOF
   #!/bin/bash
   serverUrl="<%= morpheus.applianceUrl %>"
   accessToken="<%= morpheus.apiAccessToken %>"
   morph_version=${var.morph_version}
   licenseKey="<%=cypher.read('secret/${morpheus_cypher_secret.morph_install_license.key}')%>"
   # username="<%=morpheus.user.linuxUsername%>"
   username=${var.username}
   password="<%=cypher.read('secret/${morpheus_cypher_secret.morph_install_user_password.key}')%>"
   internal_ip="<%= server.internalIp %>"
   external_ip="<%= server.externalIp %>"
   provisionType="<%=instance.provisionType%>"

   # When deploying in AWS. Not fully tested yet
   # internal_ip=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
   # external_ip=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
   # provisionType="amazon"
   
   app_url=""
   status=""
   newAppAccessToken=""
   lic_status=""
   lic_selected=false
   app_setup_failed=false
   ui_down=false
   timeout_initiated=false
   
   echo "****Disable Unattended Upgrades****" >> /tmp/morph_install_log.txt 
   yes Y | apt remove unattended-upgrades >> /tmp/morph_install_log.txt  
   
   echo "****Downloading Morpheus****" >> /tmp/morph_install_log.txt 
   wget "https://downloads.morpheusdata.com/files/morpheus-appliance_"$morph_version"_amd64.deb" >> /tmp/morph_install_log.txt  
   
   # Wait for dpkg frontend file lock to be released
   echo "****Wait for dpkg frontend file lock to be released****" >> /tmp/morph_install_log.txt 
   while fuser /var/lib/dpkg/lock >/dev/null 2>&1 ; do
       echo "Waiting for dpkg lock to be released..."
       sleep 5
   done
   
   echo "****Installing Morpheus****" >> /tmp/morph_install_log.txt 
   dpkg -i "morpheus-appliance_"$morph_version"_amd64.deb" >> /tmp/morph_install_log.txt  
   
   #Change the morpheus.rb file to use the IP address instead of hostname for appliance url
   app_ip=$internal_ip
   if [[ $provisionType == "azure"  ||  $provisionType == "amazon"  ||  $provisionType == "google" ]]; then
   	app_ip=$external_ip
   fi
   
   cp /etc/morpheus/morpheus.rb /etc/morpheus/morpheus.rb.old 
   rm /etc/morpheus/morpheus.rb
   echo "appliance_url 'https://$app_ip'" >> /etc/morpheus/morpheus.rb
   
   echo "****Reconfiguring Morpheus****" >> /tmp/morph_install_log.txt 
   morpheus-ctl reconfigure >> /tmp/morph_install_log.txt  
   
   
   # Check if the UI is up
   log_file="/var/log/morpheus/morpheus-ui/current"  # Morpheus current log file path
   ui_started=false
   timeout=1500  # Set timeout in seconds for UI state check
   seconds_counter=0
   
   while ! $ui_started; do # keep checking the log file for Morpheus UI banner until found
       if grep -Fq "****************************************" "$log_file"; then
           # Found UI banner
           ui_started=true
           echo "Morpheus UI is up" >> /tmp/morph_install_log.txt
           sleep 20  # Wait 20 seconds before performing the initial setup
   
           # Initial Morpheus Setup
           config="/etc/morpheus/morpheus.rb"
           app_url=""
   
           while IFS= read -r line; do
               if [[ "$line" == *"appliance_url '"* ]]; then
                   app_url=$(echo "$line" | cut -d "'" -f2)
                   echo "App URL = $app_url" >> /tmp/morph_install_log.txt
               fi
           done < "$config"
   
           status=$(curl -XPOST "$app_url/api/setup" \
               -H "accept: application/json" \
               -H "Content-Type: application/json" \
               -k \
               -d '{
                   "hubmode": "skip",
                   "applianceName": "The Matrix",
                   "applianceUrl": "'$app_url'",
                   "accountName": "MasterTenant",
                   "firstName": "Morpheus",
                   "lastName": "Admin",
                   "username": "'$username'",
                   "email": "noemail@morpheusdata.com",
                   "password": "'$password'"
               }' | python3 -c 'import sys, json; print(json.load(sys.stdin)["success"])')
   
           echo "Morpheus App Setup Status = $status" >> /tmp/morph_install_log.txt
   
           if [[ $status == "True" ]]; then
               echo "Try to add a license" >> /tmp/morph_install_log.txt
               sleep 5
   
               # Get API access token from the new appliance
               newAppAccessToken=$(curl -XPOST "$app_url/oauth/token?client_id=morph-api&grant_type=password&scope=write" \
                   -H "Content-Type: application/x-www-form-urlencoded" \
                   -k \
                   -d "username=$username" \
                   -d "password=$password" \
                   | python3 -c 'import sys, json; print(json.load(sys.stdin)["access_token"])')
   
               sleep 5
   
               # Apply license
               response=$(curl -XPOST "$app_url/api/license" \
                   -H "Authorization: BEARER $newAppAccessToken" \
                   -H "Content-Type: application/json" \
                   -k \
                   -d '{
                       "license": "'$licenseKey'"
                   }' | python3 -c 'import sys, json; print(json.load(sys.stdin))')
   
               echo "License status = $response" >> /tmp/morph_install_log.txt
               lic_status=$response
           else
               echo "No license selected" >> /tmp/morph_install_log.txt
               lic_selected=false
           fi
       else
           ui_down=true
           timestamp=$(date +"%Y-%m-%d %H:%M:%S")
           echo "[$timestamp] UI is down" >> /tmp/morph_install_log.txt
       fi
   
       sleep 5  # Wait 5 seconds before checking again
       ((seconds_counter++))
   
       if ((seconds_counter >= timeout)); then
           timestamp=$(date +"%Y-%m-%d %H:%M:%S")
           echo "[$timestamp] timeout initiated" >> /tmp/morph_install_log.txt
           timeout_initiated=true
           break
       fi
   done
   
   echo "app_url=$app_url,newAppAccessToken=$newAppAccessToken"
   
EOF
  sudo                = true
  retryable           = true
  retry_count         = 1
  retry_delay_seconds = 10
  allow_custom_config = true
}

# Define Provisioning Workflow Resource
resource "morpheus_provisioning_workflow" "morph_install_provisioning_workflow" {
  name        = format("morph_install-%s", timestamp())
  description = "Terraform provisioning workflow"
  labels      = ["morph_install"]
  platform    = "linux"
  visibility  = "private"
  task {
    task_id    = morpheus_shell_script_task.morph_install_shell_task.id
    task_phase = "postProvision"
  }
}

# Define vSphere Instance Resource
resource "morpheus_vsphere_instance" "morph_install_cloud_instance" {
  name               = "morph-install-$${sequence + 1000}"
  description        = "morph-install - provisioning the Instance"
  cloud_id           = data.morpheus_cloud.morph_install_cloud.id
  group_id           = data.morpheus_group.morph_install_group.id
  instance_type_id   = data.morpheus_instance_type.morph_install_instance_type.id
  instance_layout_id = data.morpheus_instance_layout.morph_install_layout.id
  plan_id            = data.morpheus_plan.morph_install_plan.id
  resource_pool_id   = data.morpheus_resource_pool.morph_install_resource_pool.id
  labels             = ["morph_install"]
  workflow_id        = morpheus_provisioning_workflow.morph_install_provisioning_workflow.id

  volumes {
    # datastore_id     = 62 - [local-NVME], 13 - [TrueNAS], 36 - [local-SSD]
    datastore_id     = 62
    name             = "root"
    root             = true
    size             = 50
    storage_type     = 1
  }

  skip_agent_install = false

  interfaces {
    network_id = data.morpheus_network.morph_install_network.id
  }

  tags = {
    name = "morph_install"
  }

  evar {
    name   = "application"
    value  = "morph_install"
    export = true
    masked = true
  }
}
