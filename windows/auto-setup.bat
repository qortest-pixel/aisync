@echo off
chcp 65001 >nul
echo.
echo ========================================
echo   AI Sync - 자동 실행 등록
echo ========================================
echo.

:: 최신 스크립트 다운로드
set SYNC_DIR=%USERPROFILE%\.ai-sync-hub
if not exist "%SYNC_DIR%\windows" mkdir "%SYNC_DIR%\windows"

echo 최신 스크립트 다운로드...
powershell -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/qortest-pixel/aisync/main/windows/collect-and-upload.ps1' -OutFile '%SYNC_DIR%\windows\collect-and-upload.ps1'"
powershell -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/qortest-pixel/aisync/main/windows/sync.bat' -OutFile '%SYNC_DIR%\windows\sync.bat'"

:: 작업 스케줄러 등록 (30분마다)
echo 자동 실행 등록 중...
schtasks /create /tn "AI-Sync-Auto" /tr "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%SYNC_DIR%\windows\collect-and-upload.ps1\"" /sc minute /mo 30 /f
echo.
echo ========================================
echo   완료! 30분마다 자동 동기화됩니다.
echo ========================================
echo.
timeout /t 5
