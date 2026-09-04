@echo off
setlocal enabledelayedexpansion
REM client.bat - Auto-install cloudflared + buka TCP tunnel untuk RustDesk client (Mode B)
REM Edit 3 host di bawah sesuai tunnel kamu. VPS direct TIDAK butuh file ini.
REM Usage: double-click client.bat (Run as Administrator jika download gagal)

set ID_HOST=id.rustdesk.example.com
set RELAY_HOST=relay.rustdesk.example.com
set NATTEST_HOST=nattest.rustdesk.example.com

set CLOUDFLARED=%~dp0cloudflared.exe
set URL=https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe

echo === RustDesk Client Tunnel (Cloudflare) ===
echo ID_HOST=%ID_HOST%
echo RELAY_HOST=%RELAY_HOST%
echo NATTEST_HOST=%NATTEST_HOST%
echo.

REM 1. Download cloudflared jika belum ada
if not exist "%CLOUDFLARED%" (
  echo [1/4] Download cloudflared...
  powershell -Command "Invoke-WebRequest -Uri '%URL%' -OutFile '%CLOUDFLARED%'"
  if not exist "%CLOUDFLARED%" (
    echo GAGAL download. Jalankan sebagai Administrator atau download manual:
    echo %URL% -^> cloudflared.exe
    pause
    exit /b 1
  )
) else (
  echo [1/4] cloudflared sudah ada: %CLOUDFLARED%
)

REM 2. Cek cloudflared bisa jalan
"%CLOUDFLARED%" --version
if errorlevel 1 (
  echo cloudflared tidak bisa jalan.
  pause
  exit /b 1
)

echo.
echo [2/4] Menjalankan tunnel...
echo Jangan tutup window ini selama pakai RustDesk!
echo.

REM 3. Jalankan 3 access tcp di window terpisah (minimized)
REM Kill lama jika ada
taskkill /F /IM cloudflared.exe 2>nul

start "rustdesk-tunnel-id" /MIN "%CLOUDFLARED%" access tcp --hostname %ID_HOST% --url localhost:21116
start "rustdesk-tunnel-relay" /MIN "%CLOUDFLARED%" access tcp --hostname %RELAY_HOST% --url localhost:21117
start "rustdesk-tunnel-nattest" /MIN "%CLOUDFLARED%" access tcp --hostname %NATTEST_HOST% --url localhost:21115

timeout /t 3 /nobreak >nul
echo [3/4] Cek tunnel...
netstat -ano | findstr "21115 21116 21117" | findstr LISTENING
if errorlevel 1 (
  echo WARNING: port 21115-21117 belum LISTENING, cek hostname & login: cloudflared tunnel login
) else (
  echo Tunnel OK - port listening:
  netstat -ano | findstr "21115 21116 21117"
)

echo.
echo [4/4] Set RustDesk client:
echo   ID Server    = 127.0.0.1
echo   Relay Server = 127.0.0.1
echo   Key          = (paste dari server: cat ./data/id_ed25519.pub)
echo.
echo Biarkan window ini terbuka. Untuk stop: tutup window ini + taskkill /F /IM cloudflared.exe
echo Tekan sembarang untuk stop tunnel...
pause
taskkill /F /IM cloudflared.exe 2>nul
echo Tunnel stopped.
pause
