Set WshShell = CreateObject("WScript.Shell")
Set FSO = CreateObject("Scripting.FileSystemObject")

' PS1 경로: .ai-sync-hub 폴더 우선, 없으면 같은 폴더
hubPath = WshShell.ExpandEnvironmentStrings("%USERPROFILE%") & "\.ai-sync-hub\windows\collect-and-upload.ps1"
localPath = FSO.GetParentFolderName(WScript.ScriptFullName) & "\collect-and-upload.ps1"

If FSO.FileExists(hubPath) Then
    psPath = hubPath
Else
    psPath = localPath
End If

' 완전 무소음: -WindowStyle Hidden + Run 0번 파라미터 (창 숨김)
WshShell.Run "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoLogo -NoProfile -File """ & psPath & """", 0, False
