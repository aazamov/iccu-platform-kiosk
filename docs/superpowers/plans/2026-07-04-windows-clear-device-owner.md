# Windows Clear Device Owner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Windows provisioning uninstall a kiosk app that was installed from macOS by asking the installed app to clear its own Device Owner state first.

**Architecture:** The Android app already exposes `DeviceOwnerControlReceiver` with action `uz.neovex.iccu.kiosk.CLEAR_DEVICE_OWNER`. The Windows PowerShell provisioning script will use that receiver before `adb uninstall`, mirroring the macOS shell script behavior.

**Tech Stack:** Android Kotlin app, ADB, PowerShell provisioning script, Gradle.

## Global Constraints

- Package name stays `uz.neovex.iccu.kiosk`.
- Device Owner clear action is `uz.neovex.iccu.kiosk.CLEAR_DEVICE_OWNER`.
- Device Owner control receiver component is `uz.neovex.iccu.kiosk/.DeviceOwnerControlReceiver`.
- Windows script must still fall back to normal APK update if Android blocks uninstall.
- If signature mismatch remains and uninstall is blocked by Device Policy Manager, script must show a factory reset instruction.

---

### Task 1: Mirror macOS Device Owner Removal In Windows Script

**Files:**
- Modify: `tools/provision_kiosk_tablet.ps1`

**Interfaces:**
- Consumes: `Capture-AdbDevice -Arguments @(...)`, `Test-OurAppIsDeviceOwner`, `Write-Step`, `Write-Ok`, `Write-Warn`, `Fail`.
- Produces: `Remove-ExistingKioskPackageForFreshInstall` that broadcasts `CLEAR_DEVICE_OWNER`, waits up to 15 seconds, then uninstalls.

- [x] **Step 1: Add Windows constants**

Add:

```powershell
$DeviceOwnerControlReceiver = "uz.neovex.iccu.kiosk/.DeviceOwnerControlReceiver"
$DeviceOwnerClearAction = "uz.neovex.iccu.kiosk.CLEAR_DEVICE_OWNER"
```

- [x] **Step 2: Request app-side Device Owner removal before uninstall**

Inside `Remove-ExistingKioskPackageForFreshInstall`, before `dpm remove-active-admin`, call:

```powershell
if (Test-OurAppIsDeviceOwner) {
    Write-Step "Requesting kiosk app to clear Device Owner"
    $result = Capture-AdbDevice -Arguments @("shell", "am", "broadcast", "-a", $DeviceOwnerClearAction, "-n", $DeviceOwnerControlReceiver)
    if ($result.Text -ne "") {
        Write-Host $result.Text
    }
    if ($result.Code -ne 0) {
        Write-Warn "Installed kiosk app may be too old to clear Device Owner itself."
    } else {
        $deadline = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $deadline) {
            if (-not (Test-OurAppIsDeviceOwner)) {
                Write-Ok "Device Owner removed by kiosk app"
                break
            }
            Start-Sleep -Seconds 1
        }
    }
}
```

- [x] **Step 3: Verify**

Run:

```bash
./gradlew testDebugUnitTest assembleDebug
```

Expected: `BUILD SUCCESSFUL`.

- [x] **Step 4: Commit and push**

Run:

```bash
git add tools/provision_kiosk_tablet.ps1 docs/superpowers/plans/2026-07-04-windows-clear-device-owner.md
git commit -m "Allow Windows provisioning to clear kiosk device owner"
git push
```
