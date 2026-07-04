# In-App Wi-Fi Kiosk Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an in-app Wi-Fi control panel that lets users enable/disable Wi-Fi, scan networks, enter a password, and connect without leaving kiosk mode.

**Architecture:** Keep Android Wi-Fi operations in a focused controller and keep `MainActivity` responsible only for UI wiring and kiosk enforcement. The Wi-Fi panel is a normal view inside the existing activity, so no Android Settings intents are started.

**Tech Stack:** Kotlin, Android SDK 36, Android `WifiManager`, `ConnectivityManager`, JUnit 4 unit tests, existing native Android view code.

## Global Constraints

- The app must not open Android Settings for Wi-Fi.
- Wi-Fi actions must not call `stopLockTask()` or `stopKioskMode()`.
- The app must remain in `mLockTaskModeState=LOCKED` on Device Owner tablets.
- PIN `2026` remains only for exiting the kiosk app.
- The UI must stay compact and visually close to the current header: dark translucent panel, gold active controls, muted inactive state.
- No new external dependencies.

---

### Task 1: Wi-Fi Model And Security Parsing

**Files:**
- Create: `app/src/main/java/uz/neovex/iccu/kiosk/WifiNetworkInfo.kt`
- Create: `app/src/test/java/uz/neovex/iccu/kiosk/WifiNetworkInfoTest.kt`

**Interfaces:**
- Produces: `data class WifiNetworkInfo(val ssid: String, val signalLevel: Int, val secured: Boolean, val connected: Boolean)`
- Produces: `object WifiSecurityParser { fun isSecured(capabilities: String): Boolean }`

- [ ] **Step 1: Write the failing test**

```kotlin
package uz.neovex.iccu.kiosk

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WifiNetworkInfoTest {
    @Test
    fun detectsSecuredNetworks() {
        assertTrue(WifiSecurityParser.isSecured("[WPA2-PSK-CCMP][ESS]"))
        assertTrue(WifiSecurityParser.isSecured("[WPA-PSK-CCMP][WPA2-PSK-CCMP][ESS]"))
        assertTrue(WifiSecurityParser.isSecured("[SAE][ESS]"))
        assertTrue(WifiSecurityParser.isSecured("[WEP][ESS]"))
    }

    @Test
    fun detectsOpenNetworks() {
        assertFalse(WifiSecurityParser.isSecured("[ESS]"))
        assertFalse(WifiSecurityParser.isSecured(""))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./gradlew testDebugUnitTest --tests 'uz.neovex.iccu.kiosk.WifiNetworkInfoTest'`

Expected: FAIL because `WifiSecurityParser` is not defined.

- [ ] **Step 3: Write minimal implementation**

```kotlin
package uz.neovex.iccu.kiosk

data class WifiNetworkInfo(
    val ssid: String,
    val signalLevel: Int,
    val secured: Boolean,
    val connected: Boolean,
)

object WifiSecurityParser {
    fun isSecured(capabilities: String): Boolean {
        val normalized = capabilities.uppercase()
        return listOf("WPA", "WEP", "SAE", "EAP").any { token -> normalized.contains(token) }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./gradlew testDebugUnitTest --tests 'uz.neovex.iccu.kiosk.WifiNetworkInfoTest'`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/src/main/java/uz/neovex/iccu/kiosk/WifiNetworkInfo.kt app/src/test/java/uz/neovex/iccu/kiosk/WifiNetworkInfoTest.kt
git commit -m "Add Wi-Fi network model"
```

### Task 2: Wi-Fi Result Mapping

**Files:**
- Create: `app/src/main/java/uz/neovex/iccu/kiosk/WifiConnectionResult.kt`
- Create: `app/src/test/java/uz/neovex/iccu/kiosk/WifiConnectionResultTest.kt`

**Interfaces:**
- Produces: `sealed class WifiConnectionResult`
- Produces: `object WifiOperationMessages { fun blocked(): WifiConnectionResult.Failure; fun failed(action: String): WifiConnectionResult.Failure }`

- [ ] **Step 1: Write the failing test**

```kotlin
package uz.neovex.iccu.kiosk

import org.junit.Assert.assertEquals
import org.junit.Test

class WifiConnectionResultTest {
    @Test
    fun mapsBlockedOperationToSafeMessage() {
        val result = WifiOperationMessages.blocked()
        assertEquals("Wi-Fi action blocked by tablet firmware", result.message)
    }

    @Test
    fun mapsFailedOperationToSafeMessage() {
        val result = WifiOperationMessages.failed("connect")
        assertEquals("Could not connect Wi-Fi", result.message)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./gradlew testDebugUnitTest --tests 'uz.neovex.iccu.kiosk.WifiConnectionResultTest'`

Expected: FAIL because `WifiOperationMessages` is not defined.

- [ ] **Step 3: Write minimal implementation**

```kotlin
package uz.neovex.iccu.kiosk

sealed class WifiConnectionResult {
    data object Success : WifiConnectionResult()
    data class Failure(val message: String) : WifiConnectionResult()
}

object WifiOperationMessages {
    fun blocked(): WifiConnectionResult.Failure =
        WifiConnectionResult.Failure("Wi-Fi action blocked by tablet firmware")

    fun failed(action: String): WifiConnectionResult.Failure =
        WifiConnectionResult.Failure("Could not $action Wi-Fi")
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./gradlew testDebugUnitTest --tests 'uz.neovex.iccu.kiosk.WifiConnectionResultTest'`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/src/main/java/uz/neovex/iccu/kiosk/WifiConnectionResult.kt app/src/test/java/uz/neovex/iccu/kiosk/WifiConnectionResultTest.kt
git commit -m "Add Wi-Fi operation results"
```

### Task 3: Wi-Fi Controller

**Files:**
- Create: `app/src/main/java/uz/neovex/iccu/kiosk/KioskWifiController.kt`
- Modify: `app/src/main/AndroidManifest.xml`
- Test: `./gradlew testDebugUnitTest assembleDebug`

**Interfaces:**
- Consumes: `WifiNetworkInfo`, `WifiSecurityParser`, `WifiConnectionResult`
- Produces: `class KioskWifiController(context: Context) { fun isWifiEnabled(): Boolean; fun setWifiEnabled(enabled: Boolean): WifiConnectionResult; fun currentSsid(): String?; fun scanNetworks(): List<WifiNetworkInfo>; fun connect(network: WifiNetworkInfo, password: String): WifiConnectionResult }`

- [ ] **Step 1: Add required location permission**

Modify `app/src/main/AndroidManifest.xml` to add:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

This is needed for Wi-Fi scan results on Android 10-class devices.

- [ ] **Step 2: Create controller**

Create `app/src/main/java/uz/neovex/iccu/kiosk/KioskWifiController.kt`:

```kotlin
package uz.neovex.iccu.kiosk

import android.annotation.SuppressLint
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager

class KioskWifiController(context: Context) {
    private val appContext = context.applicationContext
    private val wifiManager = appContext.getSystemService(WifiManager::class.java)
    private val connectivityManager = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    fun isWifiEnabled(): Boolean = wifiManager.isWifiEnabled

    @Suppress("DEPRECATION")
    fun setWifiEnabled(enabled: Boolean): WifiConnectionResult =
        try {
            if (wifiManager.setWifiEnabled(enabled)) {
                WifiConnectionResult.Success
            } else {
                WifiOperationMessages.failed(if (enabled) "enable" else "disable")
            }
        } catch (_: SecurityException) {
            WifiOperationMessages.blocked()
        } catch (_: RuntimeException) {
            WifiOperationMessages.failed(if (enabled) "enable" else "disable")
        }

    @SuppressLint("MissingPermission")
    fun scanNetworks(): List<WifiNetworkInfo> {
        runCatching { wifiManager.startScan() }
        val connectedSsid = currentSsid()
        return wifiManager.scanResults
            .filter { it.SSID.isNotBlank() }
            .groupBy { it.SSID }
            .map { (_, results) -> results.maxBy { it.level } }
            .sortedByDescending { it.level }
            .map { result ->
                WifiNetworkInfo(
                    ssid = result.SSID,
                    signalLevel = WifiManager.calculateSignalLevel(result.level, 4),
                    secured = WifiSecurityParser.isSecured(result.capabilities),
                    connected = result.SSID == connectedSsid,
                )
            }
    }

    fun currentSsid(): String? {
        val network = connectivityManager.activeNetwork ?: return null
        val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return null
        if (!capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return null

        return wifiManager.connectionInfo?.ssid
            ?.trim()
            ?.removePrefix("\"")
            ?.removeSuffix("\"")
            ?.takeIf { it.isNotBlank() && it != "<unknown ssid>" }
    }

    @Suppress("DEPRECATION")
    fun connect(network: WifiNetworkInfo, password: String): WifiConnectionResult =
        try {
            val configuration = WifiConfiguration().apply {
                SSID = quoteWifiValue(network.ssid)
                status = WifiConfiguration.Status.ENABLED
                if (network.secured) {
                    preSharedKey = quoteWifiValue(password)
                    allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
                    allowedProtocols.set(WifiConfiguration.Protocol.RSN)
                    allowedProtocols.set(WifiConfiguration.Protocol.WPA)
                    allowedPairwiseCiphers.set(WifiConfiguration.PairwiseCipher.CCMP)
                    allowedPairwiseCiphers.set(WifiConfiguration.PairwiseCipher.TKIP)
                    allowedGroupCiphers.set(WifiConfiguration.GroupCipher.CCMP)
                    allowedGroupCiphers.set(WifiConfiguration.GroupCipher.TKIP)
                } else {
                    allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE)
                }
            }

            val existingNetworkId = wifiManager.configuredNetworks
                ?.firstOrNull { normalizeWifiValue(it.SSID) == network.ssid }
                ?.networkId
                ?: -1

            val networkId = if (existingNetworkId >= 0) {
                configuration.networkId = existingNetworkId
                wifiManager.updateNetwork(configuration)
            } else {
                wifiManager.addNetwork(configuration)
            }

            if (networkId < 0) return WifiOperationMessages.failed("connect")

            wifiManager.disconnect()
            val enabled = wifiManager.enableNetwork(networkId, true)
            val reconnecting = wifiManager.reconnect()
            if (enabled && reconnecting) WifiConnectionResult.Success else WifiOperationMessages.failed("connect")
        } catch (_: SecurityException) {
            WifiOperationMessages.blocked()
        } catch (_: RuntimeException) {
            WifiOperationMessages.failed("connect")
        }

    private fun quoteWifiValue(value: String): String = "\"${value.replace("\"", "\\\"")}\""

    private fun normalizeWifiValue(value: String?): String = value
        ?.trim()
        ?.removePrefix("\"")
        ?.removeSuffix("\"")
        .orEmpty()
}
```

- [ ] **Step 3: Build**

Run: `./gradlew testDebugUnitTest assembleDebug`

Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Commit**

```bash
git add app/src/main/AndroidManifest.xml app/src/main/java/uz/neovex/iccu/kiosk/KioskWifiController.kt
git commit -m "Add kiosk Wi-Fi controller"
```

### Task 4: In-App Wi-Fi Panel UI

**Files:**
- Modify: `app/src/main/java/uz/neovex/iccu/kiosk/MainActivity.kt`
- Test: `./gradlew testDebugUnitTest assembleDebug`

**Interfaces:**
- Consumes: `KioskWifiController`, `WifiNetworkInfo`, `WifiConnectionResult`
- Produces: Wi-Fi icon opens a full in-app control panel and never opens Android Settings.

- [ ] **Step 1: Add fields to `MainActivity`**

Add these fields near existing Wi-Fi fields:

```kotlin
private lateinit var wifiController: KioskWifiController
private lateinit var wifiNetworksContainer: LinearLayout
private lateinit var wifiPasswordInput: EditText
private lateinit var wifiMessageText: TextView
private lateinit var wifiPowerButton: TextView
private var selectedWifiNetwork: WifiNetworkInfo? = null
```

- [ ] **Step 2: Initialize controller**

In `onCreate`, after `adminComponent` is initialized:

```kotlin
wifiController = KioskWifiController(this)
```

- [ ] **Step 3: Replace compact status panel content with controls**

In `createLayout`, expand `wifiPanel` to include:

```kotlin
wifiPowerButton = TextView(this).apply {
    textSize = 12f
    gravity = Gravity.CENTER
    setTextColor(ACTIVE_CONTROL_COLOR)
    includeFontPadding = false
    setOnClickListener { toggleWifiPower() }
}

val wifiRefreshButton = TextView(this).apply {
    text = "Refresh"
    textSize = 12f
    gravity = Gravity.CENTER
    setTextColor(ACTIVE_CONTROL_COLOR)
    includeFontPadding = false
    setOnClickListener { refreshWifiNetworks() }
}

wifiNetworksContainer = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
}

wifiPasswordInput = EditText(this).apply {
    hint = "Password"
    textSize = 12f
    setSingleLine(true)
    visibility = View.GONE
}

val wifiConnectButton = TextView(this).apply {
    text = "Connect"
    textSize = 12f
    gravity = Gravity.CENTER
    setTextColor(ACTIVE_CONTROL_COLOR)
    includeFontPadding = false
    setOnClickListener { connectSelectedWifiNetwork() }
}

wifiMessageText = TextView(this).apply {
    textSize = 11f
    setTextColor(INACTIVE_CONTROL_COLOR)
    includeFontPadding = false
}
```

Build the panel as a vertical layout with header row, status text, network rows, password input, connect button, and message text. Use the existing close button behavior.

- [ ] **Step 4: Add panel behavior methods**

Add these methods to `MainActivity`:

```kotlin
private fun refreshWifiPanel() {
    updateWifiStatus()
    wifiPowerButton.text = if (wifiController.isWifiEnabled()) "Wi-Fi ON" else "Wi-Fi OFF"
    wifiStatusText.text = wifiController.currentSsid()?.let { "Connected: $it" } ?: "Wi-Fi offline"
    refreshWifiNetworks()
}

private fun refreshWifiNetworks() {
    if (!::wifiNetworksContainer.isInitialized) return
    wifiNetworksContainer.removeAllViews()
    val networks = wifiController.scanNetworks().take(6)
    networks.forEach { network ->
        wifiNetworksContainer.addView(createWifiNetworkRow(network))
    }
}

private fun createWifiNetworkRow(network: WifiNetworkInfo): View =
    TextView(this).apply {
        text = buildString {
            append(if (network.connected) "* " else "")
            append(network.ssid)
            append("  ")
            append(if (network.secured) "lock" else "open")
            append("  ")
            append("${network.signalLevel}/3")
        }
        textSize = 12f
        setTextColor(if (network.connected) ACTIVE_CONTROL_COLOR else Color.WHITE)
        includeFontPadding = false
        setPadding(dp(6), dp(5), dp(6), dp(5))
        setOnClickListener {
            selectedWifiNetwork = network
            wifiPasswordInput.visibility = if (network.secured) View.VISIBLE else View.GONE
            wifiMessageText.text = network.ssid
        }
    }

private fun toggleWifiPower() {
    enforceKioskAfterWifiAction()
    val result = wifiController.setWifiEnabled(!wifiController.isWifiEnabled())
    showWifiResult(result)
    refreshWifiPanel()
    enforceKioskAfterWifiAction()
}

private fun connectSelectedWifiNetwork() {
    enforceKioskAfterWifiAction()
    val network = selectedWifiNetwork ?: run {
        wifiMessageText.text = "Select Wi-Fi network"
        return
    }
    val result = wifiController.connect(network, wifiPasswordInput.text.toString())
    showWifiResult(result)
    refreshWifiPanel()
    enforceKioskAfterWifiAction()
}

private fun showWifiResult(result: WifiConnectionResult) {
    wifiMessageText.text = when (result) {
        WifiConnectionResult.Success -> "Wi-Fi action started"
        is WifiConnectionResult.Failure -> result.message
    }
}

private fun enforceKioskAfterWifiAction() {
    enterFullscreen()
    configureDeviceOwnerPolicies()
    startKioskMode()
}
```

- [ ] **Step 5: Update `toggleWifiPanel`**

When opening the panel, call:

```kotlin
refreshWifiPanel()
```

Keep `KioskActionPolicy.shouldStopKioskFor(KioskAction.WIFI_PANEL)` false and do not add Settings intents.

- [ ] **Step 6: Build**

Run: `./gradlew testDebugUnitTest assembleDebug`

Expected: BUILD SUCCESSFUL.

- [ ] **Step 7: Commit**

```bash
git add app/src/main/java/uz/neovex/iccu/kiosk/MainActivity.kt
git commit -m "Add in-app Wi-Fi control panel"
```

### Task 5: Device Verification And Install

**Files:**
- No source files unless verification finds a bug.

**Interfaces:**
- Consumes: built APK from Task 4.
- Produces: verified behavior on connected tablet.

- [ ] **Step 1: Install and launch**

Run:

```bash
adb devices -l
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am force-stop uz.neovex.iccu.kiosk
adb shell monkey -p uz.neovex.iccu.kiosk -c android.intent.category.LAUNCHER 1
```

Expected: install `Success`, app launches.

- [ ] **Step 2: Verify kiosk lock**

Run:

```bash
adb shell dumpsys activity activities | rg -n "mLockTaskModeState|mResumedActivity|ResumedActivity|uz.neovex.iccu.kiosk|com.android.settings"
```

Expected:

- `mLockTaskModeState=LOCKED`
- resumed activity is `uz.neovex.iccu.kiosk/.MainActivity`
- `com.android.settings` is not the resumed activity

- [ ] **Step 3: Stress Wi-Fi button**

Run six taps near the Wi-Fi button:

```bash
for i in 1 2 3 4 5 6; do adb shell input tap 780 18; sleep 0.2; done
adb shell dumpsys activity activities | rg -n "mLockTaskModeState|mResumedActivity|ResumedActivity|uz.neovex.iccu.kiosk|com.android.settings"
```

Expected:

- `mLockTaskModeState=LOCKED`
- resumed activity is `uz.neovex.iccu.kiosk/.MainActivity`

- [ ] **Step 4: Manual Wi-Fi test on tablet**

On the tablet:

- Open Wi-Fi panel.
- Tap refresh.
- Select `Neo_wifi`.
- Enter `12345678!!`.
- Tap Connect.
- Confirm the site reloads or remains available.
- Confirm users cannot enter Android Settings or launcher.

- [ ] **Step 5: Final commit if verification fixes were needed**

If source changes were made during verification:

```bash
git add app/src/main/java/uz/neovex/iccu/kiosk app/src/test/java/uz/neovex/iccu/kiosk app/src/main/AndroidManifest.xml
git commit -m "Verify in-app Wi-Fi kiosk control"
```
