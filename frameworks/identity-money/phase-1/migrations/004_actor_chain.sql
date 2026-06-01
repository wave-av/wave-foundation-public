-- Phase 1 — actor chain (RFC 8693 §2.1).
-- A token may carry an `act` claim with a nested chain: orchestrator → agent → human.
-- Permission rule: every actor in the chain must INDEPENDENTLY hold each scope (intersection).
--
-- See: docs/superpowers/specs/2026-05-28-identity-money-program-overview.md §2.4

BEGIN;

-- Walks the JWT `act` chain and asserts every actor holds the required scope.
-- jwt is the raw JWT payload (jsonb); we walk `act.act.act…` and check `scopes`.
CREATE OR REPLACE FUNCTION auth.actor_chain_has_scope(jwt jsonb, required text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  cur jsonb := jwt;
  cur_scopes text[];
BEGIN
  -- Top-level actor must hold the scope.
  cur_scopes := ARRAY(SELECT jsonb_array_elements_text(coalesce(cur->'scopes', '[]'::jsonb)));
  IF NOT auth.has_scope(cur_scopes, required) THEN
    RETURN false;
  END IF;
  -- Walk each `act` link; each one must also hold the scope.
  WHILE cur ? 'act' LOOP
    cur := cur->'act';
    cur_scopes := ARRAY(SELECT jsonb_array_elements_text(coalesce(cur->'scopes', '[]'::jsonb)));
    -- A nested actor without scopes claim is treated as "inherits parent's grant explicitly null"
    -- meaning: the parent already vouched, but per spec each actor must independently hold the
    -- scope. An empty/missing scopes claim ⇒ does NOT independently hold ⇒ FAIL.
    IF NOT auth.has_scope(cur_scopes, required) THEN
      RETURN false;
    END IF;
  END LOOP;
  RETURN true;
END;
$$;

COMMENT ON FUNCTION auth.actor_chain_has_scope(jsonb, text)
IS 'Phase 1 — RFC 8693 actor-chain scope intersection. Every actor in the chain must hold the scope.';

COMMIT;
