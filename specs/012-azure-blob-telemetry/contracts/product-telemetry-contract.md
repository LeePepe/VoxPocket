# Contract: VoxPocket Blob product telemetry

**Contract version**: 4

**Authority**: MY-1818 issue revision 1, MY-1841 common consent contract, Constitution III/IV, the 2026-10-16 Lead decision `A-keep-0.2.0-offmain-accept-defaults`, and `spec.md` FR-002–FR-026

## Routing boundary

- Product vocabulary/privacy sections apply only to the new Azure Blob product path. The lifecycle/capacity sections also bind the legacy Loki consumer adaptation required by exact `0.2.0`.
- Existing Loki product telemetry and `VoxPocketLogging` do not route through or mirror into this path.
- Product callers use typed APIs. No API accepting an arbitrary event name or property dictionary may be exposed outside the Blob runtime.

## Product event vocabulary

### `product.user_action`

| Property | Type | Allowed values |
|---|---|---|
| `action` | closed string | `settings_opened`, `full_panel_opened`, `quick_record_started`, `quick_record_stopped` |

No other product property is allowed.

### `product.performance`

| Property | Type | Allowed values |
|---|---|---|
| `operation` | closed string | `app_launch` |
| `duration_ms` | finite number | `0...3_600_000` inclusive |

No other product property is allowed.

### `telemetry.heartbeat`

This name is reserved to the shared adapter. It is not part of the product-event count and may contain only the documented content-free operational fields from the pinned dependency. VoxPocket product code must not construct or supplement it.

## Trusted SDK/host fields

The policy explicitly permits only the pinned adapter's required timestamp/provenance fields and trusted built-bundle app/version/build metadata. Product callers cannot override them. Install UUID may be used only where the adapter contract requires operational provenance; it is not a caller property or product/user identity.

## Whole-event rejection

The policy rejects the event before accepted memory, disk, or network state if any of these is true:

- event name, property key, label, timestamp, or provenance is not allowlisted;
- a numeric value is non-finite or outside the declared range;
- any generic/free-text, identifier, URL, endpoint, credential, error, or reason field is present;
- any audio, transcript, refined text, prompt, model/deployment name, session/user identifier, localized/stringified error, SAS, or secret marker is present;
- a product caller attempts to emit `telemetry.heartbeat`.

Rejection diagnostics name only a fixed category such as `unknown_event`, `unknown_key`, `invalid_label`, `invalid_number`, or `forbidden_value_class`. They never echo a supplied name or value.

## Host configuration contract

Source plist entries are exact:

```text
LokiKitBlobEndpoint = $(TELEMETRY_BLOB_ENDPOINT)
LokiKitBlobSAS = $(TELEMETRY_BLOB_SAS)
```

- Missing, empty, or literal unresolved `$(...)` values select disabled behavior before identity/store/network work.
- Present-invalid values select a Blob-only fail-closed state and fixed diagnostic.
- Debug, pull-request, and local credential-free paths do not receive real values.
- Synthetic Release validation supplies only fake non-routable test values, does not send, and inspects the processed plist.
- Real values enter only the explicitly Owner-authorized macOS TestFlight archive from GitHub Actions secrets. CI writes one untracked xcconfig in the runner temporary directory, sets mode `0600`, passes only its path via `-xcconfig`, and removes it through `always`/`ensure`; values never enter xcargs, command-line environment assignments, printable arguments, or logs.
- Release-path tests use synthetic raw and shell/percent-escaped sentinels and require both forms to be absent from captured workflow/Fastlane/xcodebuild logs.

### Production SAS shape

- Decision 1A requires an Owner-created stored access policy using key-based authentication, permission `c`, and an explicit UTC expiry.
- The Owner generates an HTTPS-only container service SAS referencing that policy. The accepted query-name set is the pinned adapter's set; the stored-policy form contains `sr=c`, non-empty `si` and `sig`, optional `sv`, and `spr=https`, and contains no user-delegation fields.
- Permission is carried by the stored access policy, so the emitted stored-policy token normally omits `sp`; if `sp` is present in any accepted non-policy form, it must equal `c`. `sp=cw`, `--as-user`, and user-delegation keys are rejected.
- Representative fixture: `sv=2023-11-03&sr=c&si=synthetic-create-only&spr=https&sig=fake%2Bonly%2F%3D`. The fixture is synthetic and never contacts Azure.

## Concurrency and lifecycle contract

- One app-lifetime lifecycle coordinator is backed by a dedicated serial non-main executor. The canonical `tasks.md` graph introduces it together with exact shared-telemetry `0.2.0` in atomic PR02; there is no standalone PR03 or publishable old-`0.1.0` intermediate. The coordinator lazily constructs the selected legacy provider and exposes only a `TelemetryService` facade to existing callers. PR06 extends the same coordinator to own at most one live Blob adapter/dedicated-store generation while consent is on.
- The coordinator is the sole underlying entry for legacy provider construction/`track`/`flush` and Blob construction/product `track`/lifecycle `flush`. `@MainActor` code submits commands asynchronously and never calls synchronous provider persistence directly. Legacy flush barriers all earlier track submissions, and concurrent flush requests join rather than compete.
- Blob construction omits the `maxDiskBytes` argument and therefore accepts the provider default. Decision 2A exempts only SDK-owned, internally synchronized, content-free `telemetry.heartbeat` startup/daily work initiated by the bundle initializer. The exemption does not permit product-emitted heartbeat, another store owner, host bypass, or synchronous persistence on `@MainActor`.
- Startup records `product.performance(operation: app_launch, duration_ms: ...)`, then requests flush.
- Settings/full-panel/quick-record start/quick-record stop emit only their closed action.
- Recording/session completion requests flush after prior admission has drained.
- macOS resign-active requests a non-blocking best-effort flush.
- One active flush exists at most; later requests join it. Failure/cancellation causes no host/manual deletion, and non-evicted unconfirmed files remain retryable.

## Consent, identity, and host-construction contract

- Settings exposes “Send usage data” through `UserDefaultsPreferencesStore`; absence decodes as `false`, and only an explicit user action changes it to `true`.
- Valid endpoint/SAS configuration is necessary but never sufficient: consent off means zero Blob service construction, admission, or upload.
- The Settings interface persists only the consent Boolean. It never reads, requests, creates, or returns install identity, and missing/invalid configuration retains that explicit choice without provisioning telemetry state.
- Before opt-in, and after opt-in while the host is excluded or configuration is missing/invalid, the host creates/requests no identity. Only the eligible interactive-app composition branch after valid configuration may invoke the existing identity-provisioning interface. Disabling immediately closes admission/upload for the active generation without host/manual deletion and retains non-evicted pending local files plus the persisted install UUID under SDK disable semantics; while off, no active service requests or uses that UUID. Re-enable occurs only after a later explicit opt-in and reuses that same UUID.
- The first eligible interactive-app composition after explicit opt-in creates and persists one random non-personal install UUID. Every later explicit opt-in and eligible launch reuses it for the app installation's lifetime. V1 exposes no install-ID Reset/rotation surface, requires no shared-telemetry API change for identity lifecycle, and performs no host parsing of adapter-private storage or catalog state.
- CLI, headless, and test hosts never provision identity or construct the Blob service, regardless of configuration or persisted test values. Only the interactive app composition root may do either after valid configuration and consent. The repository has no production CLI target, so a negative host-kind fixture covers CLI/headless without adding one.

## Existing Loki privacy hardening

The Loki path remains routing/store-separated, but exact `0.2.0` intentionally changes its execution and retention boundaries. The raw provider is constructed and invoked only by the shared serialized non-main coordinator; existing callers receive its facade. VoxPocket passes no `maxDiskBytes` override, accepting the provider's 50 MiB persisted-data default, whole-oldest-batch eviction, oversized-event rejection, and durable dropped-event/loss-ledger accounting. Existing arbitrary `error.localizedDescription` and stringified `reason` properties remain forbidden; the owning layer replaces them with a closed content-free failure category or omits them while preserving safe durations/counts/event outcomes. Product UI error presentation is not changed.

Rollback stops all producers/active work, prevents old/new writer overlap, and lets the `0.2.0` capacity-aware reader finish pending paired eviction cleanup after storage is writable before any separately reviewed older reader opens the store. Retained files and the loss ledger remain. Already evicted events cannot be recovered, and VoxPocket does not manually delete or convert provider queue files.

## Mechanical evidence

Tests must prove:

1. the two valid product shapes are admitted;
2. every unknown event/key/label and non-finite/out-of-range number is rejected as a whole;
3. transcript, refined-text, audio, prompt, error, endpoint, SAS, UUID, and credential sentinels are absent from persisted bytes, request fixtures, and diagnostics;
4. missing/empty/unexpanded configuration causes zero identity-provider, store, enqueue, and network calls;
5. invalid present configuration fails only Blob closed without value disclosure;
6. direct `@MainActor` persistence is structurally unavailable; a main-actor-originating spy proves legacy provider construction, `track A`, `track B`, and barrier `flush` occur in order, with maximum underlying concurrency one and `Thread.isMainThread == false`; Blob tests prove coordinator-only host construction/`track`/`flush`, ordered admission, joined flush, and retained non-evicted failure/cancellation state; heartbeat fixtures prove bundle startup heartbeat exists, later ticks remain SDK-owned/off-main, and product callers cannot emit it;
7. Loki endpoint/Noop selection, routing, log-sink behavior, and safe vocabulary remain; a structural regression proves the raw provider exists only behind the shared coordinator, no production consumer passes `maxDiskBytes:`, and arbitrary error text is removed;
8. the representative stored-policy query is accepted while `sp=cw`, user-delegation keys, unsupported names, and invalid `sr` are rejected;
9. synthetic processed Release plist contains both fully expanded fake values and no unresolved build-setting reference; TestFlight packaging logs contain neither raw nor escaped sentinels and expose no value-bearing argument.
10. a fresh preference suite defaults consent off; the additive consent-only interface persists/reloads `true` while leaving the identity key absent and generator uncalled; the accepted coupled provisioning interface and its existing tests remain unchanged;
11. the actual Settings/runtime transition with missing/unexpanded or present-invalid configuration persists consent but records zero construction/admission/upload plus zero identity creation/provider request; only the eligible interactive-app branch provisions the first random UUID, and every later explicit opt-in and eligible relaunch reuses it for the app installation's lifetime;
12. disable causes no host/manual deletion, retains non-evicted pending files plus the persisted UUID, and prevents active-service identity use; no v1 Reset/rotation surface or private-storage parsing exists, and no identity value appears in a product property, diagnostic, or evidence fixture;
13. CLI, headless, and test host fixtures record zero identity provisioning and zero Blob-service construction even with valid synthetic configuration and consent set true;
14. rapid-release and startup/recording/session/resign-active regressions drive the real `AppDelegate` / `ServiceContainer` production callers through narrow app-shell test seams; direct instrumentation invocation is supplemental and cannot be the only evidence;
15. planning and migration evidence records the accepted 50 MiB default, whole-oldest-batch eviction, oversized-event rejection, durable loss accounting, cleanup-before-rollback rule, and irrecoverability of already evicted events without restating them as a no-loss guarantee.
