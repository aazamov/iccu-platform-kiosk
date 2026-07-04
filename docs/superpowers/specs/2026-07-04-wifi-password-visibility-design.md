# Wi-Fi Password Visibility Design

## Goal

Allow an admin/user in the in-app Wi-Fi panel to temporarily view the typed Wi-Fi password while staying inside kiosk mode.

## User Experience

- Password input is masked by default.
- The password row should read as one compact input, not as separate blocks.
- A small attached `View` control appears beside the password field for secured Wi-Fi networks.
- Pressing `View` reveals the typed password and changes the control to `Hide`.
- Pressing `Hide` masks the password again.
- The row height should stay close to the custom keyboard key height.
- The visibility control should be narrow, quiet, and not visually compete with `Connect`.
- Selecting another network, closing the panel, connecting, clearing the password, or resetting the password state returns visibility to hidden.

## Components

- `WifiPasswordInputState` owns the password buffer and visibility state.
- `MainActivity` renders the password display text and the compact `View`/`Hide` control.
- The custom keyboard remains the only password input method; no Android soft keyboard is opened.

## Data Flow

1. User selects a WPA/WPA2 network.
2. Password display and visibility control appear.
3. Custom keyboard updates `WifiPasswordInputState`.
4. Display text renders either masked bullets or the raw password based on visibility state.
5. Connect uses the raw `password` value exactly as before.

## Error Handling

- Empty password display still shows `Password`.
- Visibility toggle has no effect when no secured network is selected.
- Reset paths force the display back to masked mode.

## Testing

- Unit tests cover default masked mode, visible password mode, visibility toggle, and reset hiding the password.
- Existing Wi-Fi keyboard and full Gradle build tests must continue to pass.
