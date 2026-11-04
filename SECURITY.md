# Security: strafe-tatoalo

This is the tatoalo fork of Strafe. It retains upstream's gesture engine but adds a Sparkle update channel and signed binary distribution. Upstream statements that there are no dependencies, network requests, release secrets, or prebuilt binaries do not apply to this fork.

## Input handling

The main event tap in `Sources/strafe/SwipeInterceptor.swift` subscribes to gesture, Dock-control, and modifier-change events. Its mask is defined by `strafe_tap_event_mask()` in `Sources/CStrafe/CStrafe.c`. Control–Left/Right uses Carbon's specific global hotkey registration in `HotkeyManager.swift`.

Modifier changes enable a separate keyboard tap only while Command is held; it is disabled during ordinary typing. This tap examines virtual key codes and modifier bits, never key text. It passes everything through except Control–Command–Left/Right when space-switch hotkeys are enabled and a fresh Accessibility read positively identifies Dock's `AXProcessSwitcherList`. This handles mouse utilities that retain a held Command modifier on their Control–Arrow shortcuts. Outside the app switcher, or if the check fails or times out, those shortcuts retain their normal behavior. There is no modifier or keyboard polling.

After claiming a synthetic shortcut, Strafe can preserve Command on that utility's immediate Control-release event and the system's following modifier-reconciliation event. This requires the Command key to remain physically down and expires after 250 ms, checked only when an event arrives. Physical Command-release events and unrelated processes/keys are not changed. This prevents mouse-utility cleanup from prematurely committing the selected Cmd–Tab app.

The engine reads the current display/Space topology, cursor location, and limited window metadata to identify the target display and Mission Control overlays. It synthesizes Dock-swipe events to accelerate transitions. These input and window details are used locally and are not recorded or transmitted. Private macOS APIs mean compatibility can change with macOS updates.

Accessibility is needed to intercept gestures. It can be revoked in System Settings → Privacy & Security → Accessibility. The fork's bundle identifier is `com.tatoalo.strafe`.

System UI detection reads only root child counts, machine identifiers, roles, and subroles using this same grant. It does not inspect app/window titles or descendant content. Dock connections (and WindowManager on macOS 27+) are warmed in the background at startup, after relevant lifecycle events, or after a failed input-time query. State is queried afresh only at a horizontal swipe's beginning or a candidate app-switcher shortcut, with a shared 5 ms messaging budget and at most 16 root children per host. There is no polling timer. Unknown or late results preserve native input. Earlier macOS versions retain the legacy window-layer check for Mission Control. Setting `STRAFE_OVERLAY_DIAGNOSTICS=1` logs at most 64 UI-state decisions with query durations and 16 modifier-cleanup repairs locally to stderr; it is off by default and records no input content.

## Networking, files, and updates

Sparkle is the app's third-party dependency, pinned in `Package.swift` and `Package.resolved`. It reads the HTTPS appcast at `https://github.com/tatoalo/strafe/releases/latest/download/appcast.xml`, fetches release notes/update assets, verifies update signatures, and installs updates using its bundled helpers. Update downloads come from GitHub Releases and may follow GitHub's CDN redirects. These requests expose ordinary connection metadata to GitHub. Sparkle system profiling is disabled; there is no app analytics or input telemetry.

Users can turn automatic update checks off. Manual **Check for Updates…** remains available. Automatic installation is disabled by default. Sparkle stores update preferences and temporary downloads; app preferences are stored in `com.tatoalo.strafe`. Only `transitionSpeed` and `spaceHotkeysEnabled` migrate from upstream's preferences domain.

Stable releases are signed with Developer ID, notarized by Apple, and stapled. Update archives also carry a Sparkle Ed25519 signature whose public key is embedded in the app. Local builds are ad-hoc signed and are not equivalent to notarized releases.

## Release automation

Signing and notarization credentials exist only as GitHub Actions secrets and temporary files/keychains in the release job. They are removed in an unconditional cleanup step. Pull-request CI does not receive release secrets. Release jobs run only for the fork's `main` branch or the merge result of a release-labeled PR into `main`. Assets and the appcast are uploaded to a draft and made public together.

The monthly upstream checker receives issue-writing permission and the configured analysis-provider credentials. It sends public upstream/fork code diffs and customization documentation to that provider to produce an advisory report. It never sends signing secrets, runs upstream code, modifies working-tree files, pushes commits, merges changes, or cuts releases. AI assessments may be wrong; the report separates them from factual Git/static checks.

Report vulnerabilities privately through the repository owner's GitHub contact options; do not include credentials or private data in public issues.
