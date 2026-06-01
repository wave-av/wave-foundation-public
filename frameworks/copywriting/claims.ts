// WAVE copywriting — CLAIMS REGISTER (canonical data model).
//
// This is the foundation reference type behind the copywriting standard. Each WAVE surface
// (spoke page, docs portal, marketing site) keeps its own claims register — a single source of
// truth for what that surface may assert — and copies these types verbatim.
//
// RULE: only `substantiated` claims may be rendered in live copy. `inProgress` / `required` are
// tracked so they can be promoted later once backed by a status page, a measurement, or a shipped
// feature — they MUST NOT appear in user-facing strings until then.
//
// Proven identical in wave-av/wave-www (content/claims.ts) and wave-av/wave-developer
// (content/claims.ts), audited 2026-05-31. Harvested into the foundation as the canonical model.
// See frameworks/copywriting/claims-register.md for the standard and workflow.

/**
 * Lifecycle of a marketing/product claim.
 *
 * - `required`      — the claim is desired but unsupported (often fabricated, e.g. ROI with zero
 *                     customers). DO NOT RENDER. It exists in the register to be explicitly tracked
 *                     and refused, not silently re-introduced.
 * - `inProgress`    — the claim has a path to truth but is not yet backed (no measurement, no cert,
 *                     a count that drifts). DO NOT RENDER until promoted.
 * - `substantiated` — the claim is backed by real evidence (a shipped feature, a legal page, the
 *                     actual infra stack, a public measurement). Safe to render.
 *
 * Promotion only ever moves toward `substantiated`: `required` → `inProgress` (a path/evidence link
 * appears) → `substantiated` (the evidence is proven). Demotion is allowed if backing is withdrawn.
 */
export type ClaimStatus = "substantiated" | "inProgress" | "required";

export interface Claim {
  /** Stable identifier, kebab-case (e.g. "open-protocol"). */
  id: string;
  /** The exact assertion as it would appear in copy. */
  text: string;
  status: ClaimStatus;
  /** What substantiates it. Only meaningful for `substantiated` claims. */
  backing?: string;
  /** Why it is withheld. Used for `inProgress` / `required` claims. */
  note?: string;
}

/**
 * The ONLY claims a surface may render in live copy: those proven `substantiated`.
 * Pass the surface's own `CLAIMS` array; everything `inProgress` / `required` is withheld.
 *
 *   import { CLAIMS } from "./claims-register-for-this-surface";
 *   const safe = renderable(CLAIMS); // -> only substantiated claims
 */
export const renderable = (claims: Claim[]): Claim[] =>
  claims.filter((c) => c.status === "substantiated");

/** True iff a claim is safe to render in live copy. */
export const isRenderable = (claim: Claim): boolean => claim.status === "substantiated";
