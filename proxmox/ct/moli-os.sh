#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/PrudhommeWTF/moli-os/main/proxmox"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: PrudhommeWTF
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/PrudhommeWTF/moli-os

APP="Moli-OS"
var_tags="${var_tags:-smarthome;home-automation}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_nesting="${var_nesting:-0}"
# Releases ship an aarch64 binary, but no arm64 container has run this script yet.
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -x /opt/moli-os/moli-os ]]; then
    msg_error "No Moli OS Installation Found!"
    exit
  fi

  if check_for_gh_release "moli-os" "PrudhommeWTF/moli-os"; then
    BACKUP_DIR="/var/backups/moli-os/$(date +%Y%m%d-%H%M%S)-$(cat ~/.moli-os)"
    msg_info "Backing up Moli OS data"
    $STD /usr/local/bin/moli-os backup "$BACKUP_DIR"
    msg_ok "Backed up Moli OS data to ${BACKUP_DIR}"

    msg_info "Stopping Moli OS"
    systemctl stop moli-os
    msg_ok "Stopped Moli OS"

    msg_info "Keeping the current Moli OS binary"
    cp -a /opt/moli-os/moli-os /opt/moli-os/moli-os.previous
    cp -a ~/.moli-os /opt/moli-os/moli-os.previous.version
    msg_ok "Kept the current Moli OS binary as /opt/moli-os/moli-os.previous"

    fetch_and_deploy_gh_release "moli-os" "PrudhommeWTF/moli-os" "prebuild" "latest" "/opt/moli-os" "moli-os-linux-$(arch_resolve "x86_64" "aarch64").tar.gz"

    msg_info "Starting Moli OS"
    # /api/health decides below: a start that fails must still lead to the way back.
    systemctl start moli-os || true
    for _ in {1..30}; do
      /opt/moli-os/moli-os health &>/dev/null && break
      sleep 1
    done
    if /opt/moli-os/moli-os health &>/dev/null; then
      msg_ok "Started Moli OS (/api/health answers)"
      msg_ok "Updated successfully!"
    else
      msg_error "Moli OS $(cat ~/.moli-os) does not answer /api/health: going back to the previous binary"
      systemctl stop moli-os
      cp -a /opt/moli-os/moli-os.previous /opt/moli-os/moli-os
      cp -a /opt/moli-os/moli-os.previous.version ~/.moli-os
      systemctl start moli-os || true
      msg_warn "Previous Moli OS binary restored ($(cat ~/.moli-os)); its logs: journalctl -u moli-os"
      msg_warn "Data as it was before the update: ${BACKUP_DIR} (moli-os restore ${BACKUP_DIR} --force, Moli OS stopped)"
      exit 1
    fi
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8790${CL}"
SETUP_CODE=$(pct exec "$CTID" -- sh -c "journalctl -u moli-os --no-pager -o cat | grep -o 'code=[A-Z0-9]*-[A-Z0-9]*' | tail -n 1 | cut -d= -f2" || true)
echo -e "${INFO}${YW}Setup code (valid one hour; a new one at every start until the house code is chosen):${CL}"
if [[ -n "$SETUP_CODE" ]]; then
  echo -e "${TAB}${BGN}${SETUP_CODE}${CL}"
else
  echo -e "${TAB}${BGN}pct exec ${CTID} -- sh -c 'journalctl -u moli-os | grep code='${CL}"
fi
