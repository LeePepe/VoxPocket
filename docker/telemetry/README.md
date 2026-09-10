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

Then launch VoxPocket with:

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
keeping console logging. Release/iOS builds require an explicit `LOKI_ENDPOINT`;
on a phone, localhost is the phone itself, not the Mac. The shared Compose stack
binds to the Mac's loopback interface only.

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
