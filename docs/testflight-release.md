# TestFlight release

Last-Reviewed: 2026-09-24

Delivery rules are in `AGENTS.md` → Red lines (TestFlight only; iOS TestFlight needs separate
Owner authorization). This page records how `.github/workflows/testflight.yml` works.

`.github/workflows/testflight.yml` publishes `main` to TestFlight via Fastlane on the self-hosted mac runner. Apple Connect / TestFlight testability is verified by the Owner.

- **Trigger**: `workflow_dispatch` only, after an explicit user request. Automatic releases are paused; merging a PR does not publish a build. The macOS-only release tracks `testflight/macos-last-released`; the legacy dual-platform marker is preserved for a future authorized iOS release.
- **Manual**: `gh workflow run testflight.yml --ref main -f force=true -f platform=macos` to force a macOS release ignoring the "no new commits" gate. The iOS lane stays disabled in the workflow until the Owner separately authorizes iOS TestFlight releases.
- **Build number**: `latest_testflight_build_number(platform: "osx") + 1` for macOS, across marketing versions. Each platform uses its own latest build number, so platforms cannot collide. `MARKETING_VERSION` lives in `VoxPocket/project.yml` (`settings.base`); bump it manually there. `CURRENT_PROJECT_VERSION` is a single base source, injected at archive time by fastlane `xcargs` — never hardcoded per target.
- **Signing**: Release configs use **manual** signing + explicit `Apple Distribution` + App Store provisioning profiles (per-SDK for the multiplatform target). Debug stays Automatic for local dev.
- **Required GitHub Secrets**: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, `KEYCHAIN_PASSWORD` (`GITHUB_TOKEN` is built-in).
- **One-time人工前置**: ASC App record (iOS + macOS platforms), the `.widget` App ID, and a TestFlight internal group named exactly `Internal` (or set `TESTFLIGHT_GROUPS`).

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->
