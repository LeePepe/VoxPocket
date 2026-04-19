# Telemetry Stack

The Loki + Grafana stack has been extracted to a standalone repo at:

```
~/Development/loki-telemetry-stack
```

## Quick Start

```bash
cd ~/Development/loki-telemetry-stack
docker compose up -d
```

Then launch VoxPocket with:

```bash
export LOKI_ENDPOINT=http://localhost:3100/loki/api/v1/push
```

- **Grafana**: http://localhost:3010 (admin / telemetry)
- **Loki**: http://localhost:3100

## VoxPocket Dashboard

The VoxPocket Grafana dashboard lives in the shared repo at:
`grafana/dashboards/voxpocket.json`

To update it: edit the JSON in `loki-telemetry-stack` and restart Grafana.
