# Data model: Privacy-safe Azure Blob product telemetry

This feature adds no user-facing database. The model is the in-process product-event contract, host configuration state, dedicated retry store, and non-sensitive delivery evidence.

## ProductTelemetryEvent

Closed sum type; callers cannot supply arbitrary names or properties.

| Variant | Required fields | Prohibited fields |
|---|---|---|
| `userAction` | `action: ProductAction` | transcript, refined text, prompt, audio, error/reason, identifier, URL, endpoint, credential, arbitrary metadata |
| `performance` | `operation: ProductOperation`, `durationMilliseconds: finite Double` | all fields prohibited above; negative/non-finite/out-of-range duration |

SDK-owned timestamp/provenance and trusted bundle metadata are added only after product-policy validation. No caller-supplied timestamp, identity, app, version, or build field is accepted.

## ProductAction

Closed enum:

- `settings_opened`
- `full_panel_opened`
- `quick_record_started`
- `quick_record_stopped`

## ProductOperation

Closed enum for this version:

- `app_launch`

## BlobHostConfiguration

| Field | Source | Validation |
|---|---|---|
| endpoint | processed `LokiKitBlobEndpoint` | non-empty, expanded, HTTPS, accepted adapter shape |
| SAS | processed `LokiKitBlobSAS` | non-empty, expanded, HTTPS-only container service SAS bound to a stored access policy; supported names only; `sr=c`; non-empty `si`/`sig`; optional `sv`; `spr=https`; no user-delegation names; explicit `sp`, if any, equals `c` |
| app/version/build | trusted built bundle | non-empty and explicitly policy-allowlisted |

State machine:

```text
raw plist
  ├─ either value missing/empty/unexpanded -> disabled
  ├─ both present but invalid              -> invalid (Blob closed)
  └─ both valid                            -> enabled
```

`disabled` and `invalid` construct no usable network receiver. `disabled` requests no identity and opens no store. A valid configuration remains unconstructed until persisted product-telemetry consent is on. Diagnostics are fixed categories only.

## ProductTelemetryConsent

| Field | Source | Rule |
|---|---|---|
| `sendUsageData` | `UserDefaults` through `UserDefaultsPreferencesStore` | Defaults `false`; only an explicit Settings action sets it `true` |

State transitions:

```text
never-opted-in/off (no UUID) --explicit opt-in--> consented/persisted (still no UUID)
consented/persisted --disable--> off (no UUID)
off (no UUID) --later explicit opt-in--> consented/persisted (still no UUID)
consented/persisted + excluded host or missing/invalid config -> consented/persisted (still no UUID)
consented/persisted + eligible interactive app + valid config -> on (create UUID)
on (UUID active) --disable--> disabled-after-opt-in/off (retain UUID + non-evicted pending files; no host deletion or active use)
disabled-after-opt-in/off --later explicit opt-in--> on (reuse retained UUID)
```

Valid configuration never implies consent. An excluded CLI/headless/test host remains unconstructed in either state.

## BlobInstallIdentity

- Random non-personal UUID.
- Created/requested only by the first eligible interactive-app composition after explicit opt-in has been persisted; missing/invalid configuration and excluded hosts leave consent stored with no UUID. The UUID persists across disable and is reused by every later explicit opt-in and eligible app launch for the app installation's lifetime. While consent is off, the UUID remains stored but is not requested or used by an active service.
- V1 exposes no install-ID Reset or rotation surface, changes no shared-telemetry API for identity lifecycle, and does not parse adapter-private storage or catalog state.
- Never derived from Apple ID, device name, username, audio, transcript, session data, or other account/user content.
- Not accepted as a product-event property.

## BlobTelemetryStore

- Dedicated Application Support directory owned by one Blob runtime.
- Contains adapter catalog, pending event files, sidecars, and capacity/loss ledger as defined by the pinned shared-telemetry contract. VoxPocket omits `maxDiskBytes`, accepting the provider's 50 MiB persisted-data default shared across Blob epochs.
- Never aliases the existing Loki event store or `VoxPocketLogging` queue.
- Confirmed uploads may be removed by the adapter. Capacity may evict whole oldest batches or reject an oversized event and records durable loss; failed/cancelled/shutdown-pending files remain only when not already evicted.

## TelemetryLifecycleCoordinator

App-lifetime coordinator backed by one dedicated serial non-main executor. PR02 introduces it on the old dependency version, lazily constructs the selected legacy provider off-main, and exposes only a `TelemetryService` facade to existing callers; PR03 then changes the provider pin without changing that seam. PR06 extends the same coordinator to own at most one live Blob service generation while consent is on; no second coordinator/executor is created.

State:

```text
legacy-uninitialized -> legacy-ready
legacy-ready + track -> serialized atomic persistence
legacy-ready + flush -> barrier after prior track commands

Blob: disabled | invalid | ready
ready + admitted commands  -> pending local files
ready + flush requested    -> flushing(active task)
flushing + flush requested -> join active task
flushing + success         -> ready (confirmed files retired)
flushing + failure/cancel  -> ready (no host deletion; non-evicted unconfirmed files retained)
```

Invariants:

1. The coordinator is the sole owner/caller of the raw legacy provider and the Blob service/store lease.
2. Legacy provider construction plus every underlying legacy `track`/`flush` executes on the dedicated serial non-main executor; an awaited flush barriers every earlier track submission and joins an active flush.
3. The coordinator invokes the Blob bundle initializer without a `maxDiskBytes` argument and is the sole host entry for product `track` and lifecycle `flush`.
4. Host admission order is serialized and no provider construction, `track`, local persistence, or `flush` executes on `@MainActor`.
5. Enabled-service/store construction occurs during isolated asynchronous bootstrap, not in caller-side initialization.
6. Blob flush begins only after earlier admission commands.
7. A concurrent flush request joins the active flush; it does not create a second sender.
8. UI/lifecycle callers schedule work asynchronously and never wait on synchronous file I/O.
9. Decision 2A exempts only SDK-owned `telemetry.heartbeat` startup/daily work performed under the SDK's own synchronization; product callers cannot emit heartbeat, create another owner, or bypass the host coordinator.
10. Consent persistence is identity-free. Never-opted-in/off, excluded hosts, and missing/invalid configuration create no Blob identity/service/store; only eligible interactive-app composition after persisted opt-in provisions/reuses identity. Disabling after opt-in stops new admission/upload while retaining non-evicted unconfirmed files, capacity ledger state, and the persisted UUID without active-service identity use; every later explicit opt-in and eligible app launch reuses that same UUID for the app installation's lifetime.
11. CLI, headless, and test composition roots never create the Blob service; CLI/headless are negative host-kind fixtures because this repository has no production CLI target.
12. Neither legacy nor Blob construction passes `maxDiskBytes`; both accept the provider-default 50 MiB capacity and loss accounting.

## StoredPolicySASShape

- The Owner creates the stored access policy with key-based authentication, permission `c`, and an explicit UTC expiry.
- The Owner then generates an HTTPS-only container service SAS with `--policy-name` and key-based authentication.
- Representative credential-free fixture: `sv=2023-11-03&sr=c&si=synthetic-create-only&spr=https&sig=fake%2Bonly%2F%3D`.
- In stored-policy form, permission and expiry live on the policy, so the emitted token normally omits `sp`, `st`, and `se`; if `sp` is present in any accepted non-policy fixture it must equal `c`.
- User-delegation keys such as `skoid`, `sktid`, `skt`, `ske`, `sks`, and `skv`, any unknown query name, and `sp=cw` are invalid.

## TestFlightCredentialFile

- One untracked xcconfig under the runner temporary directory, created immediately before archive and mode-checked as `0600`.
- Contains only `TELEMETRY_BLOB_ENDPOINT` and `TELEMETRY_BLOB_SAS` assignments sourced from GitHub Actions secrets.
- Only the file path crosses the workflow/Fastlane/xcodebuild boundary through `-xcconfig`; values never enter xcargs, command-line environment assignments, printable arguments, or logs.
- Deleted in an `always`/`ensure` path on success, failure, and cancellation.

## DeliveryEvidence

Allowed fields only:

- exact repository revision and workflow/run reference;
- TestFlight build number;
- blob name from read-only listing;
- terminal result category.

Payloads, endpoint/account/container identifiers, SAS values, logs containing those values, and user content are never evidence fields.

## Migration and rollback

There is no host-written Loki-data conversion or Loki→Blob migration. Exact `0.2.0` changes legacy admission from caller-side asynchronous enqueue to synchronous atomic persistence performed by the shared non-main coordinator, and applies the accepted provider-default 50 MiB cap to persisted source JSON/Blob sidecars without a consumer override. Whole oldest batches may be evicted, an oversized event may be rejected, and durable loss tombstones remain; already evicted events are unrecoverable.

Rollback stops legacy and Blob producers/active work, prevents old/new writer overlap, makes storage writable, and lets the `0.2.0` capacity-aware reader finish pending paired eviction cleanup before any separately reviewed older reader opens the store. Preserve the loss ledger and retained files so an older reader cannot replay logically dropped batches. Restoring the prior dependency/configuration does not retract transmitted events or recover evicted ones. Re-enabling must use a compatible adapter and the same separate-store contract.
