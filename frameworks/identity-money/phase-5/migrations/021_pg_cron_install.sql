-- Phase 5.1 — schedule the evaluator (CONSUMER OPT-IN).
-- This migration is deliberately separate and guarded: it requires the pg_cron
-- extension, which is available on Supabase but must be enabled per-project, and it
-- registers a recurring job. Consumers who don't want automated evaluation simply
-- skip this file and call public.evaluate_anomaly_rules() from their own scheduler.
--
-- Safe to run more than once: cron.schedule() upserts a job by name.
--
-- See: docs/superpowers/specs/2026-05-31-phase-5-active-authorization-design.md §Layer 1

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
    RAISE NOTICE 'pg_cron not available on this server — skipping anomaly-eval schedule. '
                 'Call public.evaluate_anomaly_rules() from your own scheduler instead.';
    RETURN;
  END IF;

  CREATE EXTENSION IF NOT EXISTS pg_cron;

  -- Every 60s. cron.schedule is an upsert keyed by job name, so re-running is a no-op
  -- update rather than a duplicate job.
  PERFORM cron.schedule(
    'anomaly-eval',
    '*/1 * * * *',
    $job$ SELECT public.evaluate_anomaly_rules(); $job$
  );

  RAISE NOTICE 'Scheduled anomaly-eval (*/1 * * * *) → public.evaluate_anomaly_rules().';
END;
$$;
