# Hardware Tier — WAVE Certified

The Layer-4 (Hardware) program of the [Protocol Plane](README.md). WAVE does **not** build hardware. WAVE certifies hardware: a clear stamp ("WAVE Certified") + an integration story that means broadcast partners can adopt WAVE with minimal engineering work.

## Why a certification tier exists

Three reasons:

1. **Broadcast trust is brand-built** — WAVE needs to feel as professional as Newtek/AJA/Blackmagic to OB-van engineers. A certification artifact attached to a partner product is the strongest possible signal that WAVE "speaks the language" of pro-broadcast.
2. **Network effects** — once a partner gets certified, every other partner has an asymmetric incentive to follow. The first 5 certified partners are hard to land; partners 6-50 follow naturally.
3. **Revenue tier** — certified partners pay an annual fee for the listing + the use of the brand mark. Modest at first; scales with the breadth of the certified product ecosystem.

## What "WAVE Certified" means technically

A partner product is WAVE Certified when:

1. It speaks at least one Protocol Plane protocol (NDI, Dante, SRT, OMT, MoQ) with a `wave-certify` correctness battery passing at the appropriate tier
2. It surfaces a `WAVE Certified` configuration UI: when paired with a WAVE account, the device registers itself and bridges its native protocol into the WAVE plane
3. It complies with the [Auth Token Model](auth-token-model.md) Hardware-tier spec: token in TPM/secure-element, bootstrap-token flow, OTA rotation
4. It is listed at `wave.online/certified/<partner>/<product>` with the signed cert artifact attached

## Partner targets (Wave 1 — outreach matrix)

| Category | Partner | Role | Why first |
|---|---|---|---|
| NDI cameras | **BirdDog** | PTZ + bullet NDI cams | broadest NDI footprint, indie-friendly biz-dev |
| NDI cameras | **PTZOptics** | PTZ NDI cams | low-end market access |
| NDI cameras | **Newtek/Vizrt direct** | NDI reference | strategic — but post-Vizrt-acquisition the biz-dev lane is unclear |
| SDI capture | **AJA** | HELO line, encoder/decoder boxes | broadcast-grade reputation, SDI+NDI dual-spec |
| SDI capture | **Blackmagic Design** | Decklink + Mini Recorder | maker community + small-studio reach |
| SDI capture | **Magewell** | Pro Convert + USB capture | budget-friendly + global reach |
| Dante audio | (post Audinate partnership only — see task #141) | TBD | gated |
| Mixing consoles + audio infra | **Telos Alliance** | Z/IPstream, Axia Livewire | radio + broadcast audio incumbent |
| Mixing consoles | **Wheatstone** | broadcast audio infra | reach into smaller stations |
| OB-van integrators | **NEP**, **Bexel**, **Game Creek** | full van builds | first install gets to define the spec |
| Live streaming hardware encoders | **Teradek** | bonded cellular encoders | mobile / remote production niche |
| Live streaming hardware encoders | **LiveU** | bonded cellular | same niche, larger contracts |

## Outreach playbook (per partner)

1. **Research the partner's developer relations contact** (their dev advocates / SDK channels)
2. **Draft a 3-paragraph pitch email**: WAVE positioning, what certification means for them, what we ask
3. **Schedule a 30-min discovery call**
4. **Following the call**: send the certification spec + sample artifact + integration timeline
5. **6-week pilot**: their engineer + our partner-success lead pair on a single product certification
6. **Public launch**: WAVE blog post + their press release + listing on wave.online/certified

## What we ask of partners

Minimum to certify:
- One protocol passing `wave-certify check` at the relevant tier
- Configuration UI surface that surfaces "Pair with WAVE account" (web link OK; doesn't require native SDK)
- Compliance with the Hardware-tier auth spec (TPM token storage on devices that support TPM; secure-element on devices that don't)
- Listing fee (TBD; envelope $2k-$50k/yr depending on partner size and product count)

## What we give partners

In return:
- `WAVE Certified` brand mark + usage license
- Listing on `wave.online/certified` (high SEO value)
- Inclusion in our public broadcast case studies
- Co-marketing at NAB, IBC, IBC LA, broadcast trade shows
- Direct access to our protocol engineering team for integration questions
- Per-protocol bridge container integration (we maintain the cloud-side bridge; they maintain the device-side conformance)

## Certification artifact lifecycle

```
1. Partner runs wave-certify check --target <device-addr> --protocol <p>
2. CLI emits cert-2026-05-30-abc123.json (signed by partner's pre-registered key)
3. wave-certify submit posts to gateway
4. Gateway publishes at wave.online/certified/<partner>/<product>
5. Listing renders the artifact + freshness timestamp
6. Annual re-cert required (artifact has 365-day TTL)
```

## Open biz-dev questions

1. Listing fee structure: flat per-year vs per-product?
2. Tiered certification (Bronze/Silver/Gold based on protocol breadth)?
3. Partner marketing materials: do we provide assets, or do they?
4. Conflict resolution: if a partner ships a non-conforming firmware update, what's the de-certification process?
5. WAVE Certified hardware vs WAVE Certified Studio (the OB-van install kit) — different tiers?

## Linked

- [Protocol Plane](README.md) — Layer 4 of the architecture
- [wave-certify CLI](https://github.com/wave-av/wave-certify) — the validation tool
- [Auth Token Model](auth-token-model.md) — Hardware-tier token specifics
- task #151 — the live partner outreach matrix (this doc is the spec; #151 is the execution)
