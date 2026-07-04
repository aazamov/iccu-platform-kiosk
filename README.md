# ICCU Forum Kiosk

Native Kotlin Android tablet kiosk app that opens `https://forum.iccu.uz/` in a fullscreen WebView.

## Admin Controls

- Wi-Fi opens immediately from the visible Wi-Fi icon.
- Brightness opens from the visible brightness icon and has `-`, slider, and `+` controls.
- Battery hard reload: press and hold the battery area for 3 seconds.
- Exit: press and hold the hidden top-left corner hotspot for 5 seconds, then enter PIN `2026`.

## Build

```sh
./gradlew assembleDebug
```

The debug APK will be created at:

```text
app/build/outputs/apk/debug/app-debug.apk
```

## Install

```sh
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## Enable Full Kiosk Mode

Android only permits true full kiosk mode when the app is the device owner. On a fresh or factory-reset tablet, install the app and run:

```sh
adb shell dpm set-device-owner uz.neovex.iccu.kiosk/.KioskDeviceAdminReceiver
```

Then launch the app:

```sh
adb shell monkey -p uz.neovex.iccu.kiosk 1
```

If the tablet is not provisioned as device owner, the app still hides system bars and requests lock task mode, but Android may show a screen-pinning prompt or allow system escape gestures depending on the device policy.

## One-Command Provisioning

For operators who only need to connect a prepared tablet and install kiosk mode:

```sh
./tools/provision_kiosk_tablet.sh
```

On macOS, `tools/provision_kiosk_tablet.command` is a double-click launcher for the same script.

If multiple tablets are connected:

```sh
./tools/provision_kiosk_tablet.sh --serial KZ5CAEJ85LX5DSZFRYW
```

Russian operator setup guide:

```text
docs/OPERATOR_COMPUTER_SETUP_RU.md
```

Windows operator setup guide:

```text
docs/WINDOWS_OPERATOR_SETUP_RU.md
```

On a clean Windows computer, the PowerShell script can download portable Java 17 and ADB into `tools\.portable`:

```bat
tools\provision_kiosk_tablet.bat -PrepareTools
```

On Windows, running without `-Serial` provisions all connected authorized tablets. Use `-Serial DEVICE_SERIAL` for one tablet only.

On macOS/Linux, old HK17 tablets need a newer Android System WebView APK. The script looks for it in:

```text
tools/.downloads/android-system-webview.apk
tools/.downloads/android-system-webview-150.apk
~/Downloads/*WebView*.apk
```

You can also pass a direct APK URL:

```sh
./tools/provision_kiosk_tablet.sh --webview-apk-url "https://.../android-system-webview.apk"
```

The Windows script connects each tablet to Wi-Fi `Neo_wifi` using the saved default password. If the tablet firmware blocks ADB Wi-Fi commands, the script installs the app, enables Device Owner, and then asks the kiosk app to configure Wi-Fi. To use another network:

```bat
tools\provision_kiosk_tablet.bat -WifiSsid "OfficeWifi" -WifiPassword "password"
```

Before provisioning a new app version on macOS or Windows, update the project first:

```sh
git pull
```

Both provisioning scripts build `app/build/outputs/apk/debug/app-debug.apk` from the current local source and print `Source commit` before installing.

To skip Wi-Fi setup:

```bat
tools\provision_kiosk_tablet.bat -SkipWifiSetup
```

For tablets without a Google account, the Windows script tries to download a compatible Android System WebView APK automatically when WebView is old. For stable operator setup, you can also put the APK here before provisioning:

```text
tools\.downloads\android-system-webview.apk
```

The Windows provisioning script updates old WebView versions automatically before enabling kiosk mode. For HK17 Android 10 tablets, use `com.google.android.webview` for `arm64-v8a + armeabi-v7a`, Android 10/API 29+.

## Windows Uninstall

To remove the kiosk app from a connected tablet on Windows:

```bat
tools\uninstall_kiosk_tablet.bat
```

If the app is Device Owner, the script installs the debug APK with the built-in removal hook, clears Device Owner, uninstalls `uz.neovex.iccu.kiosk`, and verifies the package is gone.
# iccu-platform-kiosk
