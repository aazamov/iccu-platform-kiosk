# Custom Wi-Fi Keyboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Wi-Fi password `EditText` with a custom in-app keyboard so users can enter Wi-Fi passwords without opening the Android system keyboard.

**Architecture:** Add a small tested password-input state object for password, mode, and shift behavior. Update `MainActivity` to render a masked password display and custom keyboard rows inside the existing Wi-Fi panel, with all Wi-Fi paths staying inside lock task mode.

**Tech Stack:** Kotlin, Android SDK 36, native Android Views, JUnit 4 unit tests.

## Global Constraints

- The implementation must not use Android Settings intents.
- The implementation must not use `InputMethodManager.showSoftInput`.
- The implementation must not use a focusable `EditText` for Wi-Fi password entry.
- The implementation must not call `stopKioskMode()` or `stopLockTask()` from any Wi-Fi path.
- The PIN exit flow is unchanged.
- The custom keyboard must stay inside the same Wi-Fi panel view hierarchy.
- No new external dependencies.

---

### Task 1: Password Keyboard State

**Files:**
- Create: `app/src/main/java/uz/neovex/iccu/kiosk/WifiPasswordInputState.kt`
- Create: `app/src/test/java/uz/neovex/iccu/kiosk/WifiPasswordInputStateTest.kt`

**Interfaces:**
- Produces: `enum class WifiKeyboardMode { LETTERS, SYMBOLS }`
- Produces: `class WifiPasswordInputState`
- Produces: `fun appendKey(label: String)`
- Produces: `fun backspace()`
- Produces: `fun clear()`
- Produces: `fun toggleShift()`
- Produces: `fun toggleMode()`
- Produces: `fun maskedPassword(): String`
- Produces: `val password: String`
- Produces: `val mode: WifiKeyboardMode`
- Produces: `val shifted: Boolean`

- [ ] **Step 1: Write failing test**

Create `app/src/test/java/uz/neovex/iccu/kiosk/WifiPasswordInputStateTest.kt`:

```kotlin
package uz.neovex.iccu.kiosk

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WifiPasswordInputStateTest {
    @Test
    fun appendsLettersAndMasksPassword() {
        val state = WifiPasswordInputState()

        state.appendKey("n")
        state.appendKey("e")
        state.appendKey("o")

        assertEquals("neo", state.password)
        assertEquals("•••", state.maskedPassword())
    }

    @Test
    fun shiftUppercasesLetters() {
        val state = WifiPasswordInputState()

        state.toggleShift()
        state.appendKey("n")

        assertEquals("N", state.password)
        assertTrue(state.shifted)
    }

    @Test
    fun backspaceRemovesOneCharacter() {
        val state = WifiPasswordInputState()

        state.appendKey("1")
        state.appendKey("2")
        state.backspace()

        assertEquals("1", state.password)
    }

    @Test
    fun clearEmptiesPassword() {
        val state = WifiPasswordInputState()

        state.appendKey("a")
        state.clear()

        assertEquals("", state.password)
        assertEquals("", state.maskedPassword())
    }

    @Test
    fun symbolsModeAcceptsWifiPasswordSymbols() {
        val state = WifiPasswordInputState()

        state.toggleMode()
        state.appendKey("!")
        state.appendKey("@")
        state.appendKey("-")

        assertEquals(WifiKeyboardMode.SYMBOLS, state.mode)
        assertEquals("!@-", state.password)
    }

    @Test
    fun toggleModeReturnsToLettersAndClearsShift() {
        val state = WifiPasswordInputState()

        state.toggleShift()
        state.toggleMode()
        state.toggleMode()

        assertEquals(WifiKeyboardMode.LETTERS, state.mode)
        assertFalse(state.shifted)
    }
}
```

- [ ] **Step 2: Run test and verify it fails**

Run:

```bash
./gradlew testDebugUnitTest --tests 'uz.neovex.iccu.kiosk.WifiPasswordInputStateTest'
```

Expected: FAIL because `WifiPasswordInputState` and `WifiKeyboardMode` are not defined.

- [ ] **Step 3: Implement state**

Create `app/src/main/java/uz/neovex/iccu/kiosk/WifiPasswordInputState.kt`:

```kotlin
package uz.neovex.iccu.kiosk

enum class WifiKeyboardMode {
    LETTERS,
    SYMBOLS,
}

class WifiPasswordInputState {
    private val buffer = StringBuilder()
    var mode: WifiKeyboardMode = WifiKeyboardMode.LETTERS
        private set
    var shifted: Boolean = false
        private set

    val password: String
        get() = buffer.toString()

    fun appendKey(label: String) {
        val value = if (mode == WifiKeyboardMode.LETTERS && label.length == 1 && label[0].isLetter()) {
            if (shifted) label.uppercase() else label.lowercase()
        } else {
            label
        }
        buffer.append(value)
    }

    fun backspace() {
        if (buffer.isNotEmpty()) {
            buffer.deleteAt(buffer.lastIndex)
        }
    }

    fun clear() {
        buffer.clear()
    }

    fun toggleShift() {
        shifted = !shifted
    }

    fun toggleMode() {
        mode = if (mode == WifiKeyboardMode.LETTERS) WifiKeyboardMode.SYMBOLS else WifiKeyboardMode.LETTERS
        shifted = false
    }

    fun maskedPassword(): String = "•".repeat(buffer.length)
}
```

- [ ] **Step 4: Run test and verify it passes**

Run:

```bash
./gradlew testDebugUnitTest --tests 'uz.neovex.iccu.kiosk.WifiPasswordInputStateTest'
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 5: Commit**

Run:

```bash
git restore app/build build
git add app/src/main/java/uz/neovex/iccu/kiosk/WifiPasswordInputState.kt app/src/test/java/uz/neovex/iccu/kiosk/WifiPasswordInputStateTest.kt
git commit -m "Add Wi-Fi password keyboard state"
```

### Task 2: Custom Keyboard UI In MainActivity

**Files:**
- Modify: `app/src/main/java/uz/neovex/iccu/kiosk/MainActivity.kt`

**Interfaces:**
- Consumes: `WifiPasswordInputState`
- Consumes: `WifiKeyboardMode`
- Produces: Wi-Fi panel with non-focusable password display and custom keyboard.

- [ ] **Step 1: Add fields**

Modify `MainActivity` Wi-Fi fields:

```kotlin
private lateinit var wifiPasswordDisplay: TextView
private lateinit var wifiKeyboardContainer: LinearLayout
private val wifiPasswordState = WifiPasswordInputState()
```

Remove the `wifiPasswordInput: EditText` field and remove Wi-Fi password `EditText` creation.

- [ ] **Step 2: Build password display**

In `createLayout`, replace `wifiPasswordInput = EditText(...)` with:

```kotlin
wifiPasswordDisplay = TextView(this).apply {
    text = "Password"
    textSize = 12f
    gravity = Gravity.CENTER_VERTICAL
    setTextColor(Color.WHITE)
    setPadding(dp(8), dp(6), dp(8), dp(6))
    setBackgroundColor(Color.argb(130, 2, 18, 12))
    visibility = View.GONE
}
```

- [ ] **Step 3: Build custom keyboard container**

In `createLayout`, add:

```kotlin
wifiKeyboardContainer = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
    visibility = View.GONE
}
```

Add `wifiPasswordDisplay` and `wifiKeyboardContainer` to `wifiPanel` before the Connect button.

- [ ] **Step 4: Add keyboard rendering methods**

Add to `MainActivity`:

```kotlin
private fun renderWifiKeyboard() {
    if (!::wifiKeyboardContainer.isInitialized) return
    wifiKeyboardContainer.removeAllViews()
    val rows = if (wifiPasswordState.mode == WifiKeyboardMode.LETTERS) {
        listOf(
            listOf("q", "w", "e", "r", "t", "y", "u", "i", "o", "p"),
            listOf("a", "s", "d", "f", "g", "h", "j", "k", "l"),
            listOf("Shift", "z", "x", "c", "v", "b", "n", "m", "Backspace"),
            listOf("123", "Clear", "Done"),
        )
    } else {
        listOf(
            listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0"),
            listOf("!", "@", "#", "$", "%", "&", "*", "_", "-", "."),
            listOf("ABC", "/", ":", ";", "?", "+", "=", "Backspace"),
            listOf("Clear", "Done"),
        )
    }
    rows.forEach { labels ->
        wifiKeyboardContainer.addView(createWifiKeyboardRow(labels))
    }
}

private fun createWifiKeyboardRow(labels: List<String>): LinearLayout =
    LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        labels.forEach { label ->
            addView(
                createWifiKeyboardKey(label),
                LinearLayout.LayoutParams(0, dp(28), 1f).apply {
                    setMargins(dp(1), dp(1), dp(1), dp(1))
                },
            )
        }
    }

private fun createWifiKeyboardKey(label: String): TextView =
    TextView(this).apply {
        text = if (label == "Shift" && wifiPasswordState.shifted) "SHIFT" else label
        textSize = if (label.length > 3) 9f else 11f
        gravity = Gravity.CENTER
        includeFontPadding = false
        setTextColor(ACTIVE_CONTROL_COLOR)
        setBackgroundColor(Color.argb(180, 10, 48, 30))
        setOnClickListener { handleWifiKeyboardKey(label) }
    }

private fun handleWifiKeyboardKey(label: String) {
    when (label) {
        "Shift" -> wifiPasswordState.toggleShift()
        "123", "ABC" -> wifiPasswordState.toggleMode()
        "Backspace" -> wifiPasswordState.backspace()
        "Clear" -> wifiPasswordState.clear()
        "Done" -> wifiKeyboardContainer.visibility = View.GONE
        else -> wifiPasswordState.appendKey(label)
    }
    updateWifiPasswordDisplay()
    renderWifiKeyboard()
    enforceKioskAfterWifiAction()
}

private fun updateWifiPasswordDisplay() {
    if (!::wifiPasswordDisplay.isInitialized) return
    wifiPasswordDisplay.text = wifiPasswordState.maskedPassword().ifBlank { "Password" }
}
```

- [ ] **Step 5: Wire network selection and connect**

In `createWifiNetworkRow`, replace Wi-Fi password `EditText` logic with:

```kotlin
wifiPasswordState.clear()
updateWifiPasswordDisplay()
selectedWifiNetwork = network
val needsPassword = network.security == WifiSecurity.WPA_PSK
wifiPasswordDisplay.visibility = if (needsPassword) View.VISIBLE else View.GONE
wifiKeyboardContainer.visibility = if (needsPassword) View.VISIBLE else View.GONE
if (needsPassword) renderWifiKeyboard()
```

In `connectSelectedWifiNetwork`, use:

```kotlin
val password = wifiPasswordState.password
wifiPasswordState.clear()
```

In `clearWifiSelection`, clear state and hide `wifiPasswordDisplay` and `wifiKeyboardContainer`.

- [ ] **Step 6: Remove system keyboard imports and usage**

Remove from `MainActivity`:

```kotlin
import android.text.InputType
```

Ensure there is no Wi-Fi password `EditText`, no `InputMethodManager`, no `showSoftInput`, and no Settings intent.

- [ ] **Step 7: Build and install**

Run:

```bash
./gradlew testDebugUnitTest assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am force-stop uz.neovex.iccu.kiosk
adb shell monkey -p uz.neovex.iccu.kiosk -c android.intent.category.LAUNCHER 1
```

Expected: BUILD SUCCESSFUL and install `Success`.

- [ ] **Step 8: Device verification**

Run:

```bash
for i in 1 2 3 4 5 6; do adb shell input tap 1242 24; sleep 0.2; done
adb shell dumpsys activity activities | rg -n "mLockTaskModeState|mResumedActivity|ResumedActivity|uz.neovex.iccu.kiosk|com.android.settings"
```

Expected:

- `mLockTaskModeState=LOCKED`
- resumed activity is `uz.neovex.iccu.kiosk/.MainActivity`
- Android Settings is not resumed

- [ ] **Step 9: Commit**

Run:

```bash
git restore app/build build
git add app/src/main/java/uz/neovex/iccu/kiosk/MainActivity.kt
git commit -m "Add custom Wi-Fi keyboard UI"
```

### Task 3: Final Verification

**Files:**
- No source files unless verification finds a bug.

**Interfaces:**
- Consumes: completed custom keyboard UI.
- Produces: verified tablet behavior.

- [ ] **Step 1: Run full verification**

Run:

```bash
./gradlew testDebugUnitTest assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am force-stop uz.neovex.iccu.kiosk
adb shell monkey -p uz.neovex.iccu.kiosk -c android.intent.category.LAUNCHER 1
```

Expected: BUILD SUCCESSFUL, install Success, app opens.

- [ ] **Step 2: Screenshot verification**

Run:

```bash
adb shell input tap 1242 24
adb exec-out screencap -p > /tmp/iccu-custom-wifi-keyboard.png
```

Expected: Wi-Fi panel opens. After selecting a secured network manually on the tablet, custom keyboard appears inside the panel and Android keyboard does not appear.

- [ ] **Step 3: Kiosk verification**

Run:

```bash
adb shell dumpsys activity activities | rg -n "mLockTaskModeState|mResumedActivity|ResumedActivity|uz.neovex.iccu.kiosk|com.android.settings"
```

Expected:

- `mLockTaskModeState=LOCKED`
- resumed activity is `uz.neovex.iccu.kiosk/.MainActivity`

- [ ] **Step 4: Push**

Run:

```bash
git push
```
