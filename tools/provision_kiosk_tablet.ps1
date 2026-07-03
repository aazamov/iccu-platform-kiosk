param(
    [Alias("s")]
    [string]$Serial = "",
    [switch]$SkipBuild,
    [switch]$NoTests,
    [string]$Adb = "",
    [switch]$NoDownloads,
    [switch]$PrepareTools,
    [switch]$BuildOnly
)

$ErrorActionPreference = "Stop"

$AppPackage = "uz.neovex.iccu.kiosk"
$MainActivity = "uz.neovex.iccu.kiosk/.MainActivity"
$AdminReceiver = "uz.neovex.iccu.kiosk/.KioskDeviceAdminReceiver"
$ApkRelativePath = "app\build\outputs\apk\debug\app-debug.apk"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ApkPath = Join-Path $ProjectRoot $ApkRelativePath
$GradlewPath = Join-Path $ProjectRoot "gradlew.bat"
$PortableRoot = Join-Path $ProjectRoot "tools\.portable"
$PlatformToolsUrl = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
$Jdk17Url = "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk"

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "OK: $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "WARN: $Message" -ForegroundColor Yellow
}

function Fail {
    param([string]$Message)
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Download-File {
    param(
        [string]$Url,
        [string]$OutFile
    )

    if ($NoDownloads) {
        Fail "Required tool is missing and -NoDownloads was used. Missing download: $Url"
    }

    Ensure-Directory -Path (Split-Path -Parent $OutFile)
    Write-Step "Downloading $Url"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $oldProgressPreference = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    } finally {
        $ProgressPreference = $oldProgressPreference
    }
}

function Expand-Zip {
    param(
        [string]$ZipPath,
        [string]$Destination
    )

    Ensure-Directory -Path $Destination
    Write-Step "Extracting $ZipPath"
    Expand-Archive -Path $ZipPath -DestinationPath $Destination -Force
}

function Get-JavaMajorVersion {
    param([string]$JavaExe)

    $versionText = (& $JavaExe -version 2>&1) -join "`n"
    if ($versionText -match 'version "1\.(\d+)\.') {
        return [int]$Matches[1]
    }
    if ($versionText -match 'version "(\d+)(\.|\+)') {
        return [int]$Matches[1]
    }
    return 0
}

function Find-PortableJavaHome {
    $java = Get-ChildItem -Path $PortableRoot -Filter "java.exe" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\bin\\java\.exe$" } |
        Select-Object -First 1

    if ($java) {
        return (Split-Path -Parent (Split-Path -Parent $java.FullName))
    }
    return ""
}

function Install-PortableJava {
    Ensure-Directory -Path $PortableRoot
    $zipPath = Join-Path $PortableRoot "temurin-jdk17-windows-x64.zip"
    $extractPath = Join-Path $PortableRoot "jdk17"

    if (-not (Test-Path $zipPath)) {
        Download-File -Url $Jdk17Url -OutFile $zipPath
    }

    if (-not (Test-Path $extractPath)) {
        Expand-Zip -ZipPath $zipPath -Destination $extractPath
    }

    $javaHome = Find-PortableJavaHome
    if ($javaHome -eq "") {
        Fail "Portable Java download/extract finished, but java.exe was not found"
    }
    return $javaHome
}

function Resolve-JavaHome {
    $candidates = @()

    if ($env:JAVA_HOME) {
        $candidates += (Join-Path $env:JAVA_HOME "bin\java.exe")
    }

    $fromPath = Get-Command "java.exe" -ErrorAction SilentlyContinue
    if ($fromPath) {
        $candidates += $fromPath.Source
    }

    $portableHome = Find-PortableJavaHome
    if ($portableHome -ne "") {
        $candidates += (Join-Path $portableHome "bin\java.exe")
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            $major = Get-JavaMajorVersion -JavaExe $candidate
            if ($major -ge 17) {
                return (Split-Path -Parent (Split-Path -Parent (Resolve-Path $candidate).Path))
            }
            Write-Warn "Ignoring Java below version 17: $candidate"
        }
    }

    Write-Warn "Java 17 was not found. Downloading portable JDK 17 into tools\.portable."
    return (Install-PortableJava)
}

function Configure-Java {
    $javaHome = Resolve-JavaHome
    $env:JAVA_HOME = $javaHome
    $env:PATH = (Join-Path $javaHome "bin") + [IO.Path]::PathSeparator + $env:PATH
    Write-Ok "Using Java: $javaHome"
}

function Install-PortableAdb {
    Ensure-Directory -Path $PortableRoot
    $zipPath = Join-Path $PortableRoot "platform-tools-latest-windows.zip"
    $extractPath = $PortableRoot

    if (-not (Test-Path $zipPath)) {
        Download-File -Url $PlatformToolsUrl -OutFile $zipPath
    }

    Expand-Zip -ZipPath $zipPath -Destination $extractPath

    $adbPath = Join-Path $PortableRoot "platform-tools\adb.exe"
    if (-not (Test-Path $adbPath)) {
        Fail "Portable ADB download/extract finished, but adb.exe was not found"
    }
    return $adbPath
}

function Resolve-Adb {
    if ($Adb -ne "") {
        if (Test-Path $Adb) { return (Resolve-Path $Adb).Path }
        $cmd = Get-Command $Adb -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        Fail "ADB path is not valid: $Adb"
    }

    $fromPath = Get-Command "adb.exe" -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }

    $candidates = @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "$env:ProgramFiles\Android\Android Studio\platform-tools\adb.exe",
        "$env:ANDROID_HOME\platform-tools\adb.exe",
        "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return (Resolve-Path $candidate).Path
        }
    }

    $portableAdb = Join-Path $PortableRoot "platform-tools\adb.exe"
    if (Test-Path $portableAdb) {
        return (Resolve-Path $portableAdb).Path
    }

    Write-Warn "adb.exe was not found. Downloading portable Android platform-tools into tools\.portable."
    return (Install-PortableAdb)
}

function Run-Command {
    param(
        [string]$File,
        [string[]]$Arguments
    )

    Write-Step "$File $($Arguments -join ' ')"
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        Fail "Command failed: $File $($Arguments -join ' ')"
    }
}

function Run-Adb {
    param([string[]]$Arguments)
    Run-Command -File $script:AdbPath -Arguments $Arguments
}

function Run-AdbDevice {
    param([string[]]$Arguments)
    Run-Adb -Arguments (@("-s", $script:Serial) + $Arguments)
}

function Capture-AdbDevice {
    param([string[]]$Arguments)
    $fullArguments = @("-s", $script:Serial) + $Arguments
    $output = & $script:AdbPath @fullArguments 2>&1
    $code = $LASTEXITCODE
    return [PSCustomObject]@{
        Code = $code
        Text = ($output -join "`n")
    }
}

function Get-DeviceRows {
    $text = & $script:AdbPath devices
    if ($LASTEXITCODE -ne 0) {
        Fail "adb devices failed"
    }

    $rows = @()
    foreach ($line in $text) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "" -or $trimmed.StartsWith("List of devices")) { continue }
        $parts = $trimmed -split "\s+"
        if ($parts.Count -ge 2) {
            $rows += [PSCustomObject]@{
                Serial = $parts[0]
                State = $parts[1]
            }
        }
    }
    return $rows
}

function Select-Device {
    Run-Adb -Arguments @("start-server")

    $rows = Get-DeviceRows

    if ($script:Serial -ne "") {
        $match = $rows | Where-Object { $_.Serial -eq $script:Serial } | Select-Object -First 1
        if (-not $match) {
            Fail "Device $($script:Serial) not found. Run: adb devices"
        }
        if ($match.State -ne "device") {
            Fail "Device $($script:Serial) is not ready. Current state: $($match.State)"
        }
        Write-Ok "Using tablet $($script:Serial)"
        return
    }

    $ready = @($rows | Where-Object { $_.State -eq "device" })
    $unauthorized = @($rows | Where-Object { $_.State -eq "unauthorized" })
    $offline = @($rows | Where-Object { $_.State -eq "offline" })

    if ($ready.Count -eq 1) {
        $script:Serial = $ready[0].Serial
        Write-Ok "Using tablet $($script:Serial)"
        return
    }

    if ($ready.Count -gt 1) {
        Write-Host "More than one tablet is connected:"
        $ready | ForEach-Object { Write-Host "  $($_.Serial)" }
        Fail "Run again with -Serial DEVICE_SERIAL"
    }

    if ($unauthorized.Count -gt 0) {
        Write-Host "Unauthorized device(s):"
        $unauthorized | ForEach-Object { Write-Host "  $($_.Serial)" }
        Fail "Approve the USB debugging prompt on the tablet, then run this script again."
    }

    if ($offline.Count -gt 0) {
        Write-Host "Offline device(s):"
        $offline | ForEach-Object { Write-Host "  $($_.Serial)" }
        Fail "Reconnect the tablet or run: adb kill-server; adb start-server"
    }

    Fail "No ready tablet found. Connect one tablet and run: adb devices"
}

function Refresh-AdbConnection {
    Write-Warn "Refreshing ADB connection"
    & $script:AdbPath kill-server | Out-Null
    & $script:AdbPath start-server | Out-Null

    if ($script:Serial.Contains(":")) {
        & $script:AdbPath disconnect $script:Serial | Out-Null
        & $script:AdbPath connect $script:Serial | Out-Null
    }
}

function Build-Apk {
    if ($SkipBuild) {
        Write-Warn "Skipping build because -SkipBuild was used"
        if (-not (Test-Path $ApkPath)) {
            Fail "APK does not exist: $ApkPath"
        }
        return
    }

    if (-not (Test-Path $GradlewPath)) {
        Fail "gradlew.bat not found: $GradlewPath"
    }

    Push-Location $ProjectRoot
    try {
        if ($NoTests) {
            Run-Command -File $GradlewPath -Arguments @("assembleDebug")
        } else {
            Run-Command -File $GradlewPath -Arguments @("testDebugUnitTest", "assembleDebug")
        }
    } finally {
        Pop-Location
    }

    if (-not (Test-Path $ApkPath)) {
        Fail "Build finished but APK was not found: $ApkPath"
    }

    Write-Ok "APK ready: $ApkRelativePath"
}

function Install-Apk {
    Write-Step "Installing APK"
    $result = Capture-AdbDevice -Arguments @("install", "-r", $ApkPath)
    Write-Host $result.Text

    if ($result.Code -eq 0) {
        Write-Ok "APK installed"
        return
    }

    if ($result.Text -match "closed") {
        Refresh-AdbConnection

        Write-Step "Retrying APK install"
        $result = Capture-AdbDevice -Arguments @("install", "-r", $ApkPath)
        Write-Host $result.Text
        if ($result.Code -eq 0) {
            Write-Ok "APK installed"
            return
        }

        Write-Step "Retrying APK install with --no-streaming"
        $result = Capture-AdbDevice -Arguments @("install", "--no-streaming", "-r", $ApkPath)
        Write-Host $result.Text
        if ($result.Code -eq 0) {
            Write-Ok "APK installed"
            return
        }
    }

    Fail "APK install failed"
}

function Ensure-DeviceOwner {
    $owner = Capture-AdbDevice -Arguments @("shell", "dpm", "get-device-owner")
    if ($owner.Text -match [regex]::Escape($AppPackage)) {
        Write-Ok "Device Owner already set to $AppPackage"
        return
    }

    Write-Step "Setting Device Owner"
    $result = Capture-AdbDevice -Arguments @("shell", "dpm", "set-device-owner", $AdminReceiver)
    Write-Host $result.Text
    if ($result.Code -eq 0) {
        Write-Ok "Device Owner enabled"
        return
    }

    Write-Host ""
    Write-Host "Device Owner setup failed. Most common fixes:"
    Write-Host "- Remove Google/account(s) from the tablet"
    Write-Host "- Factory reset the tablet, do not add an account, enable USB debugging, then run this script"
    Write-Host "- Make sure the APK was installed before Device Owner setup"
    Fail "Cannot continue without Device Owner"
}

function Configure-Kiosk {
    Run-AdbDevice -Arguments @("shell", "cmd", "package", "set-home-activity", $MainActivity)
    Run-AdbDevice -Arguments @("shell", "settings", "put", "global", "policy_control", "immersive.full=*")
    Write-Ok "Home activity and immersive fullscreen configured"
}

function Launch-App {
    Run-AdbDevice -Arguments @("shell", "am", "force-stop", $AppPackage)
    Run-AdbDevice -Arguments @("shell", "monkey", "-p", $AppPackage, "1")
    Start-Sleep -Seconds 8
    Write-Ok "Kiosk app launched"
}

function Verify-Kiosk {
    Write-Step "Verifying kiosk lock"
    $dump = Capture-AdbDevice -Arguments @("shell", "dumpsys", "activity", "activities")

    if ($dump.Text -notmatch [regex]::Escape($AppPackage)) {
        Fail "Kiosk app is not visible in running activities"
    }

    if ($dump.Text -notmatch "mLockTaskModeState=LOCKED") {
        Write-Host ($dump.Text -split "`n" | Select-String -Pattern "mLockTaskModeState|$AppPackage" -Context 2,2)
        Fail "Kiosk is not locked. Expected: mLockTaskModeState=LOCKED"
    }

    Write-Ok "Kiosk verified: mLockTaskModeState=LOCKED"
}

$script:Serial = $Serial
Configure-Java

if ($BuildOnly) {
    Build-Apk
    Write-Host ""
    Write-Host "DONE: APK build is ready." -ForegroundColor Green
    exit 0
}

$script:AdbPath = Resolve-Adb

if ($PrepareTools) {
    Write-Host ""
    Write-Host "DONE: portable Java/ADB tools are ready." -ForegroundColor Green
    Write-Host "JAVA_HOME: $env:JAVA_HOME"
    Write-Host "ADB: $script:AdbPath"
    exit 0
}

Write-Host "ICCU Forum Kiosk Windows provisioning" -ForegroundColor White
Write-Host "Project: $ProjectRoot"
Write-Host "Package: $AppPackage"
Write-Host "ADB: $script:AdbPath"
Write-Host "JAVA_HOME: $env:JAVA_HOME"
Write-Host ""

Select-Device
Build-Apk
Install-Apk
Ensure-DeviceOwner
Configure-Kiosk
Launch-App
Verify-Kiosk

Write-Host ""
Write-Host "DONE: tablet $($script:Serial) is ready for kiosk use." -ForegroundColor Green
