param(
    [Alias("s")]
    [string]$Serial = "",
    [switch]$SkipBuild,
    [switch]$NoTests,
    [string]$Adb = "",
    [switch]$NoDownloads,
    [switch]$PrepareTools,
    [switch]$BuildOnly,
    [string]$WebViewApk = "",
    [string]$WebViewApkUrl = "",
    [switch]$SkipWebViewUpdate,
    [int]$MinimumWebViewMajor = 100,
    [string]$WifiSsid = "Neo_wifi",
    [string]$WifiPassword = "12345678!!",
    [switch]$SkipWifiSetup,
    [int]$WifiConnectTimeoutSeconds = 35,
    [switch]$SingleDevice
)

$ErrorActionPreference = "Stop"

$ScriptVersion = "2026-07-03.10"
$AppPackage = "uz.neovex.iccu.kiosk"
$MainActivity = "uz.neovex.iccu.kiosk/.MainActivity"
$AdminReceiver = "uz.neovex.iccu.kiosk/.KioskDeviceAdminReceiver"
$WifiProvisionReceiver = "uz.neovex.iccu.kiosk/.WifiProvisionReceiver"
$WifiProvisionAction = "uz.neovex.iccu.kiosk.PROVISION_WIFI"
$WebViewPackage = "com.google.android.webview"
$ApkRelativePath = "app\build\outputs\apk\debug\app-debug.apk"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ApkPath = Join-Path $ProjectRoot $ApkRelativePath
$GradlewPath = Join-Path $ProjectRoot "gradlew.bat"
$PortableRoot = Join-Path $ProjectRoot "tools\.portable"
$DownloadsRoot = Join-Path $ProjectRoot "tools\.downloads"
$PlatformToolsUrl = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
$CommandLineToolsUrl = "https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip"
$Jdk17Url = "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk"
$DefaultWebViewApkUrl = "https://apks.39b7cb94d40914bac590886981b0ed6e.r2.cloudflarestorage.com/com.google.android.webview/150.0.7871.46/787104611.dda92dcf314fa7f9730b9a0d56d5890f51813998.apk?response-content-disposition=attachment%3B%20filename%3D%22Android%20System%20WebView_150.0.7871.46_apkcombo.com.apk%22&response-content-type=application%2Fvnd.android.package-archive&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Date=20260703T114144Z&X-Amz-SignedHeaders=host&X-Amz-Expires=14400&X-Amz-Credential=3cb727b4cd4780c410b780ac7caa4da3%2F20260703%2Fauto%2Fs3%2Faws4_request&X-Amz-Signature=17e5020f92c62a672eafca3df177246520ca2c2f77d2737f9990e4538d4e1c2a"
$AndroidSdkRoot = Join-Path $PortableRoot "android-sdk"
$AndroidCompileSdk = "36"
$AndroidBuildTools = "36.0.0"

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

function Get-JavaMajorVersion {
    param([string]$JavaExe)

    $result = Invoke-NativeCapture -File $JavaExe -Arguments @("-version")
    $versionText = $result.Text
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

function Install-AndroidCommandLineTools {
    $sdkManager = Join-Path $AndroidSdkRoot "cmdline-tools\latest\bin\sdkmanager.bat"
    if (Test-Path $sdkManager) {
        return $sdkManager
    }

    Ensure-Directory -Path $PortableRoot
    Ensure-Directory -Path $AndroidSdkRoot

    $zipPath = Join-Path $PortableRoot "commandlinetools-win-latest.zip"
    $extractTemp = Join-Path $PortableRoot "cmdline-tools-temp"
    $latestPath = Join-Path $AndroidSdkRoot "cmdline-tools\latest"

    if (-not (Test-Path $zipPath)) {
        Download-File -Url $CommandLineToolsUrl -OutFile $zipPath
    }

    if (Test-Path $extractTemp) {
        Remove-Item -Path $extractTemp -Recurse -Force
    }
    Expand-Zip -ZipPath $zipPath -Destination $extractTemp

    Ensure-Directory -Path (Split-Path -Parent $latestPath)
    if (Test-Path $latestPath) {
        Remove-Item -Path $latestPath -Recurse -Force
    }

    $source = Join-Path $extractTemp "cmdline-tools"
    if (-not (Test-Path $source)) {
        Fail "Android command-line tools archive extracted, but cmdline-tools folder was not found"
    }

    Move-Item -Path $source -Destination $latestPath
    Remove-Item -Path $extractTemp -Recurse -Force

    if (-not (Test-Path $sdkManager)) {
        Fail "sdkmanager.bat was not found after command-line tools setup"
    }

    return $sdkManager
}

function Get-AndroidSdkCandidate {
    if ($env:ANDROID_HOME -and (Test-Path $env:ANDROID_HOME)) {
        return $env:ANDROID_HOME
    }
    if ($env:ANDROID_SDK_ROOT -and (Test-Path $env:ANDROID_SDK_ROOT)) {
        return $env:ANDROID_SDK_ROOT
    }
    if (Test-Path "$env:LOCALAPPDATA\Android\Sdk") {
        return "$env:LOCALAPPDATA\Android\Sdk"
    }
    if (Test-Path $AndroidSdkRoot) {
        return $AndroidSdkRoot
    }
    return ""
}

function Test-AndroidSdkReady {
    param([string]$SdkRoot)

    if ($SdkRoot -eq "" -or -not (Test-Path $SdkRoot)) {
        return $false
    }

    $platform = Join-Path $SdkRoot "platforms\android-$AndroidCompileSdk\android.jar"
    $buildTools = Join-Path $SdkRoot "build-tools\$AndroidBuildTools\aapt2.exe"
    $adb = Join-Path $SdkRoot "platform-tools\adb.exe"

    return (Test-Path $platform) -and (Test-Path $buildTools) -and (Test-Path $adb)
}

function Invoke-SdkManager {
    param(
        [string]$SdkManager,
        [string[]]$Packages
    )

    $env:ANDROID_HOME = $AndroidSdkRoot
    $env:ANDROID_SDK_ROOT = $AndroidSdkRoot

    $arguments = @("--sdk_root=$AndroidSdkRoot") + $Packages
    Write-Step "$SdkManager $($arguments -join ' ')"

    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $SdkManager
    $processInfo.Arguments = ($arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join " "
    $processInfo.RedirectStandardInput = $true
    $processInfo.RedirectStandardOutput = $false
    $processInfo.RedirectStandardError = $false
    $processInfo.UseShellExecute = $false

    $process = [System.Diagnostics.Process]::Start($processInfo)
    for ($i = 0; $i -lt 80; $i++) {
        $process.StandardInput.WriteLine("y")
    }
    $process.StandardInput.Close()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0) {
        Fail "sdkmanager failed with exit code $($process.ExitCode)"
    }
}

function Write-LocalProperties {
    param([string]$SdkRoot)

    $escapedSdkPath = $SdkRoot.Replace("\", "\\").Replace(":", "\:")
    $content = "sdk.dir=$escapedSdkPath`r`n"
    Set-Content -Path (Join-Path $ProjectRoot "local.properties") -Value $content -Encoding ASCII
}

function Configure-AndroidSdk {
    $candidate = Get-AndroidSdkCandidate
    if (Test-AndroidSdkReady -SdkRoot $candidate) {
        $env:ANDROID_HOME = $candidate
        $env:ANDROID_SDK_ROOT = $candidate
        $env:PATH = (Join-Path $candidate "platform-tools") + [IO.Path]::PathSeparator + $env:PATH
        Write-LocalProperties -SdkRoot $candidate
        Write-Ok "Using Android SDK: $candidate"
        return
    }

    Write-Warn "Android SDK with platform android-$AndroidCompileSdk was not found. Downloading portable SDK into tools\.portable."
    $sdkManager = Install-AndroidCommandLineTools
    Invoke-SdkManager -SdkManager $sdkManager -Packages @(
        "platform-tools",
        "platforms;android-$AndroidCompileSdk",
        "build-tools;$AndroidBuildTools"
    )

    if (-not (Test-AndroidSdkReady -SdkRoot $AndroidSdkRoot)) {
        Fail "Android SDK setup finished, but required packages are still missing"
    }

    $env:ANDROID_HOME = $AndroidSdkRoot
    $env:ANDROID_SDK_ROOT = $AndroidSdkRoot
    $env:PATH = (Join-Path $AndroidSdkRoot "platform-tools") + [IO.Path]::PathSeparator + $env:PATH
    Write-LocalProperties -SdkRoot $AndroidSdkRoot
    Write-Ok "Using Android SDK: $AndroidSdkRoot"
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
        "$AndroidSdkRoot\platform-tools\adb.exe"
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
    $fullArguments = @("-s", $script:Serial) + $Arguments
    return Invoke-NativeCapture -File $script:AdbPath -Arguments $fullArguments
}

function Normalize-WifiSsid {
    param([string]$Ssid)

    if (-not $Ssid) {
        return ""
    }

    $normalized = $Ssid.Trim() -replace '^"|"$', ''
    if ($normalized -eq "<unknown ssid>") {
        return ""
    }

    return $normalized
}

function Get-CurrentWifiSsid {
    $status = Capture-AdbDevice -Arguments @("shell", "cmd", "wifi", "status")
    if ($status.Code -eq 0 -and $status.Text -ne "") {
        foreach ($line in $status.Lines) {
            if ($line -match 'SSID:\s*"([^"]+)"') {
                return (Normalize-WifiSsid -Ssid $Matches[1])
            }
            if ($line -match 'SSID:\s*([^,\r\n]+)') {
                return (Normalize-WifiSsid -Ssid $Matches[1])
            }
        }
    }

    $dump = Capture-AdbDevice -Arguments @("shell", "dumpsys", "wifi")
    if ($dump.Text -eq "") {
        return ""
    }

    foreach ($line in $dump.Lines) {
        if ($line -notmatch "mWifiInfo|WifiInfo") {
            continue
        }
        if ($line -match 'SSID:\s*"([^"]+)"') {
            return (Normalize-WifiSsid -Ssid $Matches[1])
        }
        if ($line -match 'SSID:\s*([^,\r\n]+)') {
            return (Normalize-WifiSsid -Ssid $Matches[1])
        }
    }

    return ""
}

function Wait-ForWifiConnected {
    param([int]$TimeoutSeconds)

    $currentSsid = ""
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 3
        $currentSsid = Get-CurrentWifiSsid
        if ($currentSsid -eq $WifiSsid) {
            Write-Ok "Wi-Fi connected: $WifiSsid"
            return $true
        }
    } while ((Get-Date) -lt $deadline)

    if ($currentSsid -ne "") {
        Write-Warn "Tablet is connected to Wi-Fi '$currentSsid', expected '$WifiSsid'"
    }

    return $false
}

function Test-WifiSetupSkipped {
    if ($SkipWifiSetup) {
        Write-Warn "Skipping Wi-Fi setup because -SkipWifiSetup was used"
        return $true
    }

    if ($WifiSsid -eq "") {
        Write-Warn "Skipping Wi-Fi setup because -WifiSsid is empty"
        return $true
    }

    return $false
}

function Ensure-WifiConnected {
    if (Test-WifiSetupSkipped) {
        return
    }

    $currentSsid = Get-CurrentWifiSsid
    if ($currentSsid -eq $WifiSsid) {
        Write-Ok "Wi-Fi already connected: $WifiSsid"
        return
    }

    Write-Step "Connecting Wi-Fi to $WifiSsid"
    $enable = Capture-AdbDevice -Arguments @("shell", "svc", "wifi", "enable")
    if ($enable.Code -ne 0 -and $enable.Text -ne "") {
        Write-Warn "Could not enable Wi-Fi with svc: $($enable.Text)"
    }
    Start-Sleep -Seconds 2

    $connect = Capture-AdbDevice -Arguments @("shell", "cmd", "wifi", "connect-network", $WifiSsid, "wpa2", $WifiPassword)
    if ($connect.Text -ne "") {
        Write-Host $connect.Text
    }

    if ($connect.Code -ne 0) {
        if ($connect.Text -match "SecurityException|does not have access to wifi commands") {
            Write-Warn "ADB shell cannot control Wi-Fi on this firmware. Will retry through the kiosk app after Device Owner is enabled."
            return
        }

        Write-Warn "ADB Wi-Fi connect command failed. Will retry through the kiosk app after Device Owner is enabled."
        return
    }

    if (Wait-ForWifiConnected -TimeoutSeconds $WifiConnectTimeoutSeconds) {
        return
    }

    Write-Warn "ADB Wi-Fi command completed, but the tablet did not connect yet. Will retry through the kiosk app after Device Owner is enabled."
}

function Ensure-WifiConnectedWithDeviceOwnerApp {
    if (Test-WifiSetupSkipped) {
        return
    }

    $currentSsid = Get-CurrentWifiSsid
    if ($currentSsid -eq $WifiSsid) {
        Write-Ok "Wi-Fi already connected: $WifiSsid"
        return
    }

    Write-Step "Connecting Wi-Fi through kiosk Device Owner app"
    $broadcast = Capture-AdbDevice -Arguments @(
        "shell",
        "am",
        "broadcast",
        "-a",
        $WifiProvisionAction,
        "-n",
        $WifiProvisionReceiver,
        "--es",
        "ssid",
        $WifiSsid,
        "--es",
        "password",
        $WifiPassword
    )

    if ($broadcast.Text -ne "") {
        Write-Host $broadcast.Text
    }
    if ($broadcast.Code -ne 0) {
        Fail "Could not send Wi-Fi provisioning broadcast to kiosk app"
    }

    if (Wait-ForWifiConnected -TimeoutSeconds $WifiConnectTimeoutSeconds) {
        return
    }

    Fail "Wi-Fi did not connect to $WifiSsid within $WifiConnectTimeoutSeconds seconds"
}

function Get-DeviceRows {
    $result = Invoke-NativeCapture -File $script:AdbPath -Arguments @("devices")
    if ($result.Code -ne 0) {
        if ($result.Text -ne "") {
            Write-Host $result.Text
        }
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

function Select-TargetDevices {
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
        return @($script:Serial)
    }

    $ready = @($rows | Where-Object { $_.State -eq "device" })
    $unauthorized = @($rows | Where-Object { $_.State -eq "unauthorized" })
    $offline = @($rows | Where-Object { $_.State -eq "offline" })

    if ($ready.Count -eq 1 -or ($ready.Count -gt 1 -and -not $SingleDevice)) {
        if ($ready.Count -gt 1) {
            Write-Ok "Using all ready tablets: $($ready.Count)"
            $ready | ForEach-Object { Write-Host "  $($_.Serial)" }
            if ($unauthorized.Count -gt 0) {
                Write-Warn "Skipping unauthorized tablet(s). Approve USB debugging and run again for them:"
                $unauthorized | ForEach-Object { Write-Host "  $($_.Serial)" }
            }
            if ($offline.Count -gt 0) {
                Write-Warn "Skipping offline tablet(s):"
                $offline | ForEach-Object { Write-Host "  $($_.Serial)" }
            }
            return @($ready | ForEach-Object { $_.Serial })
        }

        $script:Serial = $ready[0].Serial
        Write-Ok "Using tablet $($script:Serial)"
        return @($script:Serial)
    }

    if ($ready.Count -gt 1) {
        Write-Host "More than one tablet is connected:"
        $ready | ForEach-Object { Write-Host "  $($_.Serial)" }
        Fail "Run again with -Serial DEVICE_SERIAL, or omit -SingleDevice to install all ready tablets"
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

function Select-Device {
    $targets = Select-TargetDevices
    $script:Serial = $targets[0]
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

    $buildArguments = if ($NoTests) {
        @("assembleDebug")
    } else {
        @("testDebugUnitTest", "assembleDebug")
    }

    Push-Location $ProjectRoot
    try {
        Write-Step "$GradlewPath $($buildArguments -join ' ')"
        $result = Invoke-NativeCapture -File $GradlewPath -Arguments $buildArguments
        Write-Host $result.Text

        if ($result.Code -ne 0) {
            $isStaleDexFailure =
                $result.Text -match "DexArchiveMergerException" -or
                $result.Text -match "defined multiple times" -or
                $result.Text -match "project_dex_archive"

            if (-not $isStaleDexFailure) {
                Fail "Command failed: $GradlewPath $($buildArguments -join ' ')"
            }

            Write-Warn "Gradle dex cache looks stale. Retrying once with clean build."
            $cleanArguments = @("clean") + $buildArguments
            Write-Step "$GradlewPath $($cleanArguments -join ' ')"
            $cleanResult = Invoke-NativeCapture -File $GradlewPath -Arguments $cleanArguments
            Write-Host $cleanResult.Text
            if ($cleanResult.Code -ne 0) {
                Fail "Clean build failed: $GradlewPath $($cleanArguments -join ' ')"
            }
        }
    } finally {
        Pop-Location
    }

    if (-not (Test-Path $ApkPath)) {
        Fail "Build finished but APK was not found: $ApkPath"
    }

    Write-Ok "APK ready: $ApkRelativePath"
}

function Resolve-WebViewApk {
    if ($WebViewApk -ne "") {
        if (Test-Path $WebViewApk) {
            return (Resolve-Path $WebViewApk).Path
        }
        Fail "WebView APK path is not valid: $WebViewApk"
    }

    $candidates = @(
        (Join-Path $DownloadsRoot "android-system-webview.apk"),
        (Join-Path $DownloadsRoot "android-system-webview-150.apk"),
        (Join-Path $DownloadsRoot "android-system-webview-149.apk"),
        (Join-Path $ProjectRoot "tools\android-system-webview.apk")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    return ""
}

function Download-WebViewApk {
    $url = $WebViewApkUrl
    if ($url -eq "") {
        $url = $DefaultWebViewApkUrl
    }

    if ($url -eq "") {
        return ""
    }

    $outFile = Join-Path $DownloadsRoot "android-system-webview.apk"
    Download-File -Url $url -OutFile $outFile

    if (-not (Test-Path $outFile)) {
        Fail "WebView APK download finished, but file was not found: $outFile"
    }

    $size = (Get-Item $outFile).Length
    if ($size -lt 50000000) {
        Remove-Item -Path $outFile -Force -ErrorAction SilentlyContinue
        Fail "Downloaded WebView APK is too small. The download link may be expired; pass a fresh URL with -WebViewApkUrl or copy APK to tools\.downloads\android-system-webview.apk"
    }

    return (Resolve-Path $outFile).Path
}

function Get-CurrentWebViewVersion {
    $dump = Capture-AdbDevice -Arguments @("shell", "dumpsys", "webviewupdate")
    if ($dump.Text -match "Current WebView package \(name, version\): \($([regex]::Escape($WebViewPackage)),\s*([0-9][^)]+)\)") {
        return $Matches[1].Trim()
    }

    $packageDump = Capture-AdbDevice -Arguments @("shell", "dumpsys", "package", $WebViewPackage)
    if ($packageDump.Text -match "versionName=([0-9][^\s]+)") {
        return $Matches[1].Trim()
    }

    return ""
}

function Get-VersionMajor {
    param([string]$Version)

    if ($Version -match "^(\d+)") {
        return [int]$Matches[1]
    }
    return 0
}

function Install-WebView-Apk {
    param([string]$Path)

    Write-Step "Installing Android System WebView: $Path"
    $result = Capture-AdbDevice -Arguments @("install", "-r", $Path)
    Write-Host $result.Text
    if ($result.Code -eq 0) {
        return
    }

    if ($result.Text -match "closed") {
        Refresh-AdbConnection
        Write-Step "Retrying WebView install"
        $result = Capture-AdbDevice -Arguments @("install", "-r", $Path)
        Write-Host $result.Text
        if ($result.Code -eq 0) {
            return
        }

        Write-Step "Retrying WebView install with --no-streaming"
        $result = Capture-AdbDevice -Arguments @("install", "--no-streaming", "-r", $Path)
        Write-Host $result.Text
        if ($result.Code -eq 0) {
            return
        }
    }

    Fail "Android System WebView install failed"
}

function Ensure-WebViewUpdated {
    if ($SkipWebViewUpdate) {
        Write-Warn "Skipping WebView update because -SkipWebViewUpdate was used"
        return
    }

    $currentVersion = Get-CurrentWebViewVersion
    $currentMajor = Get-VersionMajor -Version $currentVersion

    if ($currentVersion -ne "" -and $currentMajor -ge $MinimumWebViewMajor) {
        Write-Ok "Android System WebView is already new enough: $currentVersion"
        return
    }

    if ($currentVersion -eq "") {
        Write-Warn "Could not read current Android System WebView version"
    } else {
        Write-Warn "Android System WebView is old: $currentVersion. Minimum required major: $MinimumWebViewMajor"
    }

    $webViewApkPath = Resolve-WebViewApk
    if ($webViewApkPath -eq "") {
        Write-Warn "WebView APK was not found locally. Downloading it into tools\.downloads."
        $webViewApkPath = Download-WebViewApk
    }

    if ($webViewApkPath -eq "") {
        Write-Host ""
        Write-Host "Put Android System WebView APK here, then run again:"
        Write-Host "  tools\.downloads\android-system-webview.apk"
        Write-Host ""
        Write-Host "Or pass a fresh direct download URL:"
        Write-Host "  tools\provision_kiosk_tablet.bat -WebViewApkUrl https://..."
        Write-Host ""
        Write-Host "For HK17 Android 10 tablets use:"
        Write-Host "  package: $WebViewPackage"
        Write-Host "  arch: arm64-v8a + armeabi-v7a"
        Write-Host "  min Android: Android 10 / API 29"
        Write-Host ""
        Fail "WebView APK is required because tablet WebView is old"
    }

    Install-WebView-Apk -Path $webViewApkPath
    Start-Sleep -Seconds 2

    $updatedVersion = Get-CurrentWebViewVersion
    $updatedMajor = Get-VersionMajor -Version $updatedVersion
    if ($updatedVersion -eq "" -or $updatedMajor -lt $MinimumWebViewMajor) {
        $dump = Capture-AdbDevice -Arguments @("shell", "dumpsys", "webviewupdate")
        Write-Host $dump.Text
        Fail "WebView update did not become active"
    }

    Write-Ok "Android System WebView updated: $updatedVersion"
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
    if (Test-OurAppIsDeviceOwner) {
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

    if ($result.Text -match "device owner is already set") {
        if (Test-OurAppIsDeviceOwner) {
            Write-Ok "Device Owner already set to $AppPackage"
            return
        }

        $ownerDetails = Get-DeviceOwnerDetails
        Write-Host ""
        Write-Host "Another Device Owner is already set on this tablet:"
        Write-Host $ownerDetails
        Write-Host ""
        Write-Host "Android does not allow replacing another Device Owner from a normal APK/ADB install."
        Write-Host "To install this kiosk as Device Owner, factory reset the tablet, do not add accounts, enable USB debugging, then run this script again."
        Fail "Cannot replace existing Device Owner"
    }

    Write-Host ""
    Write-Host "Device Owner setup failed. Most common fixes:"
    Write-Host "- Remove Google/account(s) from the tablet"
    Write-Host "- Factory reset the tablet, do not add an account, enable USB debugging, then run this script"
    Write-Host "- Make sure the APK was installed before Device Owner setup"
    Fail "Cannot continue without Device Owner"
}

function Get-DeviceOwnerDetails {
    $dpmOwner = Capture-AdbDevice -Arguments @("shell", "dpm", "get-device-owner")
    $policyDump = Capture-AdbDevice -Arguments @("shell", "dumpsys", "device_policy")

    $lines = @()
    if ($dpmOwner.Text -ne "") {
        $lines += $dpmOwner.Text
    }
    if ($policyDump.Text -ne "") {
        $interesting = $policyDump.Lines |
            Where-Object {
                $_ -match "Device Owner" -or
                $_ -match "device owner" -or
                $_ -match "admin=" -or
                $_ -match "ComponentInfo" -or
                $_ -match "mDeviceOwner"
            } |
            Select-Object -First 20
        $lines += $interesting
    }

    if ($lines.Count -eq 0) {
        return "Unable to read owner details. Run: adb shell dpm get-device-owner"
    }
    return ($lines -join "`n")
}

function Test-OurAppIsDeviceOwner {
    $ownerDetails = Get-DeviceOwnerDetails
    return $ownerDetails -match [regex]::Escape($AppPackage)
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

function Provision-CurrentDevice {
    Ensure-WifiConnected
    Ensure-WebViewUpdated
    Build-Apk
    Install-Apk
    Ensure-DeviceOwner
    Ensure-WifiConnectedWithDeviceOwnerApp
    Configure-Kiosk
    Launch-App
    Verify-Kiosk
}

function Invoke-SingleDeviceProvisioning {
    param([string]$TargetSerial)

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $PSCommandPath,
        "-Serial",
        $TargetSerial,
        "-SkipBuild",
        "-SingleDevice",
        "-MinimumWebViewMajor",
        "$MinimumWebViewMajor",
        "-WifiSsid",
        $WifiSsid,
        "-WifiPassword",
        $WifiPassword,
        "-WifiConnectTimeoutSeconds",
        "$WifiConnectTimeoutSeconds"
    )

    if ($NoTests) { $arguments += "-NoTests" }
    if ($NoDownloads) { $arguments += "-NoDownloads" }
    if ($SkipWebViewUpdate) { $arguments += "-SkipWebViewUpdate" }
    if ($SkipWifiSetup) { $arguments += "-SkipWifiSetup" }
    if ($WebViewApk -ne "") {
        $arguments += @("-WebViewApk", $WebViewApk)
    }
    if ($WebViewApkUrl -ne "") {
        $arguments += @("-WebViewApkUrl", $WebViewApkUrl)
    }

    Write-Step "Provisioning tablet $TargetSerial"
    $code = Invoke-NativeStream -File "powershell.exe" -Arguments $arguments
    return $code
}

$script:Serial = $Serial
Write-Host "ICCU provisioning script version: $ScriptVersion" -ForegroundColor White
Configure-Java
Configure-AndroidSdk

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
if ($SkipWebViewUpdate) {
    Write-Host "WebView update: skipped"
} else {
    Write-Host "WebView minimum major: $MinimumWebViewMajor"
}
if ($SkipWifiSetup) {
    Write-Host "Wi-Fi setup: skipped"
} else {
    Write-Host "Wi-Fi SSID: $WifiSsid"
}
Write-Host ""

$targets = @(Select-TargetDevices)

if ($targets.Count -gt 1 -and -not $SingleDevice) {
    Build-Apk

    $results = @()
    foreach ($target in $targets) {
        Write-Host ""
        Write-Host "================ TABLET $target ================" -ForegroundColor White
        $code = Invoke-SingleDeviceProvisioning -TargetSerial $target
        $results += [PSCustomObject]@{
            Serial = $target
            Code = $code
            Status = if ($code -eq 0) { "OK" } else { "FAILED" }
        }
    }

    Write-Host ""
    Write-Host "Provisioning summary:" -ForegroundColor White
    $results | ForEach-Object {
        if ($_.Code -eq 0) {
            Write-Host "OK: $($_.Serial)" -ForegroundColor Green
        } else {
            Write-Host "FAILED: $($_.Serial) (exit $($_.Code))" -ForegroundColor Red
        }
    }

    $failed = @($results | Where-Object { $_.Code -ne 0 })
    if ($failed.Count -gt 0) {
        Fail "$($failed.Count) tablet(s) failed provisioning"
    }

    Write-Host ""
    Write-Host "DONE: $($results.Count) tablet(s) are ready for kiosk use." -ForegroundColor Green
    exit 0
}

$script:Serial = $targets[0]
Provision-CurrentDevice

Write-Host ""
Write-Host "DONE: tablet $($script:Serial) is ready for kiosk use." -ForegroundColor Green
