#!/bin/bash
# Morpheus all-in-one appliance installer.
# Rendered by Terraform templatefile(), run by Morpheus as a post-provision
# task with sudo. Bash braces are written with a doubled dollar so templatefile
# leaves them alone; <%= %> tags are resolved by Morpheus at run time.
# Fails fast (die -> exit 1 -> task retry) and is safe to re-run.

set -uo pipefail
export DEBIAN_FRONTEND=noninteractive

# ---- inputs from Terraform ------------------------------------------------
morph_version="${morph_version}"
download_base_url="${download_base_url}"
appliance_name="${appliance_name}"
username="${username}"
cloud_init_username="${cloud_init_username}"
ui_timeout=${ui_timeout_seconds}

# ---- inputs from Morpheus -------------------------------------------------
licenseKey="<%=cypher.read('secret/${license_key_secret}')%>"
password="<%=cypher.read('secret/${password_secret}')%>"
internal_ip="<%= server.internalIp %>"

# ---- constants ------------------------------------------------------------
LOG=/tmp/morph_install_log.txt
WORKDIR=/var/tmp/morph_install
DEB="morpheus-appliance_$${morph_version}_amd64.deb"
DEB_URL="$download_base_url/$DEB"
MORPHEUS_RB=/etc/morpheus/morpheus.rb
UI_LOG=/var/log/morpheus/morpheus-ui/current
CURL_OPTS=(-k -sS --connect-timeout 10 --max-time 120)

# ---- helpers --------------------------------------------------------------
ts() { date '+%Y-%m-%d %H:%M:%S'; }
# Log to file and to the journal; the agent forwards the journal to the
# instance's Monitoring > Logs tab (tag: morph-install).
log() {
    echo "[$(ts)] $*" | tee -a "$LOG"
    logger -t morph-install -p user.info -- "$*" 2>/dev/null || true
}
warn() {
    echo "[$(ts)] WARNING: $*" | tee -a "$LOG"
    logger -t morph-install -p user.warning -- "WARNING: $*" 2>/dev/null || true
}
die() {
    echo "[$(ts)] ERROR: $*" | tee -a "$LOG"
    logger -t morph-install -p user.err -- "ERROR: $*" 2>/dev/null || true
    logger -t morph-install -p user.err -- "Installation FAILED. See $LOG on the VM." 2>/dev/null || true
    echo "[$(ts)] Installation FAILED. See $LOG on the VM." | tee -a "$LOG"
    exit 1
}

# json_body KEY=VALUE ... -> JSON object
json_body() {
    python3 - "$@" <<'PY'
import json, sys
print(json.dumps(dict(a.split("=", 1) for a in sys.argv[1:])))
PY
}

# json_get FILE a.b.c -> value or empty
json_get() {
    python3 - "$1" "$2" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    for k in sys.argv[2].split("."):
        d = d[k]
    print("" if d is None else d)
except Exception:
    print("")
PY
}

# api METHOD PATH [BODY] [TOKEN] -> sets API_CODE and API_BODY (file path)
API_BODY=$WORKDIR/last_response.json
API_CODE=""
api() {
    local method=$1 path=$2 body=$${3:-} token=$${4:-}
    local -a args=(-X "$method" "$app_url$path" -H "accept: application/json")
    [[ -n $body ]] && args+=(-H "Content-Type: application/json" -d "$body")
    [[ -n $token ]] && args+=(-H "Authorization: Bearer $token")
    API_CODE=$(curl "$${CURL_OPTS[@]}" "$${args[@]}" -o "$API_BODY" -w '%%{http_code}' 2>>"$LOG") || API_CODE="000"
}

wait_for_apt() {
    local waited=0
    while fuser /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock >/dev/null 2>&1; do
        (( waited % 60 == 0 )) && log "Waiting for apt/dpkg lock to be released..."
        sleep 5; (( waited += 5 ))
        (( waited >= 900 )) && die "apt/dpkg lock still held after 15 minutes"
    done
}

# ---- start ----------------------------------------------------------------
mkdir -p "$WORKDIR"
touch "$LOG"; chmod 600 "$LOG"
log "===== Morpheus $morph_version installer starting on $internal_ip ====="

[[ -n $internal_ip ]]  || die "server.internalIp is empty; cannot build the appliance URL"
[[ -n $password ]]     || die "password secret is empty"
command -v python3 >/dev/null || die "python3 is required but not installed"
[[ -z $licenseKey ]] && warn "No license key supplied; license activation will be skipped"

app_url="https://$internal_ip"

# ---- 1. keep apt out of the way -------------------------------------------
log "Disabling unattended upgrades and apt timers"
systemctl disable --now apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true
wait_for_apt
apt-get remove -y unattended-upgrades >>"$LOG" 2>&1 || warn "could not remove unattended-upgrades (continuing)"

# ---- 2. download + install package ----------------------------------------
installed_version=$(dpkg-query -W -f='$${Version}' morpheus-appliance 2>/dev/null || true)
if [[ $installed_version == "$morph_version" ]]; then
    log "morpheus-appliance $morph_version already installed, skipping download/install"
else
    log "Downloading $DEB_URL"
    curl -fL --retry 5 --retry-delay 15 --retry-connrefused -C - \
        --connect-timeout 20 -o "$WORKDIR/$DEB" "$DEB_URL" >>"$LOG" 2>&1 \
        || die "download failed: $DEB_URL"
    dpkg-deb --info "$WORKDIR/$DEB" >/dev/null 2>&1 || die "downloaded file is not a valid .deb (bad version or URL?)"

    log "Installing $DEB"
    wait_for_apt
    dpkg -i "$WORKDIR/$DEB" >>"$LOG" 2>&1 || die "dpkg -i failed"
    rm -f "$WORKDIR/$DEB"
fi

# ---- 3. appliance_url -> internal IP --------------------------------------
[[ -f $MORPHEUS_RB ]] || die "$MORPHEUS_RB not found after package install"
[[ -f $MORPHEUS_RB.orig ]] || cp "$MORPHEUS_RB" "$MORPHEUS_RB.orig"
if grep -qE "^\s*appliance_url\s" "$MORPHEUS_RB"; then
    sed -i -E "s|^\s*appliance_url\s.*|appliance_url '$app_url'|" "$MORPHEUS_RB"
else
    printf "\nappliance_url '%s'\n" "$app_url" >> "$MORPHEUS_RB"
fi
log "appliance_url set to $app_url"

# ---- 4. reconfigure --------------------------------------------------------
log "Running morpheus-ctl reconfigure (this takes a while)"
morpheus-ctl reconfigure >>"$LOG" 2>&1 || die "morpheus-ctl reconfigure failed"

# ---- 5. wait for the UI ----------------------------------------------------
log "Waiting up to $((ui_timeout / 60)) minutes for the UI at $app_url"
elapsed=0
setup_needed=""
while :; do
    api GET /api/setup/check
    if [[ $API_CODE == 200 ]]; then
        setup_needed=$(json_get "$API_BODY" setupNeeded)
        [[ -n $setup_needed ]] && break
    fi
    (( elapsed >= ui_timeout )) && {
        tail -n 50 "$UI_LOG" >>"$LOG" 2>/dev/null
        die "UI did not come up within $((ui_timeout / 60)) minutes (last HTTP code: $API_CODE)"
    }
    (( elapsed % 300 == 0 && elapsed > 0 )) && log "Still waiting for UI... $((elapsed / 60)) min elapsed (HTTP $API_CODE)"
    sleep 15; (( elapsed += 15 ))
done
log "UI is up after $elapsed seconds (setupNeeded=$setup_needed)"

# ---- 6. initial setup ------------------------------------------------------
if [[ $setup_needed == "True" ]]; then
    sleep 10
    body=$(json_body hubmode=skip "applianceName=$appliance_name" "applianceUrl=$app_url" \
        accountName=MasterTenant firstName=Morpheus lastName=Admin \
        "username=$username" email=noemail@morpheusdata.com "password=$password")
    api POST /api/setup "$body"
    if [[ $(json_get "$API_BODY" success) != "True" ]]; then
        die "appliance setup failed (HTTP $API_CODE): $(json_get "$API_BODY" msg)"
    fi
    log "Initial appliance setup completed"
else
    log "Appliance already set up, skipping /api/setup"
fi

# ---- 7. API token for the new appliance -----------------------------------
sleep 5
newAppAccessToken=$(curl "$${CURL_OPTS[@]}" -X POST \
    "$app_url/oauth/token?client_id=morph-api&grant_type=password&scope=write" \
    --data-urlencode "username=$username" --data-urlencode "password=$password" \
    -o "$API_BODY" 2>>"$LOG"; json_get "$API_BODY" access_token)
[[ -n $newAppAccessToken ]] || die "could not obtain an API token from the new appliance: $(json_get "$API_BODY" error_description)"
log "Obtained API token for $username"

# ---- 8. license ------------------------------------------------------------
if [[ -n $licenseKey ]]; then
    api POST /api/license "$(json_body "license=$licenseKey")" "$newAppAccessToken"
    if [[ $(json_get "$API_BODY" success) == "True" ]]; then
        log "License applied"
    else
        die "license activation failed (HTTP $API_CODE): $(json_get "$API_BODY" msg)"
    fi
fi

# ---- 9. post-setup settings (non-fatal) -----------------------------------
failures=0
body=$(python3 - "$cloud_init_username" "$password" <<'PY'
import json, sys
print(json.dumps({"provisioningSettings": {"cloudInitUsername": sys.argv[1], "cloudInitPassword": sys.argv[2]}}))
PY
)
api PUT /api/provisioning-settings "$body" "$newAppAccessToken"
if [[ $(json_get "$API_BODY" success) == "True" ]]; then
    log "Provisioning settings updated"
else
    warn "provisioning settings update failed (HTTP $API_CODE)"; (( failures++ ))
fi

body=$(python3 - "$username" "$password" <<'PY'
import json, sys
u, p = sys.argv[1], sys.argv[2]
print(json.dumps({"user": {"linuxUsername": u, "linuxPassword": p, "windowsUsername": u, "windowsPassword": p}}))
PY
)
api PUT /api/user-settings "$body" "$newAppAccessToken"
if [[ $(json_get "$API_BODY" success) == "True" ]]; then
    log "User settings updated"
else
    warn "user settings update failed (HTTP $API_CODE)"; (( failures++ ))
fi

# ---- done ------------------------------------------------------------------
rm -f "$API_BODY"
log "========================================"
log "Morpheus $morph_version installation completed"
log "Appliance URL: $app_url"
(( failures > 0 )) && log "$failures non-critical step(s) failed, see warnings above"
log "========================================"
echo "appliance_url=$app_url"
exit 0
