#!/bin/bash
# Linux/macOS: ambil public key
set -e
if [ -f ./data/id_ed25519.pub ]; then
  cat ./data/id_ed25519.pub
  echo ""
  echo "Copy string di atas ke: RustDesk > Settings > Network > Key"
elif [ -f ./data/data/id_ed25519.pub ]; then
  cat ./data/data/id_ed25519.pub
else
  echo "Key belum ada. Jalankan: docker compose up -d && docker compose logs hbbs"
  exit 1
fi
