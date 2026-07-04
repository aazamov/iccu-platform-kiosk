# In-App Wi-Fi Control For Kiosk

## Goal

Let a normal tablet user change Wi-Fi, connect to a network, and turn Wi-Fi on or off without leaving the kiosk app.

The app must not open Android Settings, must not call `stopLockTask()` for Wi-Fi, and must keep the website visible or recoverable while the Wi-Fi panel is open.

## Current Context

The kiosk app is Device Owner on provisioned tablets and already runs in lock task mode. The current Wi-Fi button shows only connection status inside the app because opening Android Settings created an escape path on HK17 tablets.

The project already has `WifiProvisionReceiver`, which uses `WifiManager` as Device Owner to enable Wi-Fi, save a WPA network, and reconnect. Android 10 restricts many Wi-Fi APIs for normal apps, but Device Owner apps are exempt for several deprecated `WifiManager` configuration methods.

## User Flow

The visible Wi-Fi icon opens a custom Wi-Fi panel inside the kiosk app.

The panel contains:

- Current status: connected/offline and current SSID when available.
- Wi-Fi power control: on/off.
- Available network list with refresh.
- Password input for secured networks.
- Connect button.
- Close button.

No PIN is required for this Wi-Fi panel. PIN `2026` remains only for exiting the kiosk app.

## Architecture

Add a small Wi-Fi domain layer separate from `MainActivity`:

- `KioskWifiController`: wraps Android `WifiManager` and `ConnectivityManager`.
- `WifiNetworkInfo`: simple model for SSID, signal level, security, and connected state.
- `WifiConnectionResult`: success/failure result with a user-safe message.

`MainActivity` owns only UI wiring:

- Opens/closes the Wi-Fi panel.
- Renders status and scan results.
- Calls `KioskWifiController` for enable, disable, scan, and connect.
- Keeps lock task mode active before and after every Wi-Fi action.

## Android Behavior

The app will use these APIs:

- `WifiManager.setWifiEnabled(true/false)` for Wi-Fi power where firmware allows it.
- `WifiManager.startScan()` and `scanResults` for visible networks.
- `WifiConfiguration`, `addNetwork`, `updateNetwork`, `enableNetwork`, and `reconnect` for WPA/WPA2 networks.
- `ConnectivityManager` and `WifiManager.connectionInfo` for current status.

If a firmware blocks an operation with `SecurityException` or returns failure, the app shows a short message inside the panel and stays in kiosk mode.

## Kiosk Safety

Wi-Fi actions never call `stopKioskMode()`.

The app never starts:

- `Settings.Panel.ACTION_WIFI`
- `Settings.ACTION_WIFI_SETTINGS`
- `Settings.ACTION_SETTINGS`

After each Wi-Fi action the app calls fullscreen and lock task enforcement again. The Wi-Fi panel is just a view inside the same activity, so repeated taps cannot switch to Android Settings or launcher.

## UI Notes

The panel will be compact and fit a tablet landscape header area without covering too much of the website. It expands downward from the Wi-Fi icon.

Controls:

- Wi-Fi on/off as a switch-like button.
- Refresh as an icon button.
- Networks as rows with SSID, signal, and lock indicator.
- Password field appears after selecting a secured network.
- Connect as a small button.

The design stays visually close to the current header: dark translucent panel, gold active controls, muted inactive state.

## Testing

Unit tests:

- Wi-Fi actions do not require stopping kiosk mode.
- Network security parsing identifies open and secured networks.
- Connection result mapping converts blocked/failed Android operations into safe messages.

Device verification:

- Install APK on a Device Owner tablet.
- Open Wi-Fi panel and press the Wi-Fi icon repeatedly.
- Confirm `mLockTaskModeState=LOCKED`.
- Confirm resumed activity stays `uz.neovex.iccu.kiosk/.MainActivity`.
- Test turning Wi-Fi off/on if firmware allows it.
- Test connecting to `Neo_wifi`.

## Out Of Scope

- Opening Android Settings.
- QR-code Wi-Fi enrollment.
- Enterprise EAP/certificate Wi-Fi.
- Managing saved networks beyond the network selected in the custom panel.
