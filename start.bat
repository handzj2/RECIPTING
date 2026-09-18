@echo off
title HandzJ Digital Receipts — Local Start
cd /d "%~dp0"

echo ============================================
echo  HANDZJ DIGITAL RECEIPTS
echo  Local start (before Supabase + Vercel)
echo ============================================
echo.

REM Local data folder (browser localStorage is primary;
REM this folder holds exports, backups, and future SQLite)
if not exist "data" mkdir data
if not exist "data\receipts" mkdir data\receipts
if not exist "data\backups" mkdir data\backups

echo [1/3] Local folders ready:
echo       data\
echo       data\receipts\
echo       data\backups\
echo.

if not exist ".env.local" (
  if exist ".env.example" (
    copy /Y ".env.example" ".env.local" >nul
    echo [2/3] Created .env.local from example.
    echo       Edit .env.local when you connect Supabase / Resend.
  ) else (
    echo [2/3] No .env.example found — skipping env setup.
  )
) else (
  echo [2/3] .env.local already exists.
)
echo.

echo [3/3] Starting local web server on http://localhost:3000
echo       Landing page : http://localhost:3000/
echo       Receipt app  : http://localhost:3000/app.html
echo.
echo Press Ctrl+C to stop the server.
echo.

where node >nul 2>&1
if errorlevel 1 (
  echo Node.js not found. Opening app file directly in your browser...
  start "" "%~dp0public\index.html"
  echo.
  echo TIP: Install Node.js from https://nodejs.org for a proper local server.
  pause
  exit /b 0
)

npx --yes serve public -l 3000
