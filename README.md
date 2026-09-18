# strafe-tatoalo

A fork of [rileycx/strafe](https://github.com/rileycx/strafe) with **Control–Arrow Space switching**, signed macOS downloads, and in-app updates.

Based on upstream Strafe 0.1.2. The instant switching technique originates with [jurplel/InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher); macOS 27 gesture support incorporates work from [joshuarli/iss](https://github.com/joshuarli/iss). Original MIT and 0BSD notices are retained in [LICENSE](LICENSE).

## Install

1. Download the Apple Silicon DMG from [Releases](https://github.com/tatoalo/strafe/releases/latest).
2. Quit any existing upstream/local `strafe` app. Drag **strafe-tatoalo.app** into Applications and open it.
3. Grant **strafe-tatoalo** permission in System Settings → Privacy & Security → Accessibility, then quit and reopen the app.
4. In System Settings → Keyboard → Keyboard Shortcuts → Mission Control, disable **Move left a space** and **Move right a space** so Strafe can own Control–Arrow.

Requires Apple Silicon and macOS 15 or newer. Releases are Developer ID signed, notarized, and stapled. This fork has its own bundle identity (`com.tatoalo.strafe`); the initial migration from an ad-hoc/upstream build needs a new Accessibility grant. Existing transition-speed and hotkey preferences are copied once without overwriting fork settings.

## Use

- **Control–Left / Control–Right:** instantly switch to the adjacent Space.
- **BetterMouse:** bind horizontal mouse gestures to Control–Left/Right. Synthetic three-finger swipe actions are not intercepted.
- **Trackpad:** native horizontal Space swipes are accelerated when Accessibility is granted and interception is enabled.
- **Menu bar:** toggle gesture interception or hotkeys independently, choose Instant/Quick/Smooth transitions, and hide/show the menu icon.
- **Check for Updates…:** view release notes, install a signed update, and relaunch.
- **Automatically check for updates:** enables periodic background checks. Installing an update remains your choice; automatic installation is disabled by default.

The update feed is [appcast.xml](https://github.com/tatoalo/strafe/releases/latest/download/appcast.xml). Only stable releases enter this feed; development artifacts and prereleases do not.

The CLI is bundled inside the app:

```sh
/Applications/strafe-tatoalo.app/Contents/MacOS/strafe-tatoalo switch left
/Applications/strafe-tatoalo.app/Contents/MacOS/strafe-tatoalo status
/Applications/strafe-tatoalo.app/Contents/MacOS/strafe-tatoalo speed quick
/Applications/strafe-tatoalo.app/Contents/MacOS/strafe-tatoalo hotkeys on
```

## Build and release

For local development, install a Swift 6.3+ toolchain and run:

```sh
./Scripts/bundle.sh
swift test
bash Tests/run.sh
bash Tests/hotkeys.sh
python3 -m unittest discover -s Tests -p 'test_*.py'
```

Local builds are ad-hoc signed. Published releases are built entirely in GitHub Actions. Merge a PR labeled **release** with an updated `VERSION` and `release-notes/<version>.md`, or run the **Release** workflow on `main`. See [RELEASE.md](RELEASE.md) for signing, publishing, recovery, and update verification.

## Upstream monitoring

The **Upstream impact report** workflow checks `rileycx/strafe` daily at **03:17 UTC**, and can be run manually. New upstream changes create an issue in this fork containing the upstream diff, merge conflicts, static checks of fork behavior, and an AI-assisted compatibility assessment. It updates an existing open report instead of creating daily duplicates.

It never merges or pushes code. Closing a report does not mark changes as incorporated; Git ancestry determines that. [Fork customizations](.github/fork-customizations.md) document the behavior to preserve. GitHub can pause scheduled workflows after prolonged repository inactivity; the workflow can be re-enabled in Actions.

## Security and attribution

Gesture interception still excludes keystrokes, and the app has no analytics. Unlike upstream, this fork includes Sparkle, contacts GitHub for updates, and publishes compiled binaries. Read [SECURITY.md](SECURITY.md) for the precise boundaries.

MIT, with upstream attribution and third-party notices in [LICENSE](LICENSE).
