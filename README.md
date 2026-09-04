# RustDesk Self-Host + Cloudflare Tunnel

Self-host RustDesk Server OSS (hbbs + hbbr) dengan opsi Cloudflare Tunnel untuk Web Client. Repo ini siap push ke GitHub dan deploy di VPS Linux (recommended) atau test lokal Windows.

> Client kamu: `rustdesk-1.4.9-x86_64.exe` (kompatibel dengan server OSS 1.1.16/latest).

## Kenapa tidak full Tunnel?

- **Native RustDesk** butuh TCP `21115-21117` + UDP `21116` raw. Cloudflare Tunnel gratis (HTTP/HTTPS) **tidak proxy TCP/UDP raw** kecuali Spectrum Enterprise [community.cloudflare.com].
- `cloudflared tunnel tcp://` bisa, tapi **tiap client harus install `cloudflared access tcp`** — tidak praktis untuk RustDesk native.
- **Yang bisa via Tunnel gratis:** Web Client `wss://domain/ws/id` (21118) dan `wss://domain/ws/relay` (21119). Jadi hybrid: native direct, web via tunnel.

## Struktur

```
.
├── deploy_remote_server.sh         # ONE-CLICK VPS deploy (chmod +x && sudo ./deploy_remote_server.sh)
├── docker-compose.yml              # VPS Linux host mode (REKOMENDASI)
├── docker-compose.ports.yml        # Windows / tanpa host mode
├── docker-compose.s6.yml           # Single container s6
├── config/cloudflared/config.yml   # Tunnel hanya untuk 21118/21119
├── data/                           # volume hbbs/hbbr (jangan commit key!)
├── scripts/get-key.ps1             # ambil public key (Windows)
└── scripts/get-key.sh              # ambil public key (Linux)
```

## Quick Start - VPS Linux (Ubuntu/Debian) - ONE CLICK

```bash
git clone https://github.com/<user>/rustdesk-selfhost-cloudflare.git
cd rustdesk-selfhost-cloudflare
chmod +x deploy_remote_server.sh
sudo ./deploy_remote_server.sh              # auto-detect IP
# atau: sudo ./deploy_remote_server.sh rustdesk.example.com
# atau: sudo ./deploy_remote_server.sh --with-tunnel rustdesk.example.com

# script akan: install docker, setup ufw, pull & up hbbs/hbbr, print Key
cat ./data/id_ed25519.pub
```

Manual (tanpa script):
```bash
docker compose up -d
docker compose logs -f hbbs  # tunggu `Key: xxxx` muncul
cat ./data/id_ed25519.pub
sudo ufw allow 21115/tcp; sudo ufw allow 21116/tcp; sudo ufw allow 21116/udp; sudo ufw allow 21117/tcp; sudo ufw enable
ss -tulpn | grep 2111  # harus ada 21115,21116 tcp + 21116 udp + 21117
```

## Quick Start - Windows (test lokal)

```powershell
# ganti rustdesk.example.com di docker-compose.ports.yml dengan IP lokal / domain kamu
docker compose -f docker-compose.ports.yml up -d
docker compose -f docker-compose.ports.yml logs hbbs
.\scripts\get-key.ps1
```

## Konfigurasi Client (WAJIB di kedua sisi)

1. Buka `rustdesk-1.4.9-x86_64.exe` > Settings (ikon titik tiga) > Network > **Unlock** (jika minta admin)
2. Isi:
   - **ID Server:** `rustdesk.example.com` atau `IP_VPS` (contoh `203.0.113.10`)
   - **Relay Server:** kosongkan jika `hbbr` 1 mesin dengan `hbbs`, atau isi sama dengan ID Server
   - **API Server:** kosongkan (OSS tidak ada)
   - **Key:** paste isi `id_ed25519.pub` (satu baris base64, tanpa spasi)
3. Save, status harus jadi `Ready` hijau. Test konek beda jaringan (jangan cuma 1 LAN).

> Jika `hbbr` pakai `-k _` (sudah di compose), hanya client dengan Key yang bisa relay — cegah pemakaian liar [ssdnodes.com].

## Cloudflare Tunnel (opsional, untuk Web Client)

Hanya jika mau akses via browser `https://rustdesk.example.com`:

```bash
# di VPS
cloudflared tunnel login
cloudflared tunnel create rustdesk-tunnel
# cat ~/.cloudflared/*.json -> ambil TUNNEL_ID, isi di config/cloudflared/config.yml
cloudflared tunnel route dns rustdesk-tunnel rustdesk.example.com
cloudflared tunnel route dns rustdesk-tunnel relay.rustdesk.example.com

# jalankan
cloudflared tunnel run rustdesk-tunnel
# atau via docker:
# docker run -d --network host -v ./config/cloudflared:/etc/cloudflared cloudflare/cloudflared tunnel run
```

`config/cloudflared/config.yml` sudah mapping `rustdesk.example.com -> localhost:21118` dan `relay... -> 21119`.

## Upgrade & Backup

```bash
# backup key (PENTING: hilang = semua client harus ganti Key)
tar czf ~/rustdesk-data-backup.tgz -C . data

# upgrade (pin versi di compose jika mau)
docker compose pull
docker compose up -d
cat ./data/id_ed25519.pub  # pastikan tidak berubah
```

## Troubleshooting

| Gejala | Cek |
|---|---|
| Client `Not ready` | UDP 21116 terblokir, DNS salah, Key tidak sama, `docker logs hbbs` |
| Bisa register tapi tidak konek | 21115/21117 terblokir, firewall provider, `docker logs hbbr` |
| Work di HP tapi tidak di LAN sama | Router tidak support hairpin NAT — pakai hosts file atau split DNS |
| `hbbs` restart loop | `ss -tulpn | grep 2111` cek port bentrok |

## Referensi

- https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/docker/
- https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/install/
- https://github.com/rustdesk/rustdesk-server
- https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/
