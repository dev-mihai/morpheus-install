#!/bin/bash
serverUrl="<%= morpheus.applianceUrl %>"
accessToken="<%= morpheus.apiAccessToken %>"
morph_version=${var.morph_version}
licenseKey="<%=cypher.read('secret/${morpheus_cypher_secret.tf_example_cypher_secret-license.key}')%>"
username="<%=morpheus.user.linuxUsername%>"
password="<%=cypher.read('secret/${morpheus_cypher_secret.tf_example_cypher_secret.key}')%>"
internal_ip="<%= server.internalIp %>"
external_ip="<%= server.externalIp %>"
provisionType="<%=instance.provisionType%>"
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

echo "****Disable Unattended Upgrades****" >> /tmp/keymaker_log.txt 
yes Y | apt remove unattended-upgrades >> /tmp/keymaker_log.txt  

echo "****Download Morpheus****" >> /tmp/keymaker_log.txt 
wget "https://downloads.morpheusdata.com/files/morpheus-appliance_"$morph_version"_amd64.deb" >> /tmp/keymaker_log.txt  

# Wait for dpkg frontend file lock to be released
echo "****Wait for dpkg frontend file lock to be released****" >> /tmp/keymaker_log.txt 
while fuser /var/lib/dpkg/lock >/dev/null 2>&1 ; do
    echo "Waiting for dpkg lock to be released..."
    sleep 5
done

echo "****Install Morpheus****" >> /tmp/keymaker_log.txt 
dpkg -i "morpheus-appliance_"$morph_version"_amd64.deb" >> /tmp/keymaker_log.txt  

#Change the morpheus.rb file to use the IP address instead of hostname for appliance url
app_ip=$internal_ip
if [[ $provisionType == "azure"  ||  $provisionType == "amazon"  ||  $provisionType == "google" ]]; then
	app_ip=$external_ip
fi

cp /etc/morpheus/morpheus.rb /etc/morpheus/morpheus.rb.old 
rm /etc/morpheus/morpheus.rb
echo "appliance_url 'https://$app_ip'" >> /etc/morpheus/morpheus.rb

echo "****Reconfigure Morpheus****" >> /tmp/keymaker_log.txt 
morpheus-ctl reconfigure >> /tmp/keymaker_log.txt  


# Check if the UI is up
log_file="/var/log/morpheus/morpheus-ui/current"  # Morpheus current log file path
ui_started=false
timeout=1500  # Set timeout in seconds for UI state check
seconds_counter=0

while ! $ui_started; do # keep checking the log file for Morpheus UI banner until found
    if grep -Fq "****************************************" "$log_file"; then
        # Found UI banner
        ui_started=true
        echo "Morpheus UI is up" >> /tmp/keymaker_log.txt
        sleep 20  # Wait 20 seconds before performing the initial setup

        # Initial Morpheus Setup
        config="/etc/morpheus/morpheus.rb"
        app_url=""

        while IFS= read -r line; do
            if [[ "$line" == *"appliance_url '"* ]]; then
                app_url=$(echo "$line" | cut -d "'" -f2)
                echo "App URL = $app_url" >> /tmp/keymaker_log.txt
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

        echo "Morpheus App Setup Status = $status" >> /tmp/keymaker_log.txt

        if [[ $status == "True" ]]; then
            echo "Try to add a license" >> /tmp/keymaker_log.txt
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

            echo "License status = $response" >> /tmp/keymaker_log.txt
            lic_status=$response
        else
            echo "No license selected" >> /tmp/keymaker_log.txt
            lic_selected=false
        fi
    else
        ui_down=true
        echo "UI is down" >> /tmp/keymaker_log.txt
    fi

    sleep 1  # Wait 1 second before checking again
    ((seconds_counter++))

    if ((seconds_counter >= timeout)); then
        # If timeout reached then end log file check
        echo "timeout initiated" >> /tmp/keymaker_log.txt
        timeout_initiated=true
        break
    fi
done

echo "app_url=$app_url,newAppAccessToken=$newAppAccessToken"