# TestFlight release

Last-Reviewed: 2026-10-16

Delivery rules are in `AGENTS.md` → Red lines (TestFlight only; iOS TestFlight needs separate
Owner authorization). This page records the approved policy and the current
`.github/workflows/testflight.yml` operating state.

`.github/workflows/testflight.yml` publishes `main` to TestFlight via Fastlane on the self-hosted mac runner. Apple Connect / TestFlight testability is verified by the Owner. Automatic push triggering is approved but not yet wired; until that workflow change lands, releases remain manual.

- **Owner decision (2026-10-14; refined 2026-10-15)**: every app publishes to TestFlight automatically after merge to `main`. CD triggers on an exact push to `main`, because CI runs on the PR and branches must be up to date before merging. Builds run on the Owner's self-hosted Mac. No per-upload Owner confirmation is required. This supersedes the earlier manual-only TestFlight policy for VoxPocket.
- **Target trigger**: an exact push to `main` will automatically publish macOS after the PR's successful CI and up-to-date merge. The current workflow still exposes only `workflow_dispatch`; use it after an explicit Owner request until automatic triggering is implemented. The macOS-only release tracks `testflight/macos-last-released`; the legacy dual-platform marker is preserved for a future authorized iOS release.
- **Manual**: `gh workflow run testflight.yml --ref main -f force=true -f platform=macos` to force a macOS release ignoring the "no new commits" gate. The iOS lane stays disabled in the workflow until the Owner separately authorizes iOS TestFlight releases.
- **Build number**: `latest_testflight_build_number(platform: "osx") + 1` for macOS, across marketing versions. Each platform uses its own latest build number, so platforms cannot collide. `MARKETING_VERSION` lives in `VoxPocket/project.yml` (`settings.base`); bump it manually there. `CURRENT_PROJECT_VERSION` is a single base source, injected at archive time by fastlane `xcargs` — never hardcoded per target.
- **Signing**: Release configs use **manual** signing + explicit `Apple Distribution` + App Store provisioning profiles (per-SDK for the multiplatform target). macOS fetches/installs its profile in-run without a fixed name, injects `VOXPOCKET_MAC_PROFILE_SPECIFIER` into archive, reuses it for export, and signs packages with `Mac Installer Distribution`. Debug stays Automatic for local dev.
- **Required GitHub Secrets**: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, `KEYCHAIN_PASSWORD` (`GITHUB_TOKEN` is built-in).
- **One-time人工前置**: ASC App record (iOS + macOS platforms), the `.widget` App ID, and a TestFlight internal group named exactly `Internal` (or set `TESTFLIGHT_GROUPS`).

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->
