@echo off
REM deploy.bat - One-click deploy dari Windows dev ke VPS (pola ai_service/deploy.bat)
REM Prasyarat: ssh key root@203.194.115.85 sudah terpasang (ssh root@203.194.115.85 tanpa password)

set VPS=root@203.194.115.85
set REMOTE_DIR=/var/www/rustdesk
set BRANCH=main

echo === Deploy RustDesk ke %VPS%:%REMOTE_DIR% ===
echo [1/3] Git push lokal...
git push origin %BRANCH%
if errorlevel 1 (
  echo Git push gagal, lanjut scp manual...
)

echo [2/3] Sync file ke VPS via scp...
scp -r docker-compose.yml docker-compose.ports.yml docker-compose.s6.yml deploy_remote_server.sh config data/.gitkeep "%VPS%:%REMOTE_DIR%/" 2>nul
REM Jika scp -r folder gagal, pakai git pull di VPS saja
echo [3/3] Remote pull + deploy...
ssh %VPS% "cd %REMOTE_DIR% && git pull origin %BRANCH% && chmod +x deploy_remote_server.sh && sudo ./deploy_remote_server.sh && echo '--- KEY ---' && cat ./data/id_ed25519.pub"

echo Deploy selesai. Cek VPS: ssh %VPS% "cd %REMOTE_DIR% && docker compose logs --tail 20 hbbs"
pause
