-- secdef-hardening/inventory.sql
--
-- Inventory SECURITY DEFINER functions + their auth-check status + their EXECUTE
-- exposure to `anon` / `authenticated`. Re-runnable against staging or prod.
--
-- WAVE staging measurement (2026-06-04):
--   no_auth_check + anon+authenticated EXECUTE = 335 funcs  <-- EXPOSURE SURFACE
--   has_auth_check + anon+authenticated EXECUTE =  29 funcs
--   has_auth_check + service_role only          =   1 func
--   TOTAL SECDEF (public + stripe_wave + audit) = 365
--
-- Volatility split (public schema):
--   stable (read-only)    =  69
--   volatile (write/admin) = 284
--
-- USAGE
--   Run against any project (staging first):
--     supabase db query --file frameworks/secdef-hardening/inventory.sql
--   or via MCP execute_sql.

WITH secdef AS (
  SELECT p.oid,
         n.nspname AS schema,
         p.proname AS function,
         pg_get_function_identity_arguments(p.oid) AS args,
         p.provolatile AS vol,
         pg_get_functiondef(p.oid) AS src
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE p.prosecdef = true
    AND n.nspname IN ('public', 'stripe_wave', 'audit')
),
exposure AS (
  SELECT s.*,
         has_function_privilege('anon', s.oid, 'EXECUTE') AS anon_can_exec,
         has_function_privilege('authenticated', s.oid, 'EXECUTE') AS auth_can_exec,
         (s.src ILIKE '%auth.uid()%' OR
          s.src ILIKE '%auth.role()%' OR
          s.src ILIKE '%current_user_id%') AS has_auth_check,
         (s.src ~* 'RAISE\s+(EXCEPTION|ERROR)') AS has_raise_exception,
         (s.src ILIKE '%service_role%' OR
          s.src ILIKE '%current_setting%') AS has_role_gate
  FROM secdef s
)
SELECT
  CASE
    WHEN NOT (anon_can_exec OR auth_can_exec) THEN '5_service_role_only'
    WHEN has_auth_check THEN '4_has_auth_check'
    WHEN has_role_gate THEN '3_role_gate'
    WHEN has_raise_exception THEN '2_has_raise'
    ELSE '1_NO_GUARD_exposed'
  END AS risk_tier,
  schema,
  vol,
  count(*),
  -- Sample 5 examples
  string_agg(function, ', ' ORDER BY function) FILTER (WHERE true) AS sample_functions
FROM exposure
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
