[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = "SilentlyContinue"
$TODAY = Get-Date -Format "yyyy-MM-dd"
$TS = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
$sessions = @()

$tokenFile = "$env:USERPROFILE\.ai-sync-token"
if (-not (Test-Path $tokenFile)) {
    $t = Read-Host "GitHub token"
    [IO.File]::WriteAllText($tokenFile, $t)
}
$token = [IO.File]::ReadAllText($tokenFile).Trim()

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

$gDir = "$env:USERPROFILE\.gemini\tmp\workspace\chats"
if (Test-Path $gDir) {
    Get-ChildItem $gDir -Filter "*.json" | ForEach-Object {
        try { $d = [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json; $msgs = @()
            foreach ($msg in $d.messages) { $t=""; foreach ($p in $msg.parts) { if ($p.text) {$t+=$p.text} }; if ($t) { $msgs += @{type=$msg.type; content=$t.Substring(0,[Math]::Min($t.Length,500))} } }
            if ($msgs.Count -gt 0) { $sessions += @{source="antigravity"; session_id=$d.sessionId; messages=@($msgs|Select -Last 10)} }
        } catch {}
    }
}

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
