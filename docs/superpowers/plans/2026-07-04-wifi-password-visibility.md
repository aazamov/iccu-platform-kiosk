# Wi-Fi Password Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Show/Hide control that lets kiosk users temporarily view the Wi-Fi password they typed with the custom keyboard.

**Architecture:** `WifiPasswordInputState` owns password visibility state and display formatting. `MainActivity` renders a small Show/Hide button beside the existing password display and resets visibility on network changes, close, connect, and clear/reset.

**Tech Stack:** Native Android Kotlin, Android Views, JUnit 4, Gradle.

## Global Constraints

- Password is masked by default.
- Custom keyboard remains the only password input method; no Android soft keyboard is opened.
- Selecting another network, closing the panel, connecting, clearing the password, or resetting the password state returns visibility to hidden.
- Existing Wi-Fi keyboard and full Gradle build tests must continue to pass.

---

### Task 1: Password Visibility State

**Files:**
- Modify: `app/src/main/java/uz/neovex/iccu/kiosk/WifiPasswordInputState.kt`
- Modify: `app/src/test/java/uz/neovex/iccu/kiosk/WifiPasswordInputStateTest.kt`

**Interfaces:**
- Consumes: existing `WifiPasswordInputState.password`, `appendKey(label: String)`, `reset()`, `clear()`
- Produces: `var passwordVisible: Boolean`, `toggleVisibility()`, `displayPassword(): String`

- [ ] **Step 1: Write failing tests**

Add these tests to `WifiPasswordInputStateTest`:

```kotlin
@Test
fun passwordIsHiddenByDefaultAndCanBeShown() {
    val state = WifiPasswordInputState()

    state.appendKey("n")
    state.appendKey("e")
    state.appendKey("o")

    assertFalse(state.passwordVisible)
    assertEquals("•••", state.displayPassword())

    state.toggleVisibility()

    assertTrue(state.passwordVisible)
    assertEquals("neo", state.displayPassword())
}

@Test
fun resetAndClearHidePasswordAgain() {
    val state = WifiPasswordInputState()

    state.appendKey("x")
    state.toggleVisibility()
    state.clear()

    assertFalse(state.passwordVisible)
    assertEquals("", state.displayPassword())

    state.appendKey("y")
    state.toggleVisibility()
    state.reset()

    assertFalse(state.passwordVisible)
    assertEquals("", state.displayPassword())
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `./gradlew testDebugUnitTest --tests uz.neovex.iccu.kiosk.WifiPasswordInputStateTest`

Expected: FAIL because `passwordVisible`, `toggleVisibility()`, and `displayPassword()` do not exist.

- [ ] **Step 3: Implement state**

Update `WifiPasswordInputState`:

```kotlin
var passwordVisible: Boolean = false
    private set

fun clear() {
    buffer.clear()
    passwordVisible = false
}

fun reset() {
    buffer.clear()
    mode = WifiKeyboardMode.LETTERS
    shifted = false
    passwordVisible = false
}

fun toggleVisibility() {
    passwordVisible = !passwordVisible
}

fun maskedPassword(): String = "•".repeat(buffer.length)

fun displayPassword(): String = if (passwordVisible) password else maskedPassword()
```

- [ ] **Step 4: Run tests to verify pass**

Run: `./gradlew testDebugUnitTest --tests uz.neovex.iccu.kiosk.WifiPasswordInputStateTest`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/src/main/java/uz/neovex/iccu/kiosk/WifiPasswordInputState.kt app/src/test/java/uz/neovex/iccu/kiosk/WifiPasswordInputStateTest.kt
git commit -m "Add Wi-Fi password visibility state"
```

---

### Task 2: Show/Hide Control in Wi-Fi Panel

**Files:**
- Modify: `app/src/main/java/uz/neovex/iccu/kiosk/MainActivity.kt`
- Test: `app/src/test/java/uz/neovex/iccu/kiosk/WifiPasswordInputStateTest.kt`

**Interfaces:**
- Consumes: `WifiPasswordInputState.passwordVisible`, `toggleVisibility()`, `displayPassword()`
- Produces: a visible `Show`/`Hide` TextView beside the password display for WPA/WPA2 networks

- [ ] **Step 1: Write/confirm behavior covered by tests**

Task 1 tests cover the state behavior. This task verifies UI behavior manually on a tablet because `MainActivity` is View-based and not covered by instrumentation tests in this project.

- [ ] **Step 2: Add UI field and row**

In `MainActivity`, add:

```kotlin
private lateinit var wifiPasswordVisibilityButton: TextView
private lateinit var wifiPasswordRow: LinearLayout
```

Replace direct password display insertion with a horizontal `wifiPasswordRow` containing the existing password display and a small `Show`/`Hide` button.

- [ ] **Step 3: Implement toggle and display update**

Add button click:

```kotlin
setOnClickListener {
    if (selectedWifiNetwork?.security == WifiSecurity.WPA_PSK) {
        wifiPasswordState.toggleVisibility()
        updateWifiPasswordDisplay()
        enforceKioskAfterWifiAction()
    }
}
```

Update display:

```kotlin
wifiPasswordDisplay.text = wifiPasswordState.displayPassword().ifBlank { "Password" }
wifiPasswordVisibilityButton.text = if (wifiPasswordState.passwordVisible) "Hide" else "Show"
```

- [ ] **Step 4: Wire visibility resets**

Use `wifiPasswordRow.visibility` instead of only `wifiPasswordDisplay.visibility` when selecting networks, clearing selection, and connecting.

- [ ] **Step 5: Verify build and tablet behavior**

Run: `./gradlew testDebugUnitTest assembleDebug`

Install and verify on the connected tablet:

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell monkey -p uz.neovex.iccu.kiosk 1
```

Expected:
- WPA network selection shows password row and custom keyboard.
- Typed password is masked by default.
- `Show` reveals the typed password.
- `Hide` masks it again.
- Selecting another network resets to hidden.
- Kiosk remains locked.

- [ ] **Step 6: Commit**

```bash
git add app/src/main/java/uz/neovex/iccu/kiosk/MainActivity.kt
git commit -m "Add Wi-Fi password show hide control"
```
