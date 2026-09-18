# Releasing strafe-tatoalo

## Identity and versioning

- Repository: `tatoalo/strafe`; upstream: `rileycx/strafe`.
- App/executable: `strafe-tatoalo`; bundle/preferences domain: `com.tatoalo.strafe`.
- Architecture: Apple Silicon; minimum macOS: 15.
- `VERSION` contains the fork's marketing version, independent of upstream.
- GitHub release tags: `strafe-tatoalo-v<version>`.
- `CFBundleVersion` is `GITHUB_RUN_NUMBER * 100 + GITHUB_RUN_ATTEMPT`, providing increasing builds across release workflow runs. Do not replace/reset the release workflow without preserving this ordering.
- Local development builds use Git commit count and are not a published update source.

## One-time setup

Enable Actions and Issues. The stable GitHub Releases appcast URL is `https://github.com/tatoalo/strafe/releases/latest/download/appcast.xml`.

Configure these repository Actions secrets:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64 of an exported Developer ID Application certificate and private key |
| `DEVELOPER_ID_P12_PASSWORD` | Export password |
| `ASC_PRIVATE_KEY` | App Store Connect API private key for notarization |
| `ASC_KEY_ID` | API key ID |
| `ASC_ISSUER_ID` | API issuer ID |
| `SPARKLE_EDDSA_PRIVATE_KEY` | Strafe's Sparkle private signing key |
| `LLM_PROVIDER_API_KEY` | Upstream-report provider API credential |
| `LLM_PROVIDER_MODEL` | Provider model identifier |
| `LLM_PROVIDER_URL` | Provider's Chat Completions-compatible endpoint |

`Resources/SparklePublicKey.txt` is public and committed. Its private counterpart is kept in the local macOS Keychain under the Sparkle account `com.tatoalo.strafe` and in GitHub's encrypted secret. Back up the private key securely. Do not substitute another app's Sparkle public key or rotate both signing identities in one release.

## Publish a stable release

1. Bump `VERSION` and write `release-notes/<version>.md`.
2. Merge the reviewed PR with the **release** label, or manually run **Release** on `main` with `prerelease=false`.
3. Actions runs the tests, builds, signs the embedded helpers and app with Hardened Runtime, notarizes/staples the app, creates and signs/notarizes/staples the DMG, verifies Gatekeeper acceptance, and signs the Sparkle archive metadata.
4. The workflow publishes the immutable GitHub release and assets, verifies the download URL, and publishes the appcast in the same release. The stable URL follows GitHub’s latest stable release. Earlier compatible feed entries are retained.
5. Verify the public download and **Check for Updates…** from the prior installed build.

Development pushes/PRs produce an ad-hoc ZIP artifact with 14-day retention. They never advance the stable feed.

## Test the whole updater

Run **Release** on `main` with `prerelease=true` to produce a signed/notarized prerelease. Its tag includes the build number and it does not enter the stable feed. Install it, then publish the stable release in a later workflow run. Sparkle must detect its higher build number, show release notes, download, verify, install, and relaunch. Verify both hotkeys, BetterMouse, trackpad interception, version, transition speed, and Accessibility after the update.

The current upstream/ad-hoc app cannot bootstrap Sparkle by itself: install this fork once. Quit the original `strafe` to avoid competing event taps/hotkeys, replace it with `strafe-tatoalo`, and grant the fork Accessibility. Preferences migrate once. Later signed-to-signed upgrades must retain the same bundle identifier and valid signing identity.

## Failures and recovery

A release that fails tests/signing/notarization never advances the feed. Signing secrets are removed even when a job fails. Release runs are serialized and are not canceled halfway through.

A published tag is immutable: bump the version for a new build instead of overwriting a released DMG. Assets and the appcast are uploaded to a draft first, then made public together. A failed draft can be retried. If post-publication verification fails, inspect the public assets and rerun `python3 Scripts/verify-published.py <tag>`; do not rebuild or overwrite a published release.

To recover from a bad update, publish the corrected app with a higher internal build number and a new marketing version. Do not lower the version or overwrite an old archive: already-installed clients will not reliably downgrade.

GitHub scheduled workflows can be disabled after 60 days without repository activity; re-enable **Upstream impact report** in Actions if needed. A closed analysis issue records acknowledgment, not a merge.
