# Ambil public key untuk ditempel di RustDesk client > Settings > Network > Key
# Jalankan setelah `docker compose up -d` pertama kali

Write-Host "=== RustDesk Key ===" -ForegroundColor Cyan
if (Test-Path ".\data\id_ed25519.pub") {
    Get-Content ".\data\id_ed25519.pub"
    Write-Host "`nCopy string di atas ke: RustDesk > Settings > Network > ID/Relay Server > Key" -ForegroundColor Green
    Write-Host "ID Server: rustdesk.example.com (ganti dengan domain/IP kamu)" -ForegroundColor Yellow
} elseif (Test-Path ".\data\data\id_ed25519.pub") {
    # s6 variant
    Get-Content ".\data\data\id_ed25519.pub"
} else {
    Write-Host "Key belum ada. Pastikan container sudah run: docker compose up -d; docker compose logs hbbs" -ForegroundColor Red
}
