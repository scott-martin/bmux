# Move Edge profile to non-default location and disable Startup Boost
# This allows --remote-debugging-port to work (Chromium 136+ security change)

$oldPath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
$newPath = "$env:LOCALAPPDATA\Microsoft\EdgeDebug"

# Kill any remaining Edge processes
Write-Host "Killing Edge processes..."
Get-Process -Name "msedge" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3

# Double-check they're dead
$remaining = Get-Process -Name "msedge" -ErrorAction SilentlyContinue
if ($remaining) {
    Write-Host "Force killing remaining Edge processes..."
    $remaining | Stop-Process -Force
    Start-Sleep -Seconds 2
}

if (Test-Path $oldPath) {
    Write-Host "Moving Edge profile..."
    Write-Host "  From: $oldPath"
    Write-Host "  To:   $newPath"

    Move-Item -Path $oldPath -Destination $newPath -Force
    Write-Host "Done! Profile moved."

    # Disable Startup Boost via registry
    Write-Host ""
    Write-Host "Disabling Startup Boost via registry..."
    $regPath = "HKCU:\Software\Microsoft\Edge\Main"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name "StartupBoostEnabled" -Value 0 -Type DWord
    Write-Host "Startup Boost disabled."
} else {
    Write-Host "Edge profile not found at default location."
    Write-Host "May already be moved or Edge not installed."
}

Write-Host ""
Write-Host "Edge profile moved to: $newPath"
