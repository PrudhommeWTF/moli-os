#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: PrudhommeWTF
# License: MIT | https://github.com/community-scripts/DevScripts/raw/main/LICENSE
# Source: https://github.com/PrudhommeWTF/moli-os

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

fetch_and_deploy_gh_release "moli-os" "PrudhommeWTF/moli-os" "prebuild" "latest" "/opt/moli-os" "moli-os-linux-$(arch_resolve "x86_64" "aarch64").tar.gz"

msg_info "Configuring Moli OS"
useradd --system --user-group --home-dir /var/lib/moli-os --shell /usr/sbin/nologin moli
install -d -o moli -g moli -m 0750 /var/lib/moli-os /var/backups/moli-os
install -d -o root -g moli -m 0750 /etc/moli-os
# The vault's key, outside the data directory so `moli-os backup` never holds it.
# Created once: a new key on an existing house would make its vault unreadable.
if [[ ! -s /etc/moli-os/master.key ]]; then
  (umask 077 && openssl rand -hex 32 >/etc/moli-os/master.key)
fi
chown moli:moli /etc/moli-os/master.key
chmod 0600 /etc/moli-os/master.key
cat <<EOF >/var/lib/moli-os/moli.toml
# Moli OS: this house's configuration. No secret here, ever: they go into the
# encrypted vault (moli-os secrets set). Full example: /opt/moli-os/moli.example.toml
# Guide: https://github.com/PrudhommeWTF/moli-os/blob/main/docs/components/installation.md

[server]
listen = "0.0.0.0:8790"
data_dir = "/var/lib/moli-os"
# Names and addresses Moli is reached by (DNS-rebinding guard); an IP address
# typed as is always works.
allowed_hosts = ["${LOCAL_IP}"]

# Devices: one [[driver]] block per integration, then systemctl restart moli-os.
EOF
chown moli:moli /var/lib/moli-os/moli.toml
chmod 0640 /var/lib/moli-os/moli.toml
# From a root shell, every moli-os command runs as the service user with the
# service's configuration and key: no file of the house becomes root's.
cat <<'EOF' >/usr/local/bin/moli-os
#!/bin/sh
export MOLI_CONFIG=/var/lib/moli-os/moli.toml
export MOLI_MASTER_KEY_FILE=/etc/moli-os/master.key
if [ "$(id -u)" -eq 0 ]; then
  exec runuser -u moli -- /opt/moli-os/moli-os "$@"
fi
exec /opt/moli-os/moli-os "$@"
EOF
chmod 0755 /usr/local/bin/moli-os
msg_ok "Configured Moli OS"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/moli-os.service
[Unit]
Description=Moli OS
Documentation=https://github.com/PrudhommeWTF/moli-os
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=moli
Group=moli
WorkingDirectory=/var/lib/moli-os
Environment=MOLI_CONFIG=/var/lib/moli-os/moli.toml
Environment=MOLI_MASTER_KEY_FILE=/etc/moli-os/master.key
Environment=RUST_LOG=info,rumqttc=warn,rmcp=warn
Environment=NO_COLOR=1
ExecStart=/opt/moli-os/moli-os serve
Restart=always
RestartSec=5
TimeoutStopSec=20
MemoryMax=128M
MemorySwapMax=0
NoNewPrivileges=yes
UMask=0027

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now moli-os
msg_ok "Created Service"

cat <<'EOF' >/etc/profile.d/moli-os.sh
echo -e "  Moli OS: http://$(hostname -I | awk '{print $1}'):8790"
echo -e "  Setup code (first start, valid one hour): journalctl -u moli-os | grep code="
echo -e "  Master key: /etc/moli-os/master.key (keep a copy in a password manager)"
echo ""
EOF

motd_ssh
customize
cleanup_lxc
