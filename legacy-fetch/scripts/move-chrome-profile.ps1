# Move Chrome profile to non-default location
# This allows --remote-debugging-port to work (Chrome 136+ security change)

$oldPath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
$newPath = "$env:LOCALAPPDATA\Google\ChromeDebug"

# Kill any remaining Chrome processes
Write-Host "Killing Chrome processes..."
Get-Process -Name "chrome" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

if (Test-Path $oldPath) {
    Write-Host "Moving Chrome profile..."
    Write-Host "  From: $oldPath"
    Write-Host "  To:   $newPath"

    Move-Item -Path $oldPath -Destination $newPath -Force
    Write-Host "Done! Profile moved."
} else {
    Write-Host "Chrome profile not found at default location."
    Write-Host "May already be moved or Chrome not installed."
}

Write-Host ""
Write-Host "Update your Chrome shortcut to use:"
Write-Host "  --user-data-dir=`"$newPath`" --remote-debugging-port=9223 --remote-allow-origins=*"
