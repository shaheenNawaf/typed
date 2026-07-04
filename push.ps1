# Push the latest debug APK to a phone over wireless ADB.
# Usage:
#   .\push.ps1                        # build + install to the last connected device
#   .\push.ps1 -SkipBuild             # install only (assumes build is fresh)
#   .\push.ps1 -Release               # build release APK instead of debug
#   .\push.ps1 -Serial <serial>       # target a specific device

param(
    [switch]$SkipBuild,
    [switch]$Release,
    [string]$Serial = ""
)

$ErrorActionPreference = "Stop"
$androidPlatformTools = "$env:LOCALAPPDATA\Android\sdk\platform-tools"
if (-not (Test-Path $androidPlatformTools)) {
    $androidPlatformTools = "C:\Users\shahe\AppData\Local\Android\Sdk\platform-tools"
}
$env:Path = "$androidPlatformTools;$env:Path"

function Section($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

Section "ADB"
& adb version | Select-Object -First 1

Section "Devices"
$devices = & adb devices
Write-Host $devices

if ($devices -notmatch "device$") {
    Write-Host "`nNo devices connected. To connect over Wi-Fi:" -ForegroundColor Yellow
    Write-Host "  1. On phone: Settings → Developer options → Wireless debugging → Pair" -ForegroundColor Yellow
    Write-Host "  2. Note the IP:port and pairing code" -ForegroundColor Yellow
    Write-Host "  3. Run: adb pair <ip>:<port>" -ForegroundColor Yellow
    Write-Host "  4. Then: adb connect <phone-ip>:<port>  (the one shown after pairing, not the pair port)" -ForegroundColor Yellow
    exit 1
}

if ($Serial -ne "") {
    $target = $Serial
} else {
    $lines = $devices -split "`n" | Where-Object { $_ -match "device$" -and $_ -notmatch "List of devices" }
    if ($lines.Count -gt 1) {
        Write-Host "`nMultiple devices. Pass -Serial <id> to disambiguate." -ForegroundColor Yellow
        exit 1
    }
    $target = ($lines[0] -split "`s+")[0]
}

if (-not $SkipBuild) {
    Section "Building"
    if ($Release) {
        flutter build apk --release --target-platform android-arm64
    } else {
        flutter build apk --debug
    }
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

Section "Installing"
$apk = if ($Release) {
    "build\app\outputs\flutter-apk\app-release.apk"
} else {
    "build\app\outputs\flutter-apk\app-debug.apk"
}

# Uninstall first to avoid signature/version conflicts (the previous build
# might be installed under the same package, signed with a different key)
Write-Host "Uninstalling any existing build of com.z4yed.typed..." -ForegroundColor Yellow
& adb -s $target uninstall com.z4yed.typed 2>&1 | Out-Null

Write-Host "Installing $apk to $target..." -ForegroundColor Green
& adb -s $target install -r $apk

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nDone. Launch with:" -ForegroundColor Green
    Write-Host "  adb -s $target shell am start -n com.z4yed.typed/.MainActivity" -ForegroundColor Green
} else {
    Write-Host "`nInstall failed." -ForegroundColor Red
    exit 1
}
