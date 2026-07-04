# Watch the project and auto-push the debug APK on every change.
# This is the fastest iteration loop: ~5-8 seconds per change vs ~60s for manual.
#
# Requires: wireless ADB already set up and phone connected (run `adb devices`)
# Usage:    .\watch-push.ps1

$ErrorActionPreference = "Stop"
$androidPlatformTools = "$env:LOCALAPPDATA\Android\sdk\platform-tools"
if (-not (Test-Path $androidPlatformTools)) {
    $androidPlatformTools = "C:\Users\shahe\AppData\Local\Android\Sdk\platform-tools"
}
$env:Path = "$androidPlatformTools;$env:Path"

Write-Host "Checking for connected device..." -ForegroundColor Cyan
$devices = & adb devices
if ($devices -notmatch "device$") {
    Write-Host "No device. Connect first (see push.ps1 for instructions)." -ForegroundColor Red
    exit 1
}

Write-Host "Watching for changes. Press Ctrl+C to stop." -ForegroundColor Green
Write-Host "Building on file changes, then pushing via adb install -r." -ForegroundColor Gray

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $PSScriptRoot
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true
$watcher.Filter = "*"

$lastBuild = Get-Date 0
$buildScriptBlock = {
    $now = Get-Date
    if (($now - $lastBuild) -lt [TimeSpan]::FromSeconds(3)) { return }
    $lastBuild = $now

    $path = $Event.SourceEventArgs.FullPath
    if ($path -match "(\.dart|\.yaml|\.xml)$") {
        Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Change: $path" -ForegroundColor Yellow
        Write-Host "Building..." -ForegroundColor Cyan
        flutter build apk --debug 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Pushing..." -ForegroundColor Cyan
            $apk = "build\app\outputs\flutter-apk\app-debug.apk"
            & adb install -r $apk 2>&1 | Out-Null
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Pushed." -ForegroundColor Green
        } else {
            Write-Host "Build failed." -ForegroundColor Red
        }
    }
}

Register-ObjectEvent -InputObject $watcher -EventName "Changed" -Action $buildScriptBlock
Register-ObjectEvent -InputObject $watcher -EventName "Created" -Action $buildScriptBlock

while ($true) { Start-Sleep -Seconds 1 }
