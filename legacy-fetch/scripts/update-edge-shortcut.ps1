$shell = New-Object -ComObject WScript.Shell

$userDataDir = "$env:LOCALAPPDATA\Microsoft\EdgeDebug"
$args = "--user-data-dir=`"$userDataDir`" --remote-debugging-port=9222 --remote-allow-origins=*"

# Update Start Menu shortcut
$lnk = $shell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Microsoft Edge (Debug).lnk")
$lnk.TargetPath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
$lnk.Arguments = $args
$lnk.IconLocation = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe,0"
$lnk.Description = "Microsoft Edge with remote debugging"
$lnk.Save()
Write-Host "Updated Start Menu shortcut"

# Update Taskbar shortcut if exists
$taskbarPath = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Microsoft Edge.lnk"
if (Test-Path $taskbarPath) {
    $lnk = $shell.CreateShortcut($taskbarPath)
    $lnk.TargetPath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    $lnk.Arguments = $args
    $lnk.IconLocation = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe,0"
    $lnk.Save()
    Write-Host "Updated Taskbar shortcut"
}

Write-Host ""
Write-Host "Edge will now use: $userDataDir"
Write-Host "Debug port: 9222"
