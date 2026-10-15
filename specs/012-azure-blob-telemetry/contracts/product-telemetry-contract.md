# Contract: VoxPocket Blob product telemetry

**Contract version**: 3

**Authority**: MY-1818 issue revision 1, MY-1841 common consent contract, Constitution IV, and `spec.md` FR-002–FR-024

## Routing boundary

- This contract applies only to the new Azure Blob product path.
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

- One non-`@MainActor` actor owns at most one live adapter/dedicated-store generation while consent is on. It invokes the exact `AzureBlobTelemetryService(bundle:app:build:version:privacy:storeDirectory:isEnabled:identityProvider:configuration:maxDiskBytes:)` initializer during actor-isolated asynchronous bootstrap.
- The host actor is the sole host entry for construction, product `track`, and lifecycle `flush`. `@MainActor` code submits typed commands asynchronously and never calls synchronous adapter persistence directly.
- Decision 2A exempts only SDK-owned, internally synchronized, content-free `telemetry.heartbeat` startup/daily work initiated by that bundle initializer. The exemption does not permit product-emitted heartbeat, another store owner, host bypass, or synchronous persistence on `@MainActor`.
- Startup records `product.performance(operation: app_launch, duration_ms: ...)`, then requests flush.
- Settings/full-panel/quick-record start/quick-record stop emit only their closed action.
- Recording/session completion requests flush after prior admission has drained.
- macOS resign-active requests a non-blocking best-effort flush.
- One active flush exists at most; later requests join it. Failure/cancellation leaves unconfirmed files retryable.

## Consent, identity, and host-construction contract

- Settings exposes “Send usage data” through `UserDefaultsPreferencesStore`; absence decodes as `false`, and only an explicit user action changes it to `true`.
- Valid endpoint/SAS configuration is necessary but never sufficient: consent off means zero Blob service construction, admission, or upload.
- Before first opt-in, the host creates/requests no identity. Disabling immediately closes admission/upload for the active generation and retains pending local files plus any persisted install UUID under SDK disable semantics; while off, no active service requests or uses that UUID. Re-enable occurs only after a later explicit opt-in and reuses the retained UUID unless Reset replaced it.
- First opt-in creates and persists one random non-personal install UUID. Eligible launches reuse it. Reset before first opt-in is a no-op. When the UUID exists, the Settings Reset action atomically replaces it while consent is off or on without enabling or otherwise altering consent, rotates a live service generation only in the on case, and ensures newly admitted events use only the replacement.
- CLI, headless, and test hosts never construct the Blob service, regardless of configuration or persisted test values. Only the interactive app composition root may construct after valid configuration and consent. The repository has no production CLI target, so a negative host-kind fixture covers CLI/headless without adding one.

## Existing Loki privacy hardening

The Loki path remains behaviorally separate, but its current arbitrary `error.localizedDescription` and stringified `reason` properties are forbidden. The owning layer must replace them with a closed content-free failure category or omit them while preserving safe durations/counts/event outcomes. Product UI error presentation is not changed.

## Mechanical evidence

Tests must prove:

1. the two valid product shapes are admitted;
2. every unknown event/key/label and non-finite/out-of-range number is rejected as a whole;
3. transcript, refined-text, audio, prompt, error, endpoint, SAS, UUID, and credential sentinels are absent from persisted bytes, request fixtures, and diagnostics;
4. missing/empty/unexpanded configuration causes zero identity-provider, store, enqueue, and network calls;
5. invalid present configuration fails only Blob closed without value disclosure;
6. direct `@MainActor` persistence is structurally unavailable; actor tests prove coordinator-only host construction/`track`/`flush`, ordered admission, joined flush, and retained failure/cancellation state; heartbeat fixtures prove bundle startup heartbeat exists, later ticks remain SDK-owned/off-main, and product callers cannot emit it;
7. existing Loki construction/routing/log-sink behavior remains, with arbitrary error text removed;
8. the representative stored-policy query is accepted while `sp=cw`, user-delegation keys, unsupported names, and invalid `sr` are rejected;
9. synthetic processed Release plist contains both fully expanded fake values and no unresolved build-setting reference; TestFlight packaging logs contain neither raw nor escaped sentinels and expose no value-bearing argument.
10. a fresh preference suite defaults consent off and observes zero construction/admission/upload plus zero identity creation/provider request before first opt-in; disable retains pending files and the persisted UUID while preventing active-service identity use; only a later explicit opt-in resumes and reuses that UUID unless Reset replaced it;
11. Reset before first opt-in creates no identity; first opt-in creates one UUID, eligible relaunch reuses it, and Reset fixtures with that UUID present while off and on replace it without enabling or otherwise changing consent and rotate a live generation only while on; no identity value appears in a product property, diagnostic, or evidence fixture;
12. CLI, headless, and test host fixtures record zero Blob-service construction even with valid synthetic configuration and consent set true.
