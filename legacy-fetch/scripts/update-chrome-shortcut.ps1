$shell = New-Object -ComObject WScript.Shell

$userDataDir = "$env:LOCALAPPDATA\Google\ChromeDebug"
$args = "--user-data-dir=`"$userDataDir`" --remote-debugging-port=9223 --remote-allow-origins=*"

# Update Start Menu shortcut
$lnk = $shell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Google Chrome (Debug).lnk")
$lnk.TargetPath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$lnk.Arguments = $args
$lnk.IconLocation = "C:\Program Files\Google\Chrome\Application\chrome.exe,0"
$lnk.Description = "Google Chrome with remote debugging"
$lnk.Save()
Write-Host "Updated Start Menu shortcut"

# Update Taskbar shortcut if exists
$taskbarPath = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Google Chrome.lnk"
if (Test-Path $taskbarPath) {
    $lnk = $shell.CreateShortcut($taskbarPath)
    $lnk.TargetPath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    $lnk.Arguments = $args
    $lnk.IconLocation = "C:\Program Files\Google\Chrome\Application\chrome.exe,0"
    $lnk.Save()
    Write-Host "Updated Taskbar shortcut"
}

Write-Host ""
Write-Host "Chrome will now use: $userDataDir"
Write-Host "Debug port: 9223"
