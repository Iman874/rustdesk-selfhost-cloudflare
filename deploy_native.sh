#!/bin/bash
# deploy_native.sh - Native systemd deploy RustDesk Server OSS (tanpa Docker)
# Pola Monoframe backend: systemd + /opt/rustdesk (mirip php8.3-fpm)
# Usage: sudo ./deploy_native.sh [relay-host]
#   relay-host: IP/domain VPS (default: auto-detect, contoh 203.194.115.85)
set -e
RELAY_HOST="${1:-}"
GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; NC="\033[0m"
if [[ $EUID -ne 0 ]]; then echo -e "${RED}Harus root: sudo ./deploy_native.sh${NC}"; exit 1; fi
if [[ -z "$RELAY_HOST" ]]; then RELAY_HOST=$(curl -4 -s ifconfig.me || hostname -I | awk '{print $1}' || echo "YOUR_VPS_IP"); fi
echo -e "${GREEN}=== RustDesk Native Deploy (systemd) ===${NC}"
echo -e "RELAY_HOST: ${YELLOW}$RELAY_HOST${NC}"

# 1. Stop docker version jika ada (hindari port bentrok)
if command -v docker &> /dev/null; then
  echo -e "${YELLOW}[1/7] Stop Docker rustdesk jika ada...${NC}"
  docker compose -f /var/www/rustdesk/docker-compose.yml down 2>/dev/null || true
  docker compose -f /var/www/rustdesk/docker-compose.ports.yml down 2>/dev/null || true
  docker compose -f /var/www/rustdesk/docker-compose.s6.yml down 2>/dev/null || true
fi

# 2. Install deps
echo -e "${YELLOW}[2/7] Install deps...${NC}"
apt-get update -y
apt-get install -y curl wget unzip ufw

# 3. Buat user & dir
id -u rustdesk &>/dev/null || useradd -r -m -d /opt/rustdesk -s /bin/false rustdesk
mkdir -p /opt/rustdesk
chown rustdesk:rustdesk /opt/rustdesk

# 4. Download rustdesk-server (pin 1.1.16 stabil 2026-08, ganti latest jika mau)
RDVER="${RDVER:-1.1.16}"
RDARCH="amd64"
if [[ $(uname -m) == "aarch64" ]]; then RDARCH="arm64v8"; fi
echo -e "${YELLOW}[3/7] Download rustdesk-server $RDVER ($RDARCH)...${NC}"
cd /tmp
wget -q "https://github.com/rustdesk/rustdesk-server/releases/download/${RDVER}/rustdesk-server-linux-${RDARCH}.zip" -O rustdesk-server.zip || \
wget -q "https://github.com/rustdesk/rustdesk-server/releases/latest/download/rustdesk-server-linux-${RDARCH}.zip" -O rustdesk-server.zip
rm -rf rustdesk-server && mkdir rustdesk-server && unzip -o -j rustdesk-server.zip '*/hbbs' '*/hbbr' -d rustdesk-server || unzip -o -j rustdesk-server.zip -d rustdesk-server
install -o rustdesk -g rustdesk -m 0755 rustdesk-server/hbbs rustdesk-server/hbbr /opt/rustdesk/
ls -lh /opt/rustdesk/hbbs /opt/rustdesk/hbbr

# 5. Systemd units (pola backend_photobox: /etc/systemd/system/*.service)
echo -e "${YELLOW}[4/7] Buat systemd units...${NC}"
cat > /etc/systemd/system/rustdesk-hbbr.service <<EOF
[Unit]
Description=RustDesk Relay Server (hbbr)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=rustdesk
Group=rustdesk
WorkingDirectory=/opt/rustdesk
ExecStart=/opt/rustdesk/hbbr -k _
Restart=on-failure
RestartSec=5s
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/rustdesk-hbbs.service <<EOF
[Unit]
Description=RustDesk ID/Rendezvous Server (hbbs)
After=network-online.target rustdesk-hbbr.service
Wants=network-online.target
Requires=rustdesk-hbbr.service

[Service]
Type=simple
User=rustdesk
Group=rustdesk
WorkingDirectory=/opt/rustdesk
ExecStart=/opt/rustdesk/hbbs -r ${RELAY_HOST}:21117 -k _
Restart=on-failure
RestartSec=5s
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now rustdesk-hbbr
systemctl enable --now rustdesk-hbbs
sleep 3
systemctl status rustdesk-hbbs --no-pager | head -20
systemctl status rustdesk-hbbr --no-pager | head -20

# 6. Firewall (pola backend GOTCHA #5)
echo -e "${YELLOW}[5/7] Setup UFW...${NC}"
ufw allow 22/tcp || true
ufw allow 21115/tcp || true
ufw allow 21116/tcp || true
ufw allow 21116/udp || true
ufw allow 21117/tcp || true
ufw --force enable || true
ufw status numbered || true

# 7. Tunggu key (hbbs generate di /opt/rustdesk/id_ed25519.pub)
echo -e "${YELLOW}[6/7] Menunggu key...${NC}"
for i in {1..15}; do [[ -f /opt/rustdesk/id_ed25519.pub ]] && break; sleep 1; done
if [[ ! -f /opt/rustdesk/id_ed25519.pub ]]; then echo -e "${RED}Key belum ada, cek journalctl -u rustdesk-hbbs${NC}"; exit 1; fi
PUB_KEY=$(cat /opt/rustdesk/id_ed25519.pub)
echo -e "${GREEN}=== KEY BERHASIL ===${NC}"
echo -e "${YELLOW}$PUB_KEY${NC}"
chown rustdesk:rustdesk /opt/rustdesk/id_ed25519*

# 8. Verifikasi (pola how_to_deploy backend)
echo -e "${YELLOW}[7/7] Verifikasi...${NC}"
ss -tulpn | grep 2111 || netstat -tulpn | grep 2111 || true
journalctl -u rustdesk-hbbs --no-pager -n 20 | grep -i "Listening\|Key" || true
echo ""
echo -e "${GREEN}=== NATIVE DEPLOY SELESAI ===${NC}"
echo -e "ID Server : ${YELLOW}$RELAY_HOST${NC}"
echo -e "Key       : ${YELLOW}$PUB_KEY${NC}"
echo -e "Cek       : journalctl -u rustdesk-hbbs -f ; journalctl -u rustdesk-hbbr -f"
echo -e "Restart   : systemctl restart rustdesk-hbbs rustdesk-hbbr"
echo -e "Update    : cd /var/www/rustdesk && git pull && sudo ./deploy_native.sh $RELAY_HOST"
echo ""
echo -e "Client: RustDesk > Settings > Network > ID Server = $RELAY_HOST , Key = $PUB_KEY"
