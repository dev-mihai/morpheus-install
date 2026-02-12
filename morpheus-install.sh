#!/bin/bash
serverUrl="<%= morpheus.applianceUrl %>"
accessToken="<%= morpheus.apiAccessToken %>"
morph_version=${morph_version}
licenseKey="<%=cypher.read('secret/${license_key_secret}')%>"
username=${username}
password="<%=cypher.read('secret/${password_secret}')%>"
internal_ip="<%= server.internalIp %>"

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

cp /etc/morpheus/morpheus.rb /etc/morpheus/morpheus.rb.old 
rm /etc/morpheus/morpheus.rb
echo "appliance_url 'https://$internal_ip'" >> /etc/morpheus/morpheus.rb

echo "****Reconfiguring Morpheus****" >> /tmp/morph_install_log.txt 
morpheus-ctl reconfigure >> /tmp/morph_install_log.txt  

# Check if the UI is up
log_file="/var/log/morpheus/morpheus-ui/current"  # Morpheus current log file path
ui_started=false
timeout=1500  # Set timeout in seconds for UI state check
seconds_counter=0
last_logged=0
log_interval=300  # Log progress every 5 minutes

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Waiting for Morpheus UI to start (timeout in $((timeout / 60)) minutes)..." >> /tmp/morph_install_log.txt

while ! $ui_started; do # keep checking the log file for Morpheus UI banner until found
    if grep -Fq "****************************************" "$log_file"; then
        # Found UI banner
        ui_started=true
        echo "Morpheus UI is up after $seconds_counter seconds" >> /tmp/morph_install_log.txt
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
            echo "Trying to apply the Morpheus license" >> /tmp/morph_install_log.txt
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
            lic_success=$(curl -XPOST "$app_url/api/license" \
                -H "Authorization: BEARER $newAppAccessToken" \
                -H "Content-Type: application/json" \
                -k \
                -d '{
                    "license": "'$licenseKey'"
                }' | python3 -c 'import sys, json; print(json.load(sys.stdin)["success"])')

            if [[ $lic_success == "True" ]]; then
                echo "License applied successfully" >> /tmp/morph_install_log.txt
            else
                echo "License application failed" >> /tmp/morph_install_log.txt
            fi
        else
            echo "Appliance setup failed" >> /tmp/morph_install_log.txt
            lic_selected=false
        fi
    fi

    sleep 10  # Wait 10 seconds before checking again
    ((seconds_counter += 10))

    # Log progress every 5 minutes instead of constantly
    if ((seconds_counter - last_logged >= log_interval)); then
        minutes=$((seconds_counter / 60))
        echo "Still waiting for UI to start... [$minutes minutes elapsed]" >> /tmp/morph_install_log.txt
        last_logged=$seconds_counter
    fi

    if ((seconds_counter >= timeout)); then
        timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        echo "[$timestamp] Timeout waiting for Morpheus UI to start after $((timeout / 60)) minutes" >> /tmp/morph_install_log.txt
        timeout_initiated=true
        break
    fi
done

echo "app_url=$app_url,newAppAccessToken=$newAppAccessToken"

# Updating cloud-init settings
echo "Updating provisioning settings..." >> /tmp/morph_install_log.txt
settings_success=$(curl --request PUT \
     --url "$app_url/api/provisioning-settings" \
     --header "Authorization: BEARER $newAppAccessToken" \
     --header 'accept: application/json' \
     --header 'content-type: application/json' \
     --data '
{
  "provisioningSettings": {
    "cloudInitUsername": "morpheusci",
    "cloudInitPassword": "'$password'"
  }
}
' -k | python3 -c 'import sys, json; print(json.load(sys.stdin)["success"])')

if [[ $settings_success == "True" || $settings_success == "true" ]]; then
    echo "Provisioning settings updated successfully" >> /tmp/morph_install_log.txt
else
    echo "Provisioning settings update failed" >> /tmp/morph_install_log.txt
fi

# Updating user-settings
echo "Updating user settings..." >> /tmp/morph_install_log.txt
user_success=$(curl --request PUT \
     --url "$app_url/api/user-settings" \
     --header "Authorization: BEARER $newAppAccessToken" \
     --header 'accept: application/json' \
     --header 'content-type: application/json' \
     --data '
{
  "user": {
    "username": "'$username'",
    "firstName": "'$username'",
    "linuxUsername": "'$username'",
    "linuxPassword": "'$password'",
    "windowsUsername": "'$username'",
    "windowsPassword": "'$password'"
  }
}
' -k | python3 -c 'import sys, json; print(json.load(sys.stdin)["success"])')

if [[ $user_success == "True" || $user_success == "true" ]]; then
    echo "User settings updated successfully" >> /tmp/morph_install_log.txt
else
    echo "User settings update failed" >> /tmp/morph_install_log.txt
fi

# Script completion
echo "" >> /tmp/morph_install_log.txt
echo "========================================" >> /tmp/morph_install_log.txt
echo "Morpheus installation script completed successfully" >> /tmp/morph_install_log.txt
echo "Appliance URL: $app_url" >> /tmp/morph_install_log.txt
echo "Completion time: $(date '+%Y-%m-%d %H:%M:%S')" >> /tmp/morph_install_log.txt
echo "========================================" >> /tmp/morph_install_log.txt
