# Custom Wi-Fi Keyboard Design

## Goal

Improve the Wi-Fi panel UX by replacing the system Android keyboard with a custom in-app password keyboard that stays inside kiosk mode.

The user can enter Wi-Fi passwords without opening Gboard or any system IME surface. The app remains in lock task mode and never opens Android Settings.

## Current Context

The kiosk app already has an in-app Wi-Fi panel. It currently uses an `EditText` password field, which can open the system keyboard. That is functional, but less controlled for kiosk tablets.

## User Flow

When the user selects a WPA/WPA2 network:

- The Wi-Fi panel shows the selected SSID.
- A masked password display appears.
- A custom keyboard appears inside the same Wi-Fi panel.
- The user taps keys to build the password.
- `Backspace` removes one character.
- `Clear` clears the whole password.
- `Shift` toggles uppercase/lowercase letters.
- `123` toggles between letters and symbols/numbers.
- `Done` hides the custom keyboard but keeps the password.
- `Connect` uses the internal password buffer.

When the user closes the panel, changes network, connects, or the panel auto-hides, the password buffer is cleared.

## UI Design

The Wi-Fi panel remains compact and aligned to the top-right header area.

The password area contains:

- Selected network label.
- Masked password display using bullet characters.
- Small action row: `Clear`, `Done`.
- Keyboard rows with stable button sizes.

Letter layout:

- `q w e r t y u i o p`
- `a s d f g h j k l`
- `Shift z x c v b n m Backspace`

Number/symbol layout:

- `1 2 3 4 5 6 7 8 9 0`
- `! @ # $ % & * _ - .`
- `ABC / : ; ? + = Backspace`

Buttons use the existing dark/gold kiosk style. Text must fit inside buttons on tablet landscape.

## Architecture

Add a small password input state separate from Android `EditText`:

- `WifiPasswordInputState`: holds the password, keyboard mode, and shift state.
- `WifiKeyboardMode`: `LETTERS` or `SYMBOLS`.

`MainActivity` owns the visual keyboard:

- Renders rows from the state.
- Updates the password display after every key press.
- Never requests focus for a system text input.
- Never calls IME APIs.

The password passed to `KioskWifiController.connect()` comes from `WifiPasswordInputState.password`.

## Kiosk Safety

The implementation must not use:

- Android Settings intents.
- `InputMethodManager.showSoftInput`.
- A focusable `EditText` for Wi-Fi password entry.
- `stopKioskMode()` or `stopLockTask()` from any Wi-Fi path.

The PIN exit flow is unchanged.

## Testing

Unit tests:

- Appending letters updates password.
- Shift changes letter casing for one mode state.
- Backspace removes one character.
- Clear empties password.
- Symbols mode accepts Wi-Fi password symbols.
- Masked display uses bullets and does not expose the password.

Device verification:

- Install APK on a Device Owner tablet.
- Open Wi-Fi panel and select a secured network.
- Confirm the system keyboard does not appear.
- Enter `12345678!!` using the custom keyboard.
- Connect to `Neo_wifi`.
- Press Wi-Fi icon repeatedly and confirm `mLockTaskModeState=LOCKED`.

## Out Of Scope

- Full international keyboard layouts.
- Clipboard paste.
- Saving Wi-Fi passwords.
- Showing plain password text.
