# Webhook Handler Pattern

Every inbound webhook in a WAVE app — Stripe, Bridge, Vercel platform, GitHub Apps, Mux, Knock, custom — follows this template. The `webhook_pattern` dogfood gate greps tracked handler files for the required signature.

## The five-clause handler

1. **HMAC verify FIRST** (before parsing body):

   ```ts
   const sig = req.headers.get("x-signature");
   const raw = await req.text(); // verify against raw, not parsed JSON
   if (!verify(raw, sig, env.VERCEL_WEBHOOK_SECRET)) return new Response("bad sig", { status: 401 });
   ```

   Use `crypto.timingSafeEqual` or equivalent. Never `===` on hashes.

2. **Replay window** — reject events older than the publisher's documented window (Stripe 5min, Vercel 10min). Compare `timestamp` from the signed payload, never client-supplied headers.

3. **Idempotency** — dedupe by event id (`event.id`, `delivery_id`) in a 24h Redis set OR a `processed_webhook_events` table with `UNIQUE (publisher, event_id)`. Return 2xx on duplicate.

4. **Enqueue, don't process inline** — every webhook handler ends with `await queue.enqueue(...)` and returns 200. Inline processing turns a 30s timeout into a publisher's automatic-retry storm.

5. **DLQ + alert** — the worker that drains the queue follows [`rules/job-queue.md`](../../rules/job-queue.md). DLQ wired to Sentry + PagerDuty.

## Anti-patterns

- ❌ Parsing the body before verifying the signature
- ❌ Comparing signatures with `===` (timing-leak)
- ❌ Reusing the publisher's payload as the idempotency key (use `event.id`)
- ❌ Returning 5xx for "I'm not interested in this event" — return 2xx so the publisher doesn't retry forever

## Required env

| Var | Purpose |
|-----|---------|
| `VERCEL_WEBHOOK_SECRET` | the HMAC key for Vercel platform webhooks |
| (per publisher) | each external publisher's signing secret is its own env var, never reused |

## Test contract

Every handler ships with three tests:

1. Happy path: valid signature → 200 + enqueue called
2. Bad signature → 401 + no enqueue
3. Replay (duplicate `event.id`) → 200 + no second enqueue

## Cross-references

- [`rules/job-queue.md`](../../rules/job-queue.md) — what the enqueued message must look like
- [`frameworks/incident-response/`](../incident-response/README.md) — DLQ paging
