// write-event.ts
//
// Tenant-tagged event writer for Cloudflare Analytics Engine.
// Caller supplies the AE binding from the Worker env; we always inject tenant_id as index[0].

import { AnalyticsEngineError, AnalyticsEvent, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;

// Cloudflare AE binding shape (subset).
export interface AEDataset {
  writeDataPoint(point: {
    indexes?: string[];
    blobs?: (string | number | null)[];
    doubles?: number[];
  }): void;
}

export interface WriteInput {
  tenant_id: TenantId;
  /** Caller-defined indexes, prepended with tenant_id. */
  extra_indexes?: string[];
  blobs?: (string | number | null)[];
  doubles?: number[];
}

export function writeTenantEvent(dataset: AEDataset, input: WriteInput): void {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new AnalyticsEngineError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  const indexes = [input.tenant_id, ...(input.extra_indexes ?? [])];
  if (indexes.length > 1 + 19) {
    // AE caps at 20 indexes total — leave one slot for tenant_id
    throw new AnalyticsEngineError("too many indexes (max 19 extra)", "TOO_MANY_INDEXES");
  }
  if ((input.blobs?.length ?? 0) > 20) {
    throw new AnalyticsEngineError("too many blobs (max 20)", "TOO_MANY_BLOBS");
  }
  if ((input.doubles?.length ?? 0) > 20) {
    throw new AnalyticsEngineError("too many doubles (max 20)", "TOO_MANY_DOUBLES");
  }

  dataset.writeDataPoint({
    indexes,
    blobs: input.blobs,
    doubles: input.doubles,
  });
}
