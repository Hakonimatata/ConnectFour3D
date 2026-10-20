@echo off
rem Starter spillet paa nett for venner (Cloudflare-tunnel). Se scripts\online.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0online.ps1" %*
