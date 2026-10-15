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
| SAS | processed `LokiKitBlobSAS` | non-empty, expanded, accepted create/write-only adapter intent |
| app/version/build | trusted built bundle | non-empty and explicitly policy-allowlisted |

State machine:

```text
raw plist
  ├─ either value missing/empty/unexpanded -> disabled
  ├─ both present but invalid              -> invalid (Blob closed)
  └─ both valid                            -> enabled
```

`disabled` and `invalid` construct no usable network receiver. `disabled` requests no identity and opens no store. Diagnostics are fixed categories only.

## BlobInstallIdentity

- Random non-personal UUID.
- Created only when valid enabled configuration initializes a new store or when an explicit reset is performed.
- Never derived from Apple ID, device name, username, audio, transcript, session data, or other account/user content.
- Not accepted as a product-event property.

## BlobTelemetryStore

- Dedicated Application Support directory owned by one Blob runtime.
- Contains adapter catalog, pending event files, sidecars, and capacity/loss ledger as defined by the pinned shared-telemetry contract.
- Never aliases the existing Loki event store or `VoxPocketLogging` queue.
- Confirmed uploads may be removed by the adapter; unconfirmed, failed, cancelled, rollback, or shutdown-pending files remain.

## BlobTelemetryLifecycleCoordinator

Non-`@MainActor` actor retained for the app lifetime.

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
2. Admission order is serialized.
3. `track`/local persistence never executes on `@MainActor`.
4. Enabled-service/store construction occurs during actor-isolated asynchronous bootstrap, not in caller-side initialization.
5. Flush begins only after earlier actor admission commands.
6. A concurrent flush request joins the active flush; it does not create a second sender.
7. UI/lifecycle callers schedule work asynchronously and never wait on synchronous file I/O.

## DeliveryEvidence

Allowed fields only:

- exact repository revision and workflow/run reference;
- TestFlight build number;
- blob name from read-only listing;
- terminal result category.

Payloads, endpoint/account/container identifiers, SAS values, logs containing those values, and user content are never evidence fields.

## Migration and rollback

There is no Loki-data migration. Enabling Blob creates only the dedicated store. Rollback disables/stops the Blob owner, retains every unconfirmed Blob file, restores the prior dependency/configuration, and leaves Loki data untouched. Re-enabling must use a compatible adapter and the same dedicated-store contract.
