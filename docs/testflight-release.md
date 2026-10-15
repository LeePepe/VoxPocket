# TestFlight release

Last-Reviewed: 2026-10-15

Delivery rules are in `AGENTS.md` → Red lines (TestFlight only; iOS TestFlight needs separate
Owner authorization). This page records how `.github/workflows/testflight.yml` works.

`.github/workflows/testflight.yml` publishes `main` to macOS TestFlight via Fastlane on the self-hosted Mac runner (`[self-hosted, macOS, ARM64]`).

- **Automatic release**: triggered by completed successful `workflow_run` of the `CI` workflow on `main`. It checks out the exact `workflow_run.head_sha` with full history (`fetch-depth: 0`) and verifies checked-out `HEAD` equality before release steps.
- **Relevance evaluation**: changed paths between the last released marker `testflight/macos-last-released` and the candidate are evaluated by `scripts/ci/testflight_relevance.py`.
  - App-relevant paths: `Packages/**`, `VoxPocket/**`, `VoxPocketWidget/**`, `fastlane/**`, `.github/workflows/testflight.yml`, `scripts/ci/fetch-external-deps.sh`.
  - An absent marker is an initial bootstrap release.
  - Candidate equal to marker skips as `already-released`.
  - No app-relevant changes skips before build/signing/upload with a concise reason summary.
  - Unresolved or non-ancestor marker fails closed.
- **Manual fallback**: `gh workflow run testflight.yml --ref main [-f force=true]` releases the immutable dispatch SHA and verifies checked-out `HEAD` equality. `force=true` bypasses relevance only for an unreleased candidate; it does not bypass marker equality, invalid marker state, macOS-only policy, or safety checks.
- **Dependencies & Signing**: checks out `LeePepe/AppleUITesting` at pinned ref `e6be2fcdf83341a9f3000a4cc489237655461a07` and verifies checked-out `HEAD` equality. Release configs use manual signing + explicit `Apple Distribution` + App Store provisioning profiles. macOS fetches and installs its profile in-run without a fixed name, injects `VOXPOCKET_MAC_PROFILE_SPECIFIER` into the archive, reuses it for export, and signs packages with `Mac Installer Distribution`. Debug stays Automatic for local development. Build/signing secrets (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, `KEYCHAIN_PASSWORD`) are step-scoped.
- **Concurrency & Permissions**: single concurrency group `testflight` with `cancel-in-progress: false`. The release job has `contents: read`; only the dependent marker job has `contents: write`.
- **Cleanup & Marker update**: `always()` cleanup removes temporary keychain and local tag state. Cleanup or checkout post-action failure blocks the dependent marker job. After successful upload and all release-job cleanup, the marker job moves `testflight/macos-last-released` directly to the exact candidate SHA without creating a local tag. The remote tag push is the terminal operation; there is no post-marker work.
- **Build number**: `latest_testflight_build_number(platform: "osx") + 1` for macOS, across marketing versions. `MARKETING_VERSION` lives in `VoxPocket/project.yml` (`settings.base`).
- **One-time人工前置**: ASC App record (iOS + macOS platforms), the `.widget` App ID, and a TestFlight internal group named exactly `Internal` (or set `TESTFLIGHT_GROUPS`).
