# Telemetry Stack

The Loki + Grafana stack has been extracted to a standalone repo at:

```
~/Development/LokiKit
```

## Quick Start

```bash
cd ~/Development/LokiKit
docker compose -f stack/docker-compose.yml up -d
```

For an explicit endpoint, launch VoxPocket from an environment containing:

```bash
export LOKI_ENDPOINT=http://localhost:3100/loki/api/v1/push
```

- **Grafana**: http://localhost:3010 (admin / telemetry)
- **Loki**: http://localhost:3100

## VoxPocket Dashboard

The VoxPocket Grafana dashboard lives in the shared repo at:
`stack/grafana/dashboards/voxpocket-logs.json`

Open http://localhost:3010/d/voxpocket-logs for ordinary application logs.
Grafana polls dashboard files every 30 seconds.

macOS Debug builds automatically mirror `PrintLogger` output to localhost while
keeping console logging. macOS Release/TestFlight builds require explicit opt-in.
For ordinary Finder/TestFlight launches, the App now also reads a persistent,
non-secret boolean in its own sandbox preferences:

```bash
# Run as the App's macOS user. Only this preference key is changed.
defaults write "$HOME/Library/Containers/com.leepepe.voxpocket/Data/Library/Preferences/com.leepepe.voxpocket" \
  VoxPocketLocalLokiLoggingEnabled -bool true
```

After saving any text and stopping recording, quit and reopen the installed App.
This preference is supported by builds containing this change; build 39 does not
read it. Setting a preference does not update an already-installed binary.
Opt-in sends only to `http://localhost:3100/loki/api/v1/push`; it does not configure
a remote collector or store a token. The shared Compose stack remains loopback-only.

Set the same key to `-bool false` to disable automatic local upload, including in
Debug. Deleting only this key restores build defaults (Debug on, Release off).
An explicit `LOKI_ENDPOINT` has priority over the preference; an invalid explicit
endpoint disables upload instead of silently falling back. Invalid preference
types fail closed. Existing redaction and queue limits are unchanged.

iOS builds still require an explicit `LOKI_ENDPOINT` and ignore this local Mac
preference; on a phone, localhost is the phone itself, not the Mac.

Verify application log records with `app="VoxPocket", stream="log"` and the
installed build label. A successful SDK test or saved preference is not evidence
that the real App has emitted records. CI runs configuration regressions in both
Debug and Release via `python3 scripts/tests/test_app_logging.py`.

The uploader flushes every 2 seconds (up to 200 records per batch), buffers up to
1,000 records, and retries after failures. During outages the oldest records are
dropped at the limit. Filtered pending records are saved to
`Application Support/VoxPocket/logs/pending.json` inside the app sandbox and
replayed after relaunch. The most recent unflushed records can be lost on exit;
this is diagnostic logging, not an audit trail or crash reporting.

Privacy: only exact, reviewed message strings and allowlisted numeric context
fields are uploaded. Other messages become `[dynamic message redacted]`; their
level, subsystem and source location remain searchable. Transcript, prompt,
response bodies, arbitrary error descriptions and credentials are not uploaded.
See `VoxPocketLogging.swift` for the policy. Existing telemetry events are separate
from the new `{app="VoxPocket",stream="log"}` stream.
