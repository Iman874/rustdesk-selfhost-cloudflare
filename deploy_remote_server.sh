#!/bin/bash
# deploy_remote_server.sh - One-click deploy RustDesk Server OSS (hbbs/hbbr) di VPS Linux Ubuntu/Debian
# Pola Monoframe backend: /var/www/monobox/backend (VPS 203.194.115.85 Ubuntu 24.04)
# Usage: chmod +x deploy_remote_server.sh && sudo ./deploy_remote_server.sh [relay-host]
#   relay-host: domain/IP VPS (default: auto-detect public IP, contoh 203.194.115.85)
#   --with-tunnel: juga setup Cloudflare Tunnel untuk 21118/21119 (butuh cloudflared login manual)
# Lihat how_to_deploy.md untuk GOTCHA & verifikasi (wajib baca sebelum deploy)

set -e
RELAY_HOST="${1:-}"
WITH_TUNNEL=false
if [[ "$1" == "--with-tunnel" ]]; then WITH_TUNNEL=true; RELAY_HOST="${2:-}"; fi
if [[ "$2" == "--with-tunnel" ]]; then WITH_TUNNEL=true; fi

GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; NC="\033[0m"

if [[ $EUID -ne 0 ]]; then echo -e "${RED}Harus run sebagai root: sudo ./deploy_remote_server.sh${NC}"; exit 1; fi

echo -e "${GREEN}=== RustDesk Self-Host Deploy (VPS Linux) ===${NC}"

# 1. Detect RELAY_HOST
if [[ -z "$RELAY_HOST" || "$RELAY_HOST" == "--with-tunnel" ]]; then
  RELAY_HOST=$(curl -4 -s ifconfig.me || curl -s ipinfo.io/ip || hostname -I | awk '{print $1}' || echo "YOUR_VPS_IP")
fi
echo -e "RELAY_HOST: ${YELLOW}$RELAY_HOST${NC}"

# 2. Install Docker if needed
if ! command -v docker &> /dev/null; then
  echo -e "${YELLOW}[1/6] Install Docker...${NC}"
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || true
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || true
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null || \
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || apt-get install -y docker.io docker-compose-plugin
  systemctl enable --now docker
else
  echo -e "${GREEN}Docker sudah terinstall: $(docker --version)${NC}"
fi
docker compose version || echo "docker compose plugin missing!"

# 3. Prepare directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
mkdir -p data db config/cloudflared
echo -e "${GREEN}[2/6] Direktori siap: $SCRIPT_DIR${NC}"

# 4. Firewall UFW
if command -v ufw &> /dev/null; then
  echo -e "${YELLOW}[3/6] Setup UFW...${NC}"
  ufw allow 22/tcp || true
  ufw allow 21115/tcp || true
  ufw allow 21116/tcp || true
  ufw allow 21116/udp || true
  ufw allow 21117/tcp || true
  ufw --force enable || true
  ufw status numbered || true
else
  echo -e "${YELLOW}UFW tidak ada, skip (pastikan firewall provider allow 21115-21117)${NC}"
  apt-get install -y ufw && ufw allow 22/tcp && ufw allow 21115/tcp && ufw allow 21116/tcp && ufw allow 21116/udp && ufw allow 21117/tcp && ufw --force enable || true
fi

# 5. Compose file
if [[ -f docker-compose.yml ]]; then
  echo -e "${GREEN}Menggunakan docker-compose.yml (host mode)${NC}"
  COMPOSE_FILE="docker-compose.yml"
elif [[ -f docker-compose.s6.yml ]]; then
  COMPOSE_FILE="docker-compose.s6.yml"
else
  echo -e "${RED}docker-compose.yml tidak ditemukan di $SCRIPT_DIR${NC}"; exit 1
fi

# 6. Pull & Up
echo -e "${YELLOW}[4/6] Pull & Start hbbs/hbbr...${NC}"
docker compose -f "$COMPOSE_FILE" pull || true
docker compose -f "$COMPOSE_FILE" up -d
sleep 5
docker compose -f "$COMPOSE_FILE" ps
docker compose -f "$COMPOSE_FILE" logs --tail 50 hbbs || true

# 7. Wait for key
echo -e "${YELLOW}[5/6] Menunggu key...${NC}"
for i in {1..30}; do
  if [[ -f data/id_ed25519.pub ]]; then break; fi
  if [[ -f data/data/id_ed25519.pub ]]; then break; fi
  sleep 1
done
KEY_FILE=""
if [[ -f data/id_ed25519.pub ]]; then KEY_FILE="data/id_ed25519.pub"
elif [[ -f data/data/id_ed25519.pub ]]; then KEY_FILE="data/data/id_ed25519.pub"
fi
if [[ -z "$KEY_FILE" ]]; then
  echo -e "${RED}Key belum ter-generate, cek: docker compose logs hbbs${NC}"
  exit 1
fi
PUB_KEY=$(cat "$KEY_FILE")
echo -e "${GREEN}=== KEY BERHASIL ===${NC}"
echo -e "${YELLOW}$PUB_KEY${NC}"
echo ""

# 8. Optional Tunnel
if [[ "$WITH_TUNNEL" == "true" ]]; then
  echo -e "${YELLOW}[6/6] Setup Cloudflare Tunnel (web 21118/21119)...${NC}"
  if ! command -v cloudflared &> /dev/null; then
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
  fi
  echo "cloudflared: $(cloudflared --version || echo installed)"
  echo "Jalankan manual: cloudflared tunnel login && cloudflared tunnel create rustdesk-tunnel"
  echo "Edit config/cloudflared/config.yml ganti TUNNEL_ID lalu: docker compose -f docker-compose.yml -f docker-compose.tunnel.yml up -d"
else
  echo -e "${GREEN}[6/6] Skip Tunnel (native only)${NC}"
fi

# 9. Summary
echo -e "${GREEN}=== DEPLOY SELESAI ===${NC}"
echo -e "ID Server  : ${YELLOW}$RELAY_HOST${NC}"
echo -e "Relay      : ${YELLOW}$RELAY_HOST:21117${NC} (kosongkan di client jika 1 VPS)"
echo -e "Key        : ${YELLOW}$PUB_KEY${NC}"
echo -e "Ports      : 21115/tcp, 21116 tcp/udp, 21117/tcp (wajib open di firewall provider)"
echo -e "Cek        : docker compose logs -f hbbs ; docker compose logs -f hbbr"
echo -e "Backup     : tar czf ~/rustdesk-data-backup.tgz -C $SCRIPT_DIR data"
echo ""
echo -e "${GREEN}Config Client RustDesk:${NC}"
echo -e "  RustDesk > Settings > Network > ID Server = $RELAY_HOST"
echo -e "  Relay Server = (kosong) atau $RELAY_HOST"
echo -e "  Key = $PUB_KEY"
echo ""
echo -e "${YELLOW}Test: dari device lain set ID Server sama, pastikan Ready hijau lalu konek via ID${NC}"
