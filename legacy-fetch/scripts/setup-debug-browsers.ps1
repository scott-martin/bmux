# Setup Debug-Enabled Browser Shortcuts
# This script creates/replaces browser shortcuts with debug-enabled versions
# that allow CDP (Chrome DevTools Protocol) connections.

param(
    [switch]$Force,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

# Configuration
$browsers = @{
    edge = @{
        name = "Microsoft Edge"
        exePath = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
        altExePath = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
        debugPort = 9222
        userDataDir = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
        iconIndex = 0
    }
    chrome = @{
        name = "Google Chrome"
        exePath = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
        altExePath = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
        debugPort = 9223
        userDataDir = "$env:LOCALAPPDATA\Google\Chrome\User Data"
        iconIndex = 0
    }
}

$taskbarPath = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
$startMenuPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"

function Get-BrowserExePath {
    param($browser)

    if (Test-Path $browser.exePath) {
        return $browser.exePath
    }
    if (Test-Path $browser.altExePath) {
        return $browser.altExePath
    }
    return $null
}

function New-DebugShortcut {
    param(
        [string]$ShortcutPath,
        [string]$TargetPath,
        [string]$Arguments,
        [string]$IconLocation,
        [string]$Description
    )

    if ($WhatIf) {
        Write-Host "[WhatIf] Would create shortcut: $ShortcutPath" -ForegroundColor Cyan
        Write-Host "         Target: $TargetPath $Arguments" -ForegroundColor Gray
        return
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Arguments = $Arguments
    $shortcut.IconLocation = $IconLocation
    $shortcut.Description = $Description
    $shortcut.WorkingDirectory = Split-Path $TargetPath
    $shortcut.Save()

    Write-Host "Created: $ShortcutPath" -ForegroundColor Green
}

function Update-TaskbarShortcut {
    param(
        [string]$BrowserKey,
        [hashtable]$Browser
    )

    $exePath = Get-BrowserExePath $Browser
    if (-not $exePath) {
        Write-Host "Skipping $($Browser.name) - not installed" -ForegroundColor Yellow
        return
    }

    # Find existing taskbar shortcut
    $existingShortcuts = Get-ChildItem -Path $taskbarPath -Filter "*.lnk" | Where-Object {
        $shell = New-Object -ComObject WScript.Shell
        $lnk = $shell.CreateShortcut($_.FullName)
        $lnk.TargetPath -like "*$BrowserKey*" -or $lnk.TargetPath -like "*$(Split-Path $exePath -Leaf)*"
    }

    $arguments = "--remote-debugging-port=$($Browser.debugPort)"
    $iconLocation = "$exePath,$($Browser.iconIndex)"
    $description = "$($Browser.name) (Debug Mode - Port $($Browser.debugPort))"

    if ($existingShortcuts) {
        foreach ($shortcut in $existingShortcuts) {
            Write-Host "Updating existing taskbar shortcut: $($shortcut.Name)" -ForegroundColor Cyan

            if (-not $WhatIf) {
                # Backup original
                $backupPath = "$($shortcut.FullName).bak"
                if (-not (Test-Path $backupPath)) {
                    Copy-Item $shortcut.FullName $backupPath
                    Write-Host "  Backed up to: $backupPath" -ForegroundColor Gray
                }
            }

            New-DebugShortcut `
                -ShortcutPath $shortcut.FullName `
                -TargetPath $exePath `
                -Arguments $arguments `
                -IconLocation $iconLocation `
                -Description $description
        }
    } else {
        # Create new taskbar shortcut
        $shortcutPath = Join-Path $taskbarPath "$($Browser.name).lnk"
        Write-Host "Creating new taskbar shortcut: $($Browser.name)" -ForegroundColor Cyan

        New-DebugShortcut `
            -ShortcutPath $shortcutPath `
            -TargetPath $exePath `
            -Arguments $arguments `
            -IconLocation $iconLocation `
            -Description $description
    }
}

function Create-StartMenuShortcut {
    param(
        [string]$BrowserKey,
        [hashtable]$Browser
    )

    $exePath = Get-BrowserExePath $Browser
    if (-not $exePath) {
        return
    }

    $shortcutPath = Join-Path $startMenuPath "$($Browser.name) (Debug).lnk"
    $arguments = "--remote-debugging-port=$($Browser.debugPort)"
    $iconLocation = "$exePath,$($Browser.iconIndex)"
    $description = "$($Browser.name) with remote debugging enabled on port $($Browser.debugPort)"

    New-DebugShortcut `
        -ShortcutPath $shortcutPath `
        -TargetPath $exePath `
        -Arguments $arguments `
        -IconLocation $iconLocation `
        -Description $description
}

# Main
Write-Host "`n=== Browser Debug Shortcut Setup ===" -ForegroundColor Magenta
Write-Host "This script creates debug-enabled browser shortcuts."
Write-Host "Debug mode allows tools like 'fetch' to connect to your browser.`n"

if ($WhatIf) {
    Write-Host "[WhatIf mode - no changes will be made]`n" -ForegroundColor Yellow
}

# Process each browser
foreach ($key in $browsers.Keys) {
    $browser = $browsers[$key]
    Write-Host "`n--- $($browser.name) ---" -ForegroundColor White

    Update-TaskbarShortcut -BrowserKey $key -Browser $browser
    Create-StartMenuShortcut -BrowserKey $key -Browser $browser
}

Write-Host "`n=== Setup Complete ===" -ForegroundColor Magenta
Write-Host @"

Debug ports:
  Edge:   http://127.0.0.1:9222
  Chrome: http://127.0.0.1:9223

To test, restart your browser using the new shortcut, then run:
  curl http://127.0.0.1:9222/json/version

If you see JSON output, debug mode is working!

Note: You may need to unpin and re-pin the browser to taskbar
for changes to take effect on existing pins.
"@
