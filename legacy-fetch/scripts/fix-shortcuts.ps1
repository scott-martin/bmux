$shell = New-Object -ComObject WScript.Shell

# Fix Chrome shortcut - just debug port, no user-data-dir
$lnk = $shell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Google Chrome (Debug).lnk")
$lnk.TargetPath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$lnk.Arguments = "--remote-debugging-port=9223"
$lnk.IconLocation = "C:\Program Files\Google\Chrome\Application\chrome.exe,0"
$lnk.Save()
Write-Host "Fixed Chrome shortcut"

# Fix Edge shortcut
$lnk = $shell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Microsoft Edge (Debug).lnk")
$lnk.TargetPath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
$lnk.Arguments = "--remote-debugging-port=9222"
$lnk.IconLocation = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe,0"
$lnk.Save()
Write-Host "Fixed Edge shortcut"
