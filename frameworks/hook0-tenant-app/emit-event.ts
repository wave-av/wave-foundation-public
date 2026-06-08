// emit-event.ts
//
// Emit an event to a tenant's Hook0 application. The application_secret carries the
// scoping — events emitted with tenant A's secret can never fan out to tenant B's
// subscribers. Wrapper enforces shape + size caps to prevent runaway payloads.

import { Hook0Error, Hook0Event } from "./types.js";

const URL_REGEX = /^https:\/\/[^\s]+$/;
const EVENT_TYPE_REGEX = /^[a-z][a-z0-9_.]{0,127}$/;
const ISO_REGEX = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z?$/;
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_PAYLOAD_BYTES = 256 * 1024; // 256 KB — generous but bounded.

export interface EmitInput {
  base_url: string;
  application_secret: string;
  event: Hook0Event;
}

export async function emitHook0Event(
  input: EmitInput,
  fetchImpl: typeof fetch = fetch,
): Promise<{ event_id: string; accepted_at: string }> {
  if (!URL_REGEX.test(input.base_url)) {
    throw new Hook0Error("base_url must be https", "INVALID_BASE_URL");
  }
  if (!input.application_secret || input.application_secret.length < 20) {
    throw new Hook0Error("invalid application_secret", "INVALID_APP_SECRET");
  }
  if (!UUID_REGEX.test(input.event.event_id)) {
    throw new Hook0Error("event_id must be UUID", "INVALID_EVENT_ID");
  }
  if (!EVENT_TYPE_REGEX.test(input.event.event_type)) {
    throw new Hook0Error("invalid event_type", "INVALID_EVENT_TYPE");
  }
  if (!ISO_REGEX.test(input.event.occurred_at)) {
    throw new Hook0Error("invalid occurred_at (RFC3339)", "INVALID_TIMESTAMP");
  }

  const body = JSON.stringify({
    event_id: input.event.event_id,
    event_type: input.event.event_type,
    occurred_at: input.event.occurred_at,
    payload: input.event.payload,
    labels: input.event.labels ?? {},
  });
  if (new TextEncoder().encode(body).byteLength > MAX_PAYLOAD_BYTES) {
    throw new Hook0Error("payload > 256KB", "PAYLOAD_TOO_LARGE");
  }

  const baseUrl = input.base_url.replace(/\/+$/, "");
  let res: Response;
  try {
    res = await fetchImpl(`${baseUrl}/api/v1/event`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${input.application_secret}`,
        "Content-Type": "application/json",
      },
      body,
    });
  } catch (err) {
    throw new Hook0Error("hook0 emit fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    throw new Hook0Error(
      `hook0 emit ${res.status}`,
      res.status === 401 ? "UNAUTHORIZED" : "API_ERROR",
    );
  }
  return { event_id: input.event.event_id, accepted_at: new Date().toISOString() };
}
