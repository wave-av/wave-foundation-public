# Discoverability standard

The single standard for what every WAVE spoke must expose so it is discoverable on **all three sides**:

1. **Human search (SEO)** — `robots.txt`, `sitemap.xml`, canonical + JSON-LD in `<head>`, a raster OG card.
2. **AI answer engines (GEO/AEO)** — `llms.txt`, JSON-LD, structured surfaces that engines can quote/cite.
3. **The agentic web** — `index.json`, `/.well-known/{x402,mcp,did.json}`, `skill.md` so agents can find, call, and pay.

This is the **Part 1** of the WAVE Discoverability Program (see `.claude/plans/wave-discoverability-2026-06-04/`): WAVE's own posture. The generators that *serve* these surfaces live in the spoke-chassis (`packages/spoke-chassis`); this framework owns the **standard** (`surfaces.json`) and the **auditor** that grades any host against it.

## The surface registry — `surfaces.json`

Single source of record. `audit-discoverability.py` reads it; never hardcodes the list. Each surface has a `tier`:

- **required** — a spoke is non-compliant without it; the auditor fails (exit 1) and CI should block.
- **recommended** — advisory; absence lowers no required score but is reported.

| Surface | Tier | Checked |
|---|---|---|
| `/robots.txt` | required | contains `Sitemap:` |
| `/sitemap.xml` | required | contains `<urlset` |
| `/llms.txt` | required | contains `WAVE` |
| `/index.json` | required | JSON keys `name`, `surfaces` |
| `/og.png` | required | content-type `image/png` (SVG never unfurls) |
| `/manifest.webmanifest` | required | JSON key `name` |
| `/.well-known/did.json` | required | JSON keys `id`, `verificationMethod` |
| `/feed.xml` | recommended | contains `<feed` |
| `/.well-known/x402` | recommended | valid JSON |
| `/.well-known/mcp` | recommended | JSON key `mcpServers` |
| `/skill.md` | recommended | served |
| `/security.txt` | recommended | contains `Contact:` |

Plus required `<head>` checks on `/`: `og:image`, `og:title`, `canonical`, `application/ld+json`.

## The auditor — `audit-discoverability.py`

IO is separated from logic (same house style as `frameworks/pricing`): `audit(host, fetched, head, std)` is a **pure** scorer (unit-tested with crafted dicts, no network); `main()` does the live fetch + `<head>` parse, then calls it. Pure stdlib.

```bash
python3 audit-discoverability.py moq.wave.online
# → {"host": "...", "score": 0-100, "violations": [...]}
# exit 0 = no required violations · 1 = required violations · 2 = load/usage error
```

Score = `100 × (required_surfaces_passing / required_total)`. Recommended failures are listed but don't reduce the score.

### Live baseline (2026-06-04)
- `wave.online` → **91** (missing `/.well-known/did.json`).
- `agents.wave.online` → **73** (missing `/index.json`, `/og.png`, `/.well-known/did.json`).

`did.json` is the broken-claim gap closed by chassis ≥ 0.5.0 (`src/did.ts`).

## Tests

```bash
python3 -m pytest tests/ -q   # pure-function teeth tests; prove each violation class is caught
```

## CI gate (rollout)

Wire as advisory first, then promote to blocking once spokes adopt chassis ≥ 0.5.0 (per the `frameworks/gates` + `never-done` conventions). One job per public host: `audit-discoverability.py <host>`; non-zero exit fails the check.
