# Custom Keyboard Panel Fit Report

- Issue: Secured Wi-Fi selection showed the custom keyboard, but the bottom action row and Connect controls were clipped by the fixed Wi-Fi panel height.
- Root cause: The top-right Wi-Fi panel allocated `260dp x 292dp`, which was too short for header/status, network rows, password display, four custom keyboard rows, Connect, and message text.
- Change: Increased only the Wi-Fi panel height to `420dp`, preserving the existing `260dp` width, top-right gravity, top margin, and end margin.
- Constraint check: No Android Settings intents, soft keyboard calls, focusable password `EditText`, Wi-Fi kiosk exits, or PIN exit changes were added.
- Verification: `./gradlew testDebugUnitTest assembleDebug` completed successfully (`BUILD SUCCESSFUL`; 41 actionable tasks, 7 executed, 34 up-to-date).
