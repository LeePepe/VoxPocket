# TestFlight release

Last-Reviewed: 2026-10-20

Delivery rules are in `AGENTS.md` → Red lines (TestFlight only; iOS TestFlight needs separate
Owner authorization). This page records the approved policy and the current
`.github/workflows/testflight.yml` operating state.

`.github/workflows/testflight.yml` checks `main` every 12 hours and publishes new macOS commits to TestFlight via Fastlane on the self-hosted mac runner. Apple Connect / TestFlight testability is verified by the Owner.

- **Owner decision (2026-10-20)**: publish every 12 hours, staggered across projects, with manual fallback and no per-upload confirmation. This supersedes the 2026-10-14/15 per-push cadence and the earlier manual-only policy. Builds run on the Owner's self-hosted Mac; required PR checks and the up-to-date merge requirement remain in force.
- **Schedule and candidate**: UTC cron `17 5,17 * * *` requests runs at 01:17 and 13:17 Asia/Shanghai. GitHub may delay starts. Only schedule and manual dispatch on `refs/heads/main` are admitted. Each checks out official `main` once and captures its HEAD for the release decision and successful-release marker. A merge alone does not trigger a release. Equal HEAD and marker skip the upload; the macOS-only marker stays `testflight/macos-last-released`, and the legacy dual-platform marker is preserved for a future authorized iOS release.
- **Manual fallback**: `gh workflow run testflight.yml --ref main -f platform=macos` applies the ordinary no-new-commits gate. Add `-f force=true` to repeat a macOS release at the same HEAD. Scheduled runs cannot force. The iOS lane stays disabled until the Owner separately authorizes iOS TestFlight releases.
- **Build number**: `latest_testflight_build_number(platform: "osx") + 1` for macOS, across marketing versions. Each platform uses its own latest build number, so platforms cannot collide. `MARKETING_VERSION` lives in `VoxPocket/project.yml` (`settings.base`); bump it manually there. `CURRENT_PROJECT_VERSION` is a single base source, injected at archive time by fastlane `xcargs` — never hardcoded per target.
- **Signing**: Release configs use **manual** signing + explicit `Apple Distribution` + App Store provisioning profiles (per-SDK for the multiplatform target). macOS fetches/installs its profile in-run without a fixed name, injects `VOXPOCKET_MAC_PROFILE_SPECIFIER` into archive, reuses it for export, and signs packages with `Mac Installer Distribution`. Debug stays Automatic for local dev.
- **Required GitHub Secrets**: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, `KEYCHAIN_PASSWORD` (`GITHUB_TOKEN` is built-in).
- **Telemetry GitHub Actions secrets**: the authorized macOS archive also requires both
  `TELEMETRY_BLOB_ENDPOINT` and `TELEMETRY_BLOB_SAS`. Missing, empty, or xcconfig-unsafe
  input fails before archive; ordinary credential-free Debug/Release development stays disabled.
  Only the preparation step receives these values. It writes one untracked file directly in
  `RUNNER_TEMP` with verified mode `0600`; URL slashes use empty-variable expansion so xcconfig
  comment parsing preserves HTTPS. Fastlane receives only `TELEMETRY_XCCONFIG_PATH` and passes
  that path through `-xcconfig` in Gym's archive-only `xcodebuild_command`. The project/detection
  `xcconfig` option stays unset: dependency resolution, build-settings detection and export
  never receive the file. The archive uses `-quiet` and discards stdout/stderr before Gym's
  log tee and formatter; failure/verbose replay therefore has no secret output to print.
  This deliberately sacrifices raw archive diagnostics. Values never belong in `xcargs`,
  inline environment assignments, messages, logs, or attached artifacts. Fastlane `ensure`
  removes the file on success, error, or interruption; workflow `always()` removes it as a
  fallback, including cancellation or preparation failure, before the existing release marker.
  Preparation, Fastlane and cleanup each compute the same run/attempt-specific path in
  step-level environment settings, where the Actions `runner` context is valid. Cleanup
  remains independent of preparation outputs, including when file creation fails partway.
- **Owner provisioning**: the PR09 body carries the exact placeholder-only operator commands
  from `specs/012-azure-blob-telemetry/plan.md`. The Owner creates a key-authenticated stored
  access policy with create-only permission `c` and explicit UTC expiry, then generates an
  HTTPS-only container service SAS bound to that policy and pipes it directly into the SAS
  Actions secret. Authorization/expiry come from the policy; any explicit SAS `sp` must be
  exactly `c`. The endpoint secret is entered interactively. Agents never generate, inspect,
  copy, persist, or provision real values. Do not put real cloud identifiers in Git.
- **Release and consent**: the approved schedule and manual fallback retain signing, numbering,
  upload, macOS scope, the disabled iOS lane, and release tags. Cadence authorization does not
  provision secrets or grant telemetry consent: the tester separately opts in through
  “Send usage data”. T012 production proof remains pending until its provisioning prerequisites
  and the tester's separate telemetry consent exist; evidence is limited to build number, run/revision and
  blob name, without payloads, identifiers, or credentials.
- **One-time人工前置**: ASC App record (iOS + macOS platforms), the `.widget` App ID, and a TestFlight internal group named exactly `Internal` (or set `TESTFLIGHT_GROUPS`).

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->
