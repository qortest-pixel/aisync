@echo off
chcp 65001 >nul
echo === AI Sync ===
powershell -ExecutionPolicy Bypass -File "%~dp0collect-and-upload.ps1"
timeout /t 3
