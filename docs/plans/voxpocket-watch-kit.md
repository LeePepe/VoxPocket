# VoxPocket Watch Kit — approved implementation record

## Scope

The Watch app is a single-screen recorder: one primary record/stop control, a seven-column waveform driven by bounded audio samples, elapsed duration, and one latest correlated phone receipt. The Watch does not manage a Todo list or history. The iPhone owns file transcription, optional refinement, Todo persistence, and receipt delivery.

## Recovery contract

Capture metadata is versioned and validated at the transport seam: UUID correlation, finite bounded duration, Apple Watch origin, AAC m4a type, UUID-only basename, and bounded file size. Incoming files are copied into Application Support before callback completion. Pending files survive relaunch; only terminal `todoAdded` receipts are cached. Failed work remains retryable for the same capture ID.

App-side ingestion reconciles deterministically: an existing matching Watch Todo wins and repairs its capture link; an orphan matching capture is converted exactly once; a linked capture without its Todo is a consistency failure; a new capture is created only when neither record exists. All content stays in the app sandbox and never enters logs or telemetry.

## Production integration and compatibility

The Watch sender journals UUID correlation and enqueue ownership before transfer, restores
pending captures at activation, and checks outstanding WCSession transfers before replay.
Receipts always use durable `transferUserInfo`; reachable message-data delivery is additive
and has matching receiving callbacks. A successful receipt cannot regress to processing.
Retry resends retained audio; the primary orb can start another recording with a fresh UUID.
Permission/start/stop transitions lock the primary action only transiently.

Phone file ownership is established synchronously on the WCSession callback queue using
metadata-first staging, a partial-file rename and an atomic UUID-directory commit. Recovery
scans committed/staged journals, not arbitrary persisted paths. Legacy flat UUID AAC files
are recovered using their actual audio duration; the prior typed pending/success journal is
migrated without perpetuating failed completion entries. Corrupt/invalid files remain unprocessed;
sender audio remains available for retry. Existing matching Watch Todo/Capture rows are
reconciled through the existing use case, including its three save windows. No transaction
semantics in the existing use case have changed.

File recognition uses an isolated authorized Apple Speech URL request (`zh-Hans`) with a
once-guard, cancellation and a 45-second bound. A fresh isolated refinement runner snapshots the app's current configured preset for each
file, uses a 20-second bound and preserves raw recognition on unavailable/failed refinement.
Processing awaits app startup and persistence readiness outside container initialization.
Background expiration preserves pending work; foreground re-entry scans/replays the inbox.
Locked-phone/background recognition is not guaranteed.

The real WidgetKit accessory extension and App Shortcut open the same recorder/start
route; a strictly validated app-open URL also handles accessory-family launch fallback.
Early intents are buffered until the shared model is installed; active start is idempotent. Action Button availability depends on supported
Apple Watch hardware and system configuration. The one-screen layout uses native glass,
semantic appearance assets, a solid reduced-transparency fallback, reduced-motion waveform
updates, wrapped titles and a 72–104-point adaptive primary control. The native style is
bounded at the control, not its padded label. The recorder stays first during active/start/
stop transitions; otherwise the latest receipt and recoverable inline retry use the permitted
top placement so a small Watch does not hide the consequence below the recorder.
Watch color polarity is selected explicitly from named canvas/text/card assets by color
scheme: watchOS does not reliably resolve luminosity asset variants or system primary/
secondary text under forced light appearance. The snapshot host supplies that scheme
explicitly; ordinary launches retain their native system scheme.

## Verification and release prerequisites

Causal package tests cover audio settings/lifecycle/errors/cancellation, finite duration and
metering, offline sender relaunch/outstanding-transfer deduplication, atomic inbox recovery,
paired failure-then-success retry and deferred cancellation recovery. App tests execute the
actual existing Todo use case and disk repositories through each save window, plus missing
links, concurrent duplicates, once-guard races and Watch primary/retry state transitions.
The simulator-only Debug launch harness injects deterministic audio/transport into the real
production Watch view; it is absent from device/Release builds and has no on-screen controls.
Native screenshot evidence belongs outside Git and must be independently reviewed.

XcodeGen remains the source of truth, with a dedicated Watch scheme and an unchanged main
scheme target set. Watch app/complication Release signing remains manual. When
`VOXPOCKET_WATCH_PROFILE_SPECIFIER` or `VOXPOCKET_WATCH_COMPLICATION_PROFILE_SPECIFIER` is
not pre-supplied, Fastlane idempotently registers the missing Watch bundle IDs via the App
Store Connect API (`Spaceship::ConnectAPI::BundleId`) and fetches/creates their App Store
provisioning profiles, failing closed when either profile mapping remains empty. Existing
macOS delivery is unchanged. Unsigned builds do not establish Release signing or TestFlight
distribution; this record makes no release claim.
