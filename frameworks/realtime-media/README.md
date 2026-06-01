# Real-Time Media

Decision matrix for any audio/video feature in a WAVE app. Two substrates, one decision rule.

## Substrate decision

| Use case | Substrate | Why |
|----------|-----------|-----|
| Interactive 2-way (call, room, agent dialogue) | **LiveKit** | sub-150ms RTT, SFU topology, server-mediated permissions |
| Broadcast 1-many with recording (livestream, podcast publish) | **MUX** | playback-ID per audience, restrictions, durable archive |
| Audio-only ephemeral (voice notes < 60s) | LiveKit egress → S3 | reuse LiveKit infra; MUX is overkill |
| AI voice agent (LLM + ElevenLabs TTS) | LiveKit + ElevenLabs WS | the [voice-role taxonomy](../../taxonomy/voice-roles.json) routes to the right voice |

## LiveKit rules

- **Tokens are minted server-side** with `LIVEKIT_API_KEY` + `_SECRET`. Client never sees secret.
- **Room name is non-guessable** — UUID v4 or HMAC of `(user_id, room_purpose, ts_bucket)`.
- **Permissions are explicit** — `canPublish`, `canSubscribe`, `canPublishData` set per participant. Default deny.
- **ICE/TURN** — use LiveKit Cloud's TURN. Self-hosting TURN means a credentials registry + rotation we don't currently own.
- **Recording** — only via LiveKit Egress to S3/R2. Don't record on the client.

## MUX rules

- **Playback IDs are signed JWTs** when content is restricted. Never use unrestricted IDs for paying-user content.
- **Restrictions** — `domain_restriction` + `user_agent_restriction` set per environment.
- **Asset lifecycle** — uploads → asset → playback ID → optional MP4 rendition. Delete unused renditions to control cost.
- **Live streams** — separate from VOD assets; `complete_live_streams` after each broadcast or they idle-cost.

## Cost guardrails

- LiveKit publish minutes: per-tenant daily cap (alert at 80%)
- MUX delivery: per-asset cap (alert + rate-limit at threshold)
- Egress: separate per substrate, separate alert

## Privacy

- Audio recordings are PII when speakers are identified. Apply [Sentry redaction rules](../../rules/sentry-instrumentation.md) to any logs around recording paths.
- DSAR (data subject access request) deletion MUST cascade to LiveKit Egress S3 + MUX assets.

## Env vars

| Var | Substrate |
|-----|-----------|
| `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` | LiveKit |
| `MUX_TOKEN_ID`, `MUX_TOKEN_SECRET` | MUX |
| `ELEVENLABS_API_KEY` + `ELEVENLABS_*_VOICE_ID` | voice agent path |
