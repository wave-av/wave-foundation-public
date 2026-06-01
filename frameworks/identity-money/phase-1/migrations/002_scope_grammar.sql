-- Phase 1 — scope grammar.
-- Single string format: <product>:<verb>:<noun>[:<modifier>]
-- Phase-1 verbs: read, write, invoke, admin, delegate
-- Phase-2 verbs (link, kyc) and Phase-3 verbs (pay) extend without changing the function shape.
--
-- See: docs/superpowers/specs/2026-05-28-identity-money-program-overview.md §2.2

BEGIN;

-- Single function used by every RLS policy in the program.
-- `claim_scopes` is the array from the JWT; `required` is what the policy wants.
-- A scope MATCHES if it equals the required scope OR has `:any` as the noun (admin shortcut).
CREATE OR REPLACE FUNCTION auth.has_scope(claim_scopes text[], required text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM unnest(claim_scopes) s
    WHERE
      s = required
      OR (
        -- product:verb:any matches product:verb:<anything>
        split_part(s, ':', 1) = split_part(required, ':', 1)
        AND split_part(s, ':', 2) = split_part(required, ':', 2)
        AND split_part(s, ':', 3) = 'any'
      )
      OR (
        -- product:admin:any is a master admin within a product surface
        split_part(s, ':', 1) = split_part(required, ':', 1)
        AND split_part(s, ':', 2) = 'admin'
        AND split_part(s, ':', 3) = 'any'
      )
  );
$$;

COMMENT ON FUNCTION auth.has_scope(text[], text)
IS 'Phase 1 — scope grammar matcher. See frameworks/identity-money/phase-1/migrations/002_scope_grammar.sql for ":any" semantics.';

COMMIT;
