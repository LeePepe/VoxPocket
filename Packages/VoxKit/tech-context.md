---
id: VoxKit
layer: VoxKit
owns: [Packages/VoxKit/**]
depends_on: []
gate: {build: "swift build --package-path Packages/VoxKit", test: "swift test --package-path Packages/VoxKit"}
red_lines: ["R1 SDK has no environment, file, configuration, defaults, bundle, or keychain reads; storage is injected", "R2 no LokiKit, shared-telemetry, or external path dependencies", "R3 StaticString structured logging and telemetry carry metrics/labels only; canary tests prove no content leaks", "R4 public APIs use async/await and AsyncStream/AsyncThrowingStream; no Combine or escaping callbacks", "R5 no product-name paths, internal issue IDs, or non-example Azure hosts"]
roles:
  Types: [VoxCore]
  Config: [VoxStorageLocations]
  Service: [VoxLogger, VoxTelemetry]
test: swift test --package-path Packages/VoxKit
targets: [VoxCore, VoxCoreTests]
Last-Reviewed: 2026-11-05
---

# VoxKit Tech Context

`VoxKit` is the standalone SDK boundary. `VoxCore` contains dependency-free public
contracts and safe value types; hosts inject credentials, logging, telemetry, and storage.
The package must remain independent from VoxDomain, LokiKit, shared-telemetry, and the app.
