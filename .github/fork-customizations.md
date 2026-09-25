# strafe-tatoalo customizations to preserve during an upstream merge

- `HotkeyManager` registers Control–Left/Right without Option. Its toggle and live preference notifications still work.
- The app, executable, and release assets are named `strafe-tatoalo`; the bundle/preferences identifier is `com.tatoalo.strafe`.
- Existing `transitionSpeed` and `spaceHotkeysEnabled` preferences migrate once from `com.rileycx.strafe`, without overwriting fork settings or importing an updater URL.
- Sparkle provides manual and optional automatic update checks. It uses this fork's HTTPS appcast, Ed25519 public key, and increasing build numbers.
- Launch at startup is opt-in through macOS Service Management and reflects the current Login Items status, including required approval.
- App termination releases the gesture tap and hotkeys so an update can relaunch cleanly.
- The release pipeline signs with Developer ID, notarizes/staples the app and DMG, signs the update archive, verifies it, and publishes assets before the feed.
- Stable updates come from reviewed fork releases, not the upstream branch or development CI artifacts.
- Gesture interception remains limited to gesture/dock-control events. The app has no analytics or input telemetry.
- Upstream checks are advisory: they create/update issues and never modify branches, merge code, run upstream code, or publish releases.
