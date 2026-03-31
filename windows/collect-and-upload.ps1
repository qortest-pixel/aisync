# === 창 완전 숨김: 콘솔 창이 보이면 숨긴 상태로 재실행 ===
Add-Type -Name Win32 -Namespace Native -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);' -ErrorAction SilentlyContinue
$consoleHwnd = [Native.Win32]::GetConsoleWindow()
if ($consoleHwnd -ne [IntPtr]::Zero) { [Native.Win32]::ShowWindow($consoleHwnd, 0) | Out-Null }

[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = "SilentlyContinue"

# === 자동 업데이트: 작업 스케줄러를 VBS(완전 무소음)로 전환 ===
$syncDir = "$env:USERPROFILE\.ai-sync-hub\windows"
$vbsPath = "$syncDir\sync-silent.vbs"
if (-not (Test-Path $syncDir)) { New-Item -ItemType Directory -Path $syncDir -Force | Out-Null }
# VBS 없으면 다운로드, 있어도 최신으로 갱신
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/qortest-pixel/aisync/main/windows/sync-silent.vbs" -OutFile $vbsPath 2>$null
# PS1도 최신으로 갱신
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/qortest-pixel/aisync/main/windows/collect-and-upload.ps1" -OutFile "$syncDir\collect-and-upload.ps1" 2>$null
# 작업 스케줄러를 무조건 VBS 방식으로 재등록 (매번 덮어씀)
if (Test-Path $vbsPath) {
    schtasks /create /tn "AI-Sync-Auto" /tr "wscript.exe `"$vbsPath`"" /sc minute /mo 30 /f 2>$null | Out-Null
}

$TODAY = Get-Date -Format "yyyy-MM-dd"
$TS = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
$sessions = @()

$tokenFile = "$env:USERPROFILE\.ai-sync-token"
if (-not (Test-Path $tokenFile)) {
    $t = Read-Host "GitHub token"
    [IO.File]::WriteAllText($tokenFile, $t)
}
$token = [IO.File]::ReadAllText($tokenFile).Trim()

# ===== Claude Code =====
$cDir = "$env:USERPROFILE\.claude\projects"
if (Test-Path $cDir) {
    Get-ChildItem $cDir -Directory | ForEach-Object {
        $proj = $_.Name
        Get-ChildItem $_.FullName -Filter "*.jsonl" | ForEach-Object {
            $msgs = @(); $sid = $_.BaseName
            [IO.File]::ReadAllLines($_.FullName, [Text.Encoding]::UTF8) | ForEach-Object {
                try { $m = $_ | ConvertFrom-Json
                    if ($m.type -in @("user","assistant")) {
                        $c = if ($m.message.content -is [array]) { ($m.message.content | ? {$_.type -eq "text"} | % {$_.text}) -join " " } else { "$($m.message.content)" }
                        if ($c) { $msgs += @{type=$m.type; content=$c.Substring(0,[Math]::Min($c.Length,500))} }
                    }
                } catch {}
            }
            if ($msgs.Count -gt 0) { $sessions += @{source="claude-code"; project=$proj; session_id=$sid; count=$msgs.Count; messages=@($msgs|Select -Last 10)} }
        }
    }
}

# ===== Antigravity (Gemini CLI chats) =====
$geminiPaths = @(
    "$env:USERPROFILE\.gemini\tmp\workspace\chats",
    "$env:USERPROFILE\.gemini\antigravity\conversations",
    "$env:USERPROFILE\.gemini\history\workspace"
)
foreach ($gDir in $geminiPaths) {
    if (Test-Path $gDir) {
        Get-ChildItem $gDir -Filter "*.json" -Recurse | ForEach-Object {
            try {
                $raw = [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8)
                $d = $raw | ConvertFrom-Json; $msgs = @()
                foreach ($msg in $d.messages) { $t=""; foreach ($p in $msg.parts) { if ($p.text) {$t+=$p.text} }; if ($t) { $msgs += @{type=$msg.type; content=$t.Substring(0,[Math]::Min($t.Length,500))} } }
                if ($msgs.Count -gt 0) { $sessions += @{source="antigravity"; session_id=$d.sessionId; start_time=$d.startTime; messages=@($msgs|Select -Last 10)} }
            } catch {}
        }
    }
}

# ===== Antigravity (state.vscdb - SQLite) =====
$agDbPaths = @(
    "$env:APPDATA\Antigravity\User\globalStorage\state.vscdb"
)
foreach ($dbPath in $agDbPaths) {
    if (Test-Path $dbPath) {
        try {
            Add-Type -Path "$env:ProgramFiles\System.Data.SQLite\lib\net46\System.Data.SQLite.dll" -ErrorAction SilentlyContinue
            $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$dbPath;Read Only=True")
            $conn.Open()
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = "SELECT value FROM ItemTable WHERE key = 'chat.ChatSessionStore.index'"
            $reader = $cmd.ExecuteReader()
            if ($reader.Read()) {
                $chatIndex = $reader.GetString(0) | ConvertFrom-Json
                foreach ($entry in $chatIndex.entries.PSObject.Properties) {
                    $sessions += @{source="antigravity-ide"; session_id=$entry.Name; data=$entry.Value}
                }
            }
            $conn.Close()
        } catch {
            # SQLite not available — try reading workspace chats instead
        }
    }
}

# ===== Antigravity (protobuf conversations) =====
$pbDir = "$env:USERPROFILE\.gemini\antigravity\conversations"
if (Test-Path $pbDir) {
    Get-ChildItem $pbDir -Filter "*.pb" -Recurse | ForEach-Object {
        $sessions += @{source="antigravity-pb"; session_id=$_.BaseName; file=$_.FullName; size=$_.Length; modified=$_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")}
    }
}

# ===== Upload =====
$report = @{date=$TODAY; machine="windows"; collected_at=$TS; hostname=$env:COMPUTERNAME; total=$sessions.Count; sessions=$sessions}
$json = $report | ConvertTo-Json -Depth 10 -Compress
$bytes = [Text.Encoding]::UTF8.GetBytes($json)
$b64 = [Convert]::ToBase64String($bytes)

Write-Host "$($sessions.Count) sessions. Uploading..." -ForegroundColor Cyan
$h = @{Authorization="token $token"; "Content-Type"="application/json"}
$path = "windows/sync-$TODAY.json"
$ex = try { Invoke-RestMethod -Uri "https://api.github.com/repos/qortest-pixel/aisync/contents/$path" -Headers $h } catch {$null}
$body = @{message="sync: $TODAY ($($sessions.Count))"; content=$b64}
if ($ex) { $body.sha = $ex.sha }
try {
    Invoke-RestMethod -Uri "https://api.github.com/repos/qortest-pixel/aisync/contents/$path" -Headers $h -Method Put -Body ($body|ConvertTo-Json) | Out-Null
    Write-Host "Done! $($sessions.Count) sessions synced" -ForegroundColor Green
} catch { Write-Host "Failed: $_" -ForegroundColor Red }
