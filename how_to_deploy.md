# How To Deploy — RustDesk Self-Host (hbbs/hbbr Docker)

Panduan deploy production RustDesk Server OSS ke VPS. Dokumen ini mengikuti pola **Monoframe backend** (`backend_photobox/backend_app/how_to_deploy.md`) — semua gotcha lapangan ditulis agar tidak terulang.

---

## 1. Informasi VPS & Path

| Item | Nilai | Keterangan |
|------|-------|------------|
| IP VPS | `203.194.115.85` | IP public VPS produksi (sama dengan Monoframe backend) |
| OS | Ubuntu 24.04 LTS | `Ubuntu 24.04 LTS` |
| Akses | `ssh root@203.194.115.85` | Akses terminal VPS |
| App root (git repo) | `/var/www/rustdesk` | Branch `main` (repo `Iman874/rustdesk-selfhost-cloudflare`, private) |
| Data dir (key) | `/var/www/rustdesk/data` | Volume `./data:/root` — berisi `id_ed25519` + `id_ed25519.pub` + `db_v2.sqlite3` |
| Compose | `/var/www/rustdesk/docker-compose.yml` | `network_mode: host` (REKOMENDASI, Linux only) |
| Compose Windows | `docker-compose.ports.yml` | Hanya untuk test lokal Windows (tanpa host mode) |
| Env produksi | tidak ada `.env` | Key di-generate otomatis `hbbs` di `data/` (gitignored, jangan commit) |
| Nginx site | tidak pakai Nginx | RustDesk langsung `21115-21117` TCP/UDP, bukan HTTP — jangan buat site baru |
| Ports wajib | `21115/tcp, 21116/tcp+udp, 21117/tcp` | `21118/21119` hanya untuk web client (opsional) |

> **JANGAN** buat block Nginx baru untuk RustDesk — RustDesk bukan HTTP. Nginx hanya dipakai jika mau proxy web client `wss://` (lihat `config/cloudflared/config.yml`).

---

## 2. Alur Deploy Standar (VPS)

```bash
ssh root@203.194.115.85
cd /var/www/rustdesk

# 1. Pull kode terbaru (pola Monoframe: git pull origin <branch>)
git pull origin main

# 2. One-click deploy (install docker jika belum, setup ufw, pull & up)
chmod +x deploy_remote_server.sh
sudo ./deploy_remote_server.sh
# atau dengan domain: sudo ./deploy_remote_server.sh rustdesk.example.com

# 3. Ambil Key (WAJIB untuk semua client)
cat ./data/id_ed25519.pub
# contoh: OEDJtHbIM6eClqaynnCz5OEPSCJq2Jjko51Yr1I8DRE=

# 4. Cek listen
ss -tulpn | grep 2111
# harus: 21115 tcp, 21116 tcp + udp, 21117 tcp (plus 21118/21119 jika web)

# 5. Cek logs
docker compose logs --tail 50 hbbs
docker compose logs --tail 50 hbbr
```

**Deploy dari Windows dev (one-click, pola ai_service `deploy.bat`):**
```cmd
cd rustdesk-selfhost-cloudflare
deploy.bat
```
Isi `deploy.bat`:
```bat
scp -r . root@203.194.115.85:/var/www/rustdesk
ssh root@203.194.115.85 "cd /var/www/rustdesk && git pull origin main && ./deploy_remote_server.sh"
```

---

## 3. ⚠️ GOTCHA Produksi (WAJIB DIBACA)

Semua error di bawah pernah terjadi di lapangan dan bikin client `Not ready` / `relay fail`.

### GOTCHA #1 — UDP 21116 wajib, bukan hanya TCP

`hbbs` butuh **UDP 21116** untuk ID registration & heartbeat. Banyak yang hanya buka TCP.

**Symptom:** client `Not ready`, log `hbbs` tidak ada `Listening on tcp/udp :21116`, `docker logs hbbs` sepi.

**Fix:**
```bash
ufw allow 21116/udp
ufw allow 21116/tcp
# provider firewall (Vultr/AWS SG) juga buka UDP 21116
```

### GOTCHA #2 — `hbbr -k _` wajib, default relay terbuka untuk umum

Default `hbbr` tanpa `-k` memperbolehkan **siapa saja** pakai relay kamu (habiskan bandwidth).

**Symptom:** tidak ada error, tapi bandwidth VPS jebol dipakai orang lain.

**Fix:** compose sudah pakai `command: hbbr -k _` (load key dari `./data` yang sama dengan `hbbs`). Jangan hapus `-k _`.

### GOTCHA #3 — `network_mode: host` hanya Linux

Di VPS Linux `host` mode paling stabil (lihat `docker-compose.yml`). Di Windows/Docker Desktop `host` tidak jalan.

**Symptom di Windows:** `docker compose up` error `network_mode host not supported`.

**Fix:** Windows pakai `docker-compose.ports.yml` (ports mapping) atau `docker-compose.s6.yml` single container.

### GOTCHA #4 — Key hilang = semua client harus ganti Key

`id_ed25519` (private) di `data/` adalah identitas server. Hilang/rusak = `id_ed25519.pub` ganti = semua RustDesk client harus paste Key baru.

**Fix (backup sekali setelah deploy):**
```bash
tar czf ~/rustdesk-data-backup.tgz -C /var/www/rustdesk data
# simpan di luar VPS juga
```

### GOTCHA #5 — Firewall provider (bukan hanya UFW)

UFW `allow` belum cukup jika provider punya firewall/SG terpisah.

**Symptom:** lokal `ss -tulpn` LISTENING tapi dari internet `telnet IP 21116` timeout.

**Fix:** buka juga di panel provider: `21115/tcp, 21116 tcp+udp, 21117/tcp`.

### GOTCHA #6 — Hairpin NAT (work di HP tapi tidak di LAN sama)

Router rumah tidak support hairpin — device 1 LAN tidak bisa konek via IP publik.

**Symptom:** test via 4G/HP bisa, 1 WiFi tidak.

**Fix:** pakai ZeroTier (`10.190.229.160`) atau hosts file `rustdesk.example.com -> 10.217.211.167`.

---

## 4. Verifikasi Setelah Deploy

```bash
# Health ports (harus LISTEN)
ss -tulpn | grep 2111
# atau
netstat -ano | findstr 2111  # Windows

# Logs
docker compose logs --tail 30 hbbs | grep -i "Listening\|Key"
docker compose logs --tail 30 hbbr | grep -i "Listening\|Key"

# Test dari client lain (WAJIB beda jaringan, bukan 1 LAN)
# RustDesk > Settings > Network > ID Server = 203.194.115.85 (atau domain) + Key = cat ./data/id_ed25519.pub
# Harus Ready hijau, lalu konek via ID. Cek relay:
docker compose logs hbbr --tail 20 | grep -i "relay\|handshake"
```

---

## 5. Troubleshooting Cepat

| Symptom | Kemungkinan | Cek / Fix |
|---------|-------------|-----------|
| `Not ready` | UDP 21116 terblokir / Key salah | `ufw status`, `cat data/id_ed25519.pub` sama dengan client, `docker logs hbbs` |
| `Relay fail` | 21117 terblokir / `-k _` mismatch | `ufw allow 21117/tcp`, pastikan `hbbr -k _`, `docker logs hbbr` |
| `hbbs` restart loop | port bentrok | `ss -tulpn \| grep 2111` cek konflik, `docker compose down && up -d` |
| Key berubah setelah upgrade | `data/` terhapus | restore `~/rustdesk-data-backup.tgz`, pin image tag `1.1.16` bukan `latest` |
| Web client `wss://` fail | `21118/21119` tidak di-proxy | pakai `config/cloudflared/config.yml` atau buka `21118/21119` langsung |

Log: `docker compose logs -f hbbs` dan `docker compose logs -f hbbr`
Backup: `tar czf ~/rustdesk-data-backup.tgz -C /var/www/rustdesk data`
