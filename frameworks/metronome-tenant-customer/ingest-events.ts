// ingest-events.ts
//
// Batch usage events to Metronome /ingest. Caller is responsible for stamping the right
// customer_id per event — this wrapper validates shape, enforces batch limits, and forces
// every event through deterministic transaction_id checks so a retry can never double-bill.

import { MetronomeError, UsageEvent } from "./types.js";

const METRONOME_API_BASE = "https://api.metronome.com/v1";
const ISO_REGEX = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z?$/;
const TRANSACTION_ID_REGEX = /^[A-Za-z0-9_:.-]{1,128}$/;
const EVENT_TYPE_REGEX = /^[a-z][a-z0-9_.]{0,127}$/;
const MAX_BATCH = 100;
const MAX_PROPERTIES = 50;

export async function ingestUsageEvents(
  api_key: string,
  events: ReadonlyArray<UsageEvent>,
  fetchImpl: typeof fetch = fetch,
): Promise<{ accepted: number; sent_at: string }> {
  if (!api_key || api_key.length < 20) {
    throw new MetronomeError("invalid metronome api_key", "INVALID_API_KEY");
  }
  if (events.length === 0) {
    throw new MetronomeError("events batch empty", "EMPTY_BATCH");
  }
  if (events.length > MAX_BATCH) {
    throw new MetronomeError(`batch > ${MAX_BATCH}`, "BATCH_TOO_LARGE");
  }

  for (const ev of events) {
    if (!ev.customer_id || typeof ev.customer_id !== "string") {
      throw new MetronomeError("event missing customer_id", "INVALID_TRANSACTION_ID");
    }
    if (!EVENT_TYPE_REGEX.test(ev.event_type)) {
      throw new MetronomeError(`invalid event_type ${ev.event_type}`, "INVALID_EVENT_TYPE");
    }
    if (!ISO_REGEX.test(ev.timestamp)) {
      throw new MetronomeError("invalid timestamp (must be RFC3339)", "INVALID_TIMESTAMP");
    }
    if (!TRANSACTION_ID_REGEX.test(ev.transaction_id)) {
      throw new MetronomeError("invalid transaction_id", "INVALID_TRANSACTION_ID");
    }
    if (Object.keys(ev.properties).length > MAX_PROPERTIES) {
      throw new MetronomeError("too many event properties", "INVALID_PROPERTIES");
    }
  }

  let res: Response;
  try {
    res = await fetchImpl(`${METRONOME_API_BASE}/ingest`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${api_key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(events),
    });
  } catch (err) {
    throw new MetronomeError("metronome ingest fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    throw new MetronomeError(
      `metronome ingest ${res.status}`,
      res.status === 401 ? "UNAUTHORIZED" : "API_ERROR",
    );
  }

  return { accepted: events.length, sent_at: new Date().toISOString() };
}
