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
never-opted-in/off (no UUID) --explicit opt-in--> on (create UUID)
on (UUID active) --disable--> disabled-after-opt-in/off (retain UUID + pending files; no active use)
disabled-after-opt-in/off --later explicit opt-in--> on (reuse retained UUID)
never-opted-in/off --Reset--> never-opted-in/off (no UUID created)
disabled-after-opt-in/off or on --Reset--> same consent state (replace UUID; rotate live generation only when on)
```

Valid configuration never implies consent. An excluded CLI/headless/test host remains unconstructed in either state.

## BlobInstallIdentity

- Random non-personal UUID.
- Created/requested only on the first explicit opt-in; persisted across disable and reused by a later explicit opt-in and later eligible app launches unless Reset replaced it. While consent is off, an existing UUID remains stored but is not requested or used by an active service.
- When present, replaced with a new random UUID by the explicit Settings Reset action while consent is either off or on; Reset before first opt-in is a no-op, never enables or otherwise changes consent, rotates a live service generation only when on, and affects newly admitted events.
- Never derived from Apple ID, device name, username, audio, transcript, session data, or other account/user content.
- Not accepted as a product-event property.

## BlobTelemetryStore

- Dedicated Application Support directory owned by one Blob runtime.
- Contains adapter catalog, pending event files, sidecars, and capacity/loss ledger as defined by the pinned shared-telemetry contract.
- Never aliases the existing Loki event store or `VoxPocketLogging` queue.
- Confirmed uploads may be removed by the adapter; unconfirmed, failed, cancelled, rollback, or shutdown-pending files remain.

## BlobTelemetryLifecycleCoordinator

Non-`@MainActor` actor that owns at most one live service generation while consent is on.

State:

```text
disabled | invalid | ready
ready + admitted commands -> pending local files
ready + flush requested   -> flushing(active task)
flushing + flush requested -> join active task
flushing + success         -> ready (confirmed files retired)
flushing + failure/cancel  -> ready (unconfirmed files retained)
```

Invariants:

1. The actor is the sole owner of the Blob service and store lease.
2. The actor invokes the exact bundle initializer and is the sole host entry for product `track` and lifecycle `flush`.
3. Host admission order is serialized and host `track`/local persistence never executes on `@MainActor`.
4. Enabled-service/store construction occurs during actor-isolated asynchronous bootstrap, not in caller-side initialization.
5. Flush begins only after earlier actor admission commands.
6. A concurrent flush request joins the active flush; it does not create a second sender.
7. UI/lifecycle callers schedule work asynchronously and never wait on synchronous file I/O.
8. Decision 2A exempts only SDK-owned `telemetry.heartbeat` startup/daily work performed under the SDK's own synchronization; product callers cannot emit heartbeat, create another owner, or bypass the host actor.
9. Never-opted-in/off creates no identity/service/store and pre-opt-in Reset is a no-op. Disabling after opt-in stops new admission/upload while retaining unconfirmed files, store state, and the persisted UUID without active-service identity use; a later explicit opt-in reuses that UUID unless Reset replaced it. Reset with an existing UUID preserves the off/on consent state and rotates a live generation only when on.
10. CLI, headless, and test composition roots never create the Blob service; CLI/headless are negative host-kind fixtures because this repository has no production CLI target.

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

There is no Loki-data migration. Enabling Blob creates only the dedicated store. Rollback disables/stops the Blob owner, retains every unconfirmed Blob file, restores the prior dependency/configuration, and leaves Loki data untouched. Re-enabling must use a compatible adapter and the same dedicated-store contract.
