param(
    [Alias("s")]
    [string]$Serial = "",
    [string]$Adb = "",
    [switch]$SkipBuild,
    [switch]$NoTests,
    [switch]$NoDownloads
)

$ErrorActionPreference = "Stop"

$ScriptVersion = "2026-07-03.1"
$AppPackage = "uz.neovex.iccu.kiosk"
$DebugRemoveActivity = "uz.neovex.iccu.kiosk/.DebugRemoveOwnerActivity"
$ApkRelativePath = "app\build\outputs\apk\debug\app-debug.apk"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ApkPath = Join-Path $ProjectRoot $ApkRelativePath
$GradlewPath = Join-Path $ProjectRoot "gradlew.bat"
$ProvisionScriptPath = Join-Path $ProjectRoot "tools\provision_kiosk_tablet.ps1"
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

function Invoke-NativeCapture {
    param(
        [string]$File,
        [string[]]$Arguments
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $File @Arguments 2>&1 | ForEach-Object { $_.ToString() }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return [PSCustomObject]@{
        Code = $code
        Text = ($output -join "`n")
        Lines = @($output)
    }
}

function Invoke-NativeStream {
    param(
        [string]$File,
        [string[]]$Arguments
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $File @Arguments 2>&1 | ForEach-Object { Write-Host $_.ToString() }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return $code
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

function Install-PortableAdb {
    Ensure-Directory -Path $PortableRoot
    $zipPath = Join-Path $PortableRoot "platform-tools-latest-windows.zip"

    if (-not (Test-Path $zipPath)) {
        Download-File -Url $PlatformToolsUrl -OutFile $zipPath
    }

    Expand-Zip -ZipPath $zipPath -Destination $PortableRoot

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
        "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe",
        "$PortableRoot\android-sdk\platform-tools\adb.exe",
        "$PortableRoot\platform-tools\adb.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return (Resolve-Path $candidate).Path
        }
    }

    Write-Warn "adb.exe was not found. Downloading portable Android platform-tools into tools\.portable."
    return (Install-PortableAdb)
}

function Get-JavaMajorVersion {
    param([string]$JavaExe)

    $result = Invoke-NativeCapture -File $JavaExe -Arguments @("-version")
    if ($result.Text -match 'version "1\.(\d+)\.') {
        return [int]$Matches[1]
    }
    if ($result.Text -match 'version "(\d+)(\.|\+)') {
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

function Configure-JavaIfNeeded {
    if ($SkipBuild -and (Test-Path $ApkPath)) {
        return
    }

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
        if ($candidate -and (Test-Path $candidate) -and (Get-JavaMajorVersion -JavaExe $candidate) -ge 17) {
            $javaHome = Split-Path -Parent (Split-Path -Parent (Resolve-Path $candidate).Path)
            $env:JAVA_HOME = $javaHome
            $env:PATH = (Join-Path $javaHome "bin") + [IO.Path]::PathSeparator + $env:PATH
            Write-Ok "Using Java: $javaHome"
            return
        }
    }

    Write-Warn "Java 17 was not found. Downloading portable JDK 17 into tools\.portable."
    $javaHome = Install-PortableJava
    $env:JAVA_HOME = $javaHome
    $env:PATH = (Join-Path $javaHome "bin") + [IO.Path]::PathSeparator + $env:PATH
    Write-Ok "Using Java: $javaHome"
}

function Run-Command {
    param(
        [string]$File,
        [string[]]$Arguments
    )

    Write-Step "$File $($Arguments -join ' ')"
    $code = Invoke-NativeStream -File $File -Arguments $Arguments
    if ($code -ne 0) {
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
    return Invoke-NativeCapture -File $script:AdbPath -Arguments (@("-s", $script:Serial) + $Arguments)
}

function Get-DeviceRows {
    $result = Invoke-NativeCapture -File $script:AdbPath -Arguments @("devices")
    if ($result.Code -ne 0) {
        Fail "adb devices failed"
    }

    $rows = @()
    foreach ($line in $result.Lines) {
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

function Build-DebugApkIfNeeded {
    if ($SkipBuild) {
        Write-Warn "Skipping build because -SkipBuild was used"
        if (-not (Test-Path $ApkPath)) {
            Fail "APK does not exist: $ApkPath"
        }
        return
    }

    if (Test-Path $ProvisionScriptPath) {
        $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ProvisionScriptPath, "-BuildOnly")
        if ($NoTests) {
            $arguments += "-NoTests"
        }
        if ($NoDownloads) {
            $arguments += "-NoDownloads"
        }
        Run-Command -File "powershell.exe" -Arguments $arguments
    } else {
        if (-not (Test-Path $GradlewPath)) {
            Fail "gradlew.bat not found: $GradlewPath"
        }

        Configure-JavaIfNeeded

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
    }

    if (-not (Test-Path $ApkPath)) {
        Fail "Build finished but APK was not found: $ApkPath"
    }

    Write-Ok "Debug APK ready: $ApkRelativePath"
}

function Test-PackageInstalled {
    $result = Capture-AdbDevice -Arguments @("shell", "pm", "list", "packages", $AppPackage)
    return $result.Text -match [regex]::Escape("package:$AppPackage")
}

function Get-DeviceOwnerDetails {
    $policyDump = Capture-AdbDevice -Arguments @("shell", "dumpsys", "device_policy")
    if ($policyDump.Text -eq "") {
        return ""
    }

    $interesting = $policyDump.Lines |
        Where-Object {
            $_ -match "Device Owner" -or
            $_ -match "device owner" -or
            $_ -match "admin=" -or
            $_ -match "ComponentInfo" -or
            $_ -match [regex]::Escape($AppPackage)
        } |
        Select-Object -First 30

    return ($interesting -join "`n")
}

function Test-OurAppIsDeviceOwner {
    $ownerDetails = Get-DeviceOwnerDetails
    return $ownerDetails -match [regex]::Escape($AppPackage)
}

function Install-DebugApkForRemoval {
    Build-DebugApkIfNeeded
    Write-Step "Installing debug APK with removal hook"
    $result = Capture-AdbDevice -Arguments @("install", "-r", $ApkPath)
    Write-Host $result.Text
    if ($result.Code -eq 0) {
        Write-Ok "Debug APK installed"
        return
    }

    Write-Step "Retrying install with --no-streaming"
    $result = Capture-AdbDevice -Arguments @("install", "--no-streaming", "-r", $ApkPath)
    Write-Host $result.Text
    if ($result.Code -ne 0) {
        Fail "Debug APK install failed"
    }
    Write-Ok "Debug APK installed"
}

function Clear-DeviceOwnerWithDebugActivity {
    Install-DebugApkForRemoval
    Write-Step "Clearing Device Owner inside the app"
    $result = Capture-AdbDevice -Arguments @("shell", "am", "start", "-n", $DebugRemoveActivity)
    Write-Host $result.Text
    if ($result.Code -ne 0) {
        Fail "Could not start $DebugRemoveActivity"
    }

    Start-Sleep -Seconds 3

    if (Test-OurAppIsDeviceOwner) {
        Write-Host (Get-DeviceOwnerDetails)
        Fail "Device Owner was not cleared. Open the app, exit kiosk with PIN 2026 if needed, then run again."
    }

    Write-Ok "Device Owner cleared"
}

function Uninstall-App {
    if (-not (Test-PackageInstalled)) {
        Write-Ok "Package is already not installed: $AppPackage"
        return
    }

    Run-AdbDevice -Arguments @("shell", "am", "force-stop", $AppPackage)

    if (Test-OurAppIsDeviceOwner) {
        Write-Warn "$AppPackage is Device Owner; clearing it before uninstall"
        Clear-DeviceOwnerWithDebugActivity
    }

    Write-Step "Uninstalling $AppPackage"
    $result = Capture-AdbDevice -Arguments @("uninstall", $AppPackage)
    Write-Host $result.Text
    if ($result.Code -ne 0) {
        if ($result.Text -match "DELETE_FAILED_DEVICE_POLICY_MANAGER") {
            Fail "Android still reports Device Owner. Factory reset may be required if this is a non-debug/non-removable owner."
        }
        Fail "Uninstall failed"
    }

    if (Test-PackageInstalled) {
        Fail "Uninstall command finished, but package is still installed"
    }

    Write-Ok "Package removed: $AppPackage"
}

$script:Serial = $Serial
$script:AdbPath = Resolve-Adb

Write-Host "ICCU kiosk uninstall script version: $ScriptVersion" -ForegroundColor White
Write-Host "Project: $ProjectRoot"
Write-Host "Package: $AppPackage"
Write-Host "ADB: $script:AdbPath"
Write-Host ""

Select-Device
Uninstall-App

Write-Host ""
Write-Host "DONE: tablet $($script:Serial) no longer has $AppPackage installed." -ForegroundColor Green
