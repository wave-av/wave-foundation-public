# Video Pipeline

MUX-specific patterns for upload → process → deliver → archive. Pairs with [realtime-media](../realtime-media/README.md) (LiveKit). The WAVE Audio Library plan defines the asset taxonomy (separate memory; not in this repo).

## Upload pattern

```ts
// 1. Server creates upload URL (short-lived)
const upload = await mux.video.uploads.create({
  cors_origin: APP_ORIGIN,
  new_asset_settings: {
    playback_policy: ["signed"],     // ALWAYS signed for user content
    encoding_tier: "smart",          // default tier
    mp4_support: "none",             // enable per-asset only when needed
  },
});

// 2. Client uploads directly to upload.url (Tus protocol)
// 3. Webhook (video.asset.ready) fires -> follow the webhooks framework
```

## Playback ID hygiene

- `public` playback IDs only for explicitly-public content (marketing, docs videos)
- `signed` playback IDs for everything user-generated, paid, or auth-required
- JWT signing keys live in env (`MUX_SIGNING_KEY_ID` + `MUX_SIGNING_KEY_PRIVATE`)
- JWT expiry: 1 hour for streamable content, 5 minutes for thumbnails

## Restrictions

Apply `playback_restriction` to every signed playback ID:

- `allowed_domains`: production hostnames only
- `allow_no_referrer`: false (block direct curl)
- `user_agent_restriction.allow_high_risk_user_agents`: false (block scraping)

## Asset lifecycle

| State | Action | Cost notes |
|-------|--------|------------|
| Upload pending | wait for webhook | free until processing |
| Processing | poll status via webhook only | encoding charge starts |
| Ready | playback ID issued | storage + delivery |
| Archived | move to `archived` via API | storage tier drops |
| Deleted | DSAR or explicit user action | irreversible — confirm |

Run `scripts/mux-audit.ts` weekly per app: flag assets with > 0 deliveries that lack restrictions, flag orphaned MP4 renditions, flag assets > 90 days untouched as archive candidates.

## Live streams

- Always `complete_live_streams` after a broadcast ends.
- `reset_stream_key` on rotation or compromise.
- Simulcast targets (YouTube, Twitch) are config — never hardcode RTMP URLs in code.

## Subtitles & transcripts

- Auto-generate subtitles via MUX `generated_subtitles` per asset.
- Store transcripts in Supabase for search (Phase 4 unified audit ties this to billable actions).

## Env vars

| Var | Purpose |
|-----|---------|
| `MUX_TOKEN_ID` | API auth |
| `MUX_TOKEN_SECRET` | API auth (secret) |
| `MUX_SIGNING_KEY_ID` | playback ID signing |
| `MUX_SIGNING_KEY_PRIVATE` | playback ID signing (PEM) |
| `MUX_WEBHOOK_SECRET` | HMAC for [webhooks](../webhooks/README.md) |
