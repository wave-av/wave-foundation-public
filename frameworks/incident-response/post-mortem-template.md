# Post-Mortem: <incident-id>

> Required for P0 + P1 within 5 business days. Blameless. Focus on systems, not individuals.

## Summary

One paragraph: what happened, who was affected, how long, how it was resolved.

## Timeline (UTC)

| Time | Event |
|------|-------|
| 00:00 | Alert fired |
| 00:02 | Oncall acked |
| 00:05 | Incident channel created |
| ... | ... |
| HH:MM | Service restored |
| HH:MM | All-clear declared |

## Impact

- Users affected: <count or %>
- Revenue at risk: <$ or N/A>
- Data integrity: <intact / partial loss / under investigation>
- SLA breach: <yes/no — which SLA>

## What went well

- Alert fired fast and routed correctly
- Mitigation X bought us time without rollback
- ...

## What went poorly

- Detection lag of N minutes because <signal was missing>
- Initial mitigation didn't work because <assumption was wrong>
- ...

## Root cause

The actual technical cause. Be specific. Include the code path / config / data row that caused it.

## Contributing factors

What made the impact worse than it had to be. Process gaps. Knowledge gaps.

## Action items

| # | Action | Owner | Severity | Due | Tracked in |
|---|--------|-------|----------|-----|------------|
| 1 | <specific fix> | @ | P0/P1 | YYYY-MM-DD | <issue link> |
| 2 | <runbook update> | @ | P2 | YYYY-MM-DD | <link> |

## Lessons

What we learned that should change how we build or operate. Link to any rules/frameworks updates in `wave-foundation/`.
