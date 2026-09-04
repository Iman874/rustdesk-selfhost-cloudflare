# How to Run RustDesk Client

Panduan khusus **client Windows** — 2 mode, pilih salah satu.

## Mode A — VPS Direct (REKOMENDASI, tanpa Cloudflare)

Pakai jika server di **VPS dengan IP publik** (hasil `deploy_remote_server.sh`).

1. Install RustDesk `rustdesk-1.4.9-x86_64.exe` (double-click)
2. Settings > Network > Unlock:
   - **ID Server:** `IP_VPS` atau `rustdesk.example.com` (contoh `203.0.113.10`, atau `10.190.229.160` jika via ZeroTier)
   - **Relay Server:** kosongkan (auto) atau isi sama
   - **Key:** paste `id_ed25519.pub` dari VPS (`cat ./data/id_ed25519.pub`)
3. Save > `Ready` hijau > konek via ID.

> Tidak perlu `cloudflared`, tidak perlu `client.bat`. Ini mode VPS kamu sekarang.

## Mode B — Cloudflare Tunnel TCP (untuk client di balik CGNAT / tanpa IP publik di server rumah)

Pakai jika **server di rumah/laptop** (`10.217.211.167`) tanpa IP publik dan mau diakses dari internet via Tunnel. VPS tidak butuh ini.

### Konsep
- Server rumah jalankan `cloudflared tunnel --url tcp://localhost:21116` (3 port: 21115,21116,21117) dengan 3 hostname.
- Client jalankan `cloudflared access tcp --hostname <host> --url localhost:<port>` lalu RustDesk arahkan ke `127.0.0.1`.

### Server (rumah) — sekali setup
```powershell
# di VPS/rumah, edit config/cloudflared/config.tcp.yml lalu:
cloudflared tunnel login
cloudflared tunnel create rustdesk-tcp
cloudflared tunnel route dns rustdesk-tcp id.rustdesk.example.com
cloudflared tunnel route dns rustdesk-tcp relay.rustdesk.example.com
cloudflared tunnel route dns rustdesk-tcp nattest.rustdesk.example.com
cloudflared tunnel run rustdesk-tcp
```

### Client — auto via `client.bat`
1. Edit `client.bat` ganti:
   ```bat
   set ID_HOST=id.rustdesk.example.com
   set RELAY_HOST=relay.rustdesk.example.com
   set NATTEST_HOST=nattest.rustdesk.example.com
   ```
2. Double-click `client.bat` (Run as Administrator jika gagal download)
   - Auto download `cloudflared-windows-amd64.exe` ke folder ini jika belum ada
   - Auto jalankan 3 tunnel `access tcp` di background:
     - `id.rustdesk.example.com` -> `localhost:21116`
     - `relay.rustdesk.example.com` -> `localhost:21117`
     - `nattest.rustdesk.example.com` -> `localhost:21115`
3. Setelah `client.bat` bilang `Tunnel OK`, buka RustDesk:
   - **ID Server:** `127.0.0.1`
   - **Relay Server:** `127.0.0.1`
   - **Key:** sama (`OEDJtHbIM6eClqaynnCz5OEPSCJq2Jjko51Yr1I8DRE=` untuk test lokal)
4. Jangan tutup window `client.bat` selama pakai RustDesk. Tutup window = tunnel mati.

### Catatan
- Mode B butuh **3 hostname Cloudflare** (satu per port) + `cloudflared` di **tiap client**.
- Jika VPS sudah ada IP publik, **jangan pakai Mode B** — langsung Mode A lebih cepat & stabil.
- `client.bat` sudah handle download & run, cukup edit 3 baris host.
