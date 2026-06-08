# Per-layer capabilities.json examples

One worked example for each WAVE Protocol Plane layer + non-plane categories. Use these as starting points when filling in a new repo.

## Layer 0 — Operator (Electron apps + plugins)

[`wave-monitor`](./capabilities.example.json) — minimal viewer app.

Other Layer 0 patterns:

- **wave-desktop**: `exposes.renderSurfaces[].kind = "electron-app"`, `consumes.thirdParty` includes Keychain/DPAPI via `safeStorage`, `events.publishes` includes `auth.signed-in`.
- **obs-wave-plugin**: `exposes.renderSurfaces[].kind = "obs-plugin"`, `consumes.thirdParty = [{ service: "obsproject" }]`.
- **vmix-wave-integration**: `exposes.renderSurfaces[].kind = "vmix-titles"`, the companion sidecar appears separately as a Node service with its own `apis` entry.

## Layer 1 — Edge

- **wave-realtime-edge**: `exposes.apis = [{ protocol: "webrtc-whip", endpoint: "https://rt.wave.online/whip" }, { protocol: "webrtc-whep", endpoint: "https://rt.wave.online/whep" }]`, `events.publishes = [{ topic: "rtc.session.opened", transport: "x402-meter" }]`.
- **api-gateway**: `exposes.apis` with every public endpoint enumerated, each with an `openapiRef`.

## Layer 2 — Bridges

- **wave-bridge-edge**: `consumes.thirdParty = [{ service: "audinate-dante", licenseGated: true }, { service: "vizrt-ndi", licenseGated: true }]`, `exposes.apis` for each protocol bridge endpoint.
- **transport-library**: `lifecycle: "ga"` for SRT, `"alpha"` for the dante subtree until #157 ships.

## Layer 3 — Local

- **wave-agent**: `exposes.hardwareDrivers` enumerates every supported edge device family.
- **flash-cli**: `exposes.cli = [{ binary: "flash" }]`.

## Layer 4 — Hardware

Hardware repos (designs, profiles, certify CLI) typically only `expose` and don't `consume` runtime WAVE products. Use the `tags` array to mark `"hardware-spec"` so the aggregator groups them.

- **wave-certify**: `exposes.cli`, `consumes.foundationFrameworks = ["frameworks/protocol-plane"]`.
- **wave-hardware-designs**: nothing in `exposes` (it's just CAD); `tags = ["hardware-spec", "openscad"]`.

## Non-plane: SDKs, marketing sites, agent tools

For repos that don't fit a layer, set `planeLayer: null` and lean on `tags`:

- **sdks** (TypeScript open-core): `tags = ["sdk", "public", "open-core"]`, `consumes.waveProducts = [{ repo: "wave-av/api-spec" }]`.
- **wave-www** (apex marketing site): `tags = ["marketing", "public", "cloudflare-worker"]`.
- **adk** (Agent Developer Kit): `exposes.mcpTools` enumerates every tool the kit registers.

## Build-on-WAVE meta

Any repo that doubles as a public reference implementation for `frameworks/build-on-wave/` should add the `"build-on-wave"` tag. The aggregator promotes those into the build-on-wave hub automatically — single source of truth.
