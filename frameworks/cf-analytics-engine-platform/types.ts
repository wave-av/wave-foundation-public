// Shared types for Cloudflare Analytics Engine per-tenant attribution.
// CF Analytics Engine is a time-series store. For for-Platforms, we share ONE dataset across
// tenants and tag every event with `tenant_id` as a blob/index, then auto-filter at query time
// (cheaper than dataset-per-tenant; AE pricing rewards shared datasets).

export type TenantId = string;

export interface AnalyticsDatasetBinding {
  binding: string;     // Worker binding name, e.g. "ANALYTICS"
  dataset: string;     // CF Analytics Engine dataset name
}

export interface AnalyticsEvent {
  /** Indexed by AE. WAVE convention: index[0] = tenant_id, index[1..] = user-defined. */
  indexes: [TenantId, ...string[]];
  /** Up to 20 blob fields. */
  blobs?: (string | number | null)[];
  /** Up to 20 numeric fields. */
  doubles?: number[];
}

export class AnalyticsEngineError extends Error {
  constructor(message: string, public readonly code: string, public readonly cause?: unknown) {
    super(message);
    this.name = "AnalyticsEngineError";
  }
}
