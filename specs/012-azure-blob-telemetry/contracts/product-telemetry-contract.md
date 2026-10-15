# Contract: VoxPocket Blob product telemetry

**Contract version**: 1

**Authority**: MY-1818 issue revision 1, Constitution IV, and `spec.md` FR-002–FR-016/FR-021

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
- Real values enter only the explicitly Owner-authorized macOS TestFlight archive from GitHub Actions secrets and are never printed.

## Concurrency and lifecycle contract

- One non-`@MainActor` actor owns the adapter and dedicated store for app lifetime. Enabled-service/store construction occurs in actor-isolated asynchronous bootstrap, not synchronously in an initializer invoked by `@MainActor`.
- `@MainActor` code submits a typed event/flush command asynchronously; it never calls synchronous adapter persistence directly.
- Startup records `product.performance(operation: app_launch, duration_ms: ...)`, then requests flush.
- Settings/full-panel/quick-record start/quick-record stop emit only their closed action.
- Recording/session completion requests flush after prior admission has drained.
- macOS resign-active requests a non-blocking best-effort flush.
- One active flush exists at most; later requests join it. Failure/cancellation leaves unconfirmed files retryable.

## Existing Loki privacy hardening

The Loki path remains behaviorally separate, but its current arbitrary `error.localizedDescription` and stringified `reason` properties are forbidden. The owning layer must replace them with a closed content-free failure category or omit them while preserving safe durations/counts/event outcomes. Product UI error presentation is not changed.

## Mechanical evidence

Tests must prove:

1. the two valid product shapes are admitted;
2. every unknown event/key/label and non-finite/out-of-range number is rejected as a whole;
3. transcript, refined-text, audio, prompt, error, endpoint, SAS, UUID, and credential sentinels are absent from persisted bytes, request fixtures, and diagnostics;
4. missing/empty/unexpanded configuration causes zero identity, store, enqueue, and network calls;
5. invalid present configuration fails only Blob closed without value disclosure;
6. direct `@MainActor` persistence is structurally unavailable and actor tests prove ordered admission, joined flush, and retained failure/cancellation state;
7. existing Loki construction/routing/log-sink behavior remains, with arbitrary error text removed;
8. synthetic processed Release plist contains both fully expanded fake values and no unresolved build-setting reference.
