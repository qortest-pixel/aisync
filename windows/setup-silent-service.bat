@echo off
chcp 65001 >nul
echo ========================================
echo   AI Sync - 무소음 백그라운드 서비스 설치
echo ========================================
echo.

:: 1. 기존 작업 스케줄러 삭제
echo [1/4] 기존 작업 삭제 중...
schtasks /delete /tn "AI-Sync-Auto" /f >nul 2>&1
echo       완료

:: 2. 로컬 허브 폴더 생성 + 최신 파일 복사
echo [2/4] 파일 복사 중...
set HUBDIR=%USERPROFILE%\.ai-sync-hub\windows
if not exist "%HUBDIR%" mkdir "%HUBDIR%"
copy /y "%~dp0collect-and-upload.ps1" "%HUBDIR%\" >nul
copy /y "%~dp0sync-silent.vbs" "%HUBDIR%\" >nul
echo       완료

:: 3. 새 무소음 작업 등록 (VBS 경유 → 창 0개)
echo [3/4] 무소음 서비스 등록 중...
schtasks /create /tn "AI-Sync-Silent" /tr "wscript.exe \"%HUBDIR%\sync-silent.vbs\"" /sc minute /mo 30 /f >nul 2>&1
echo       완료

:: 4. 확인
echo [4/4] 확인 중...
schtasks /query /tn "AI-Sync-Silent" /fo LIST 2>nul | findstr "상태 Status"
echo.
echo ========================================
echo   설치 완료! 이제 창이 절대 안 뜹니다.
echo   30분마다 백그라운드로 동기화됩니다.
echo ========================================
echo.
pause
