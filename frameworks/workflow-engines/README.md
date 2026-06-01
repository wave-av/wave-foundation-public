# Workflow Engines Framework

This framework ships a **schema-driven agent workflow engine** — a JSON contract plus a
shell runtime that executes ordered, checkpointed, escalatable agent workflows. 40+ workflow
definitions consume it. A workflow is data (`workflow.json` validated against
[`engine/workflow-schema.json`](engine/workflow-schema.json)); the runtime
([`engine/workflow-runner.sh`](engine/workflow-runner.sh)) interprets it, so adding or changing a
workflow never means touching the engine.

> Promoted from `staging/agent-workflows/_framework`. The engine is dogfooded — the foundation
> runs the same gates against itself (`scripts/dogfood.sh`); shell files here pass the shell ratchet
> with **zero** new shellcheck findings.

## The engine

Five files under [`engine/`](engine/):

| File | Role |
|------|------|
| [`workflow-schema.json`](engine/workflow-schema.json) | The **contract**. JSON-Schema 2020-12 describing a valid workflow definition: `name`, `version`, `trigger`, `steps`, `outcomes`, plus optional `checkpoints`/`escalation`/`reporting`/`metrics`. |
| [`workflow-runner.sh`](engine/workflow-runner.sh) | The **interpreter**. Loads a `workflow.json`, validates it against the schema (via `ajv` when present), runs each step in order, and routes failures by each step's `onFailure.action`. |
| [`checkpoint-manager.sh`](engine/checkpoint-manager.sh) | **State persistence + rollback.** Snapshots run state to `~/.claude/state/workflows/checkpoints`, restores/rolls back, prunes to `MAX_CHECKPOINTS`. |
| [`escalation-handler.sh`](engine/escalation-handler.sh) | **Human-in-the-loop.** Fans a failure out to Slack / Linear / PagerDuty by severity (`low → critical`), and tracks acknowledge/resolve in an append-only `escalations.jsonl`. |
| [`outcome-reporter.sh`](engine/outcome-reporter.sh) | **Result of record.** Writes a per-run outcome report and ships it to configured destinations (file / Slack / Linear / Supabase), plus a `summary` rollup. |

The runner `source`s the other three, so a step's `onFailure: rollback` reaches
`rollback_to_last_checkpoint`, `escalate` reaches `handle_escalation`, and the terminal outcome
reaches `report_outcome` — one cohesive lifecycle.

## The schema contract

A workflow definition is a single JSON object. The required keys:

- **`name`** — kebab-case identifier (`^[a-z][a-z0-9-]+$`).
- **`version`** — semver (`^\d+\.\d+\.\d+$`). In-flight runs continue on their pinned version.
- **`description`** — what it does, for humans and for the runner's `--help` listing.
- **`trigger`** — `{ type: manual | event | schedule | webhook | linear-issue, ... }`.
- **`steps`** — the ordered work (see below). `minItems: 1`.
- **`outcomes`** — at least `success` and `failure`, each `{ message, actions[] }`. `partial` optional.

Optional blocks the runtime honors: `inputs` (typed + validated), `context`
(`maxBudget`, `requiredMemories`, `requiredRules`), `checkpoints`, `escalation`, `reporting`,
`metrics` (`track[]` + an `slo` of `maxDuration`/`successRate`).

### A step

```json
{
  "id": "reproduce",
  "name": "Reproduce the bug",
  "action": { "type": "agent-spawn", "agentType": "debugger", "prompt": "...", "timeout": 600, "retries": 2 },
  "checkpoint": { "enabled": true, "saveState": true, "allowRollback": true },
  "conditions": { "runIf": "inputs.has_repro == false" },
  "onSuccess": "write-fix",
  "onFailure": { "action": "escalate", "escalateTo": "oncall" }
}
```

`action.type` is one of `agent-spawn`, `tool-call`, `validation`, `checkpoint`, `decision`,
`parallel`, `human-review`, `notification` — each dispatched by a handler in the runner.
`onFailure.action` is one of `retry`, `skip`, `escalate`, `rollback`, `abort`.

## Runner lifecycle

```
workflow-runner.sh <name> [--input k=v] [--resume <checkpoint>] [--dry-run] [--verbose]
   │
   ├─ load_workflow        read <name>/workflow.json, validate against the schema
   ├─ generate_run_id      run_<ts>_<pid>
   ├─ (resume)             restore_checkpoint if --resume
   └─ for each step:
        ├─ checkpoint.enabled?  → create_checkpoint
        ├─ dispatch by action.type
        └─ on failure → onFailure.action:
             retry    → run once more, then escalate
             skip     → continue
             escalate → handle_escalation
             rollback → rollback_to_last_checkpoint; exit
             abort    → report_outcome failure; exit
   └─ report_outcome success
```

`--dry-run` validates and narrates without spawning agents or calling tools — use it in CI to
prove a new `workflow.json` is well-formed before it can run for real.

## Authoring a workflow (consumer guide)

1. **Create** `agent-workflows/<your-workflow>/workflow.json`.
2. **Conform** to [`engine/workflow-schema.json`](engine/workflow-schema.json) — minimally
   `name`, `version`, `description`, `trigger`, `steps`, `outcomes`.
3. **Validate** — `ajv validate -s engine/workflow-schema.json -d <your-workflow>/workflow.json`
   (the runner does this automatically when `ajv` is on `PATH`).
4. **Dry-run** — `engine/workflow-runner.sh <your-workflow> --dry-run` to walk the steps.
5. **Wire integrations** via env, never hard-coded: `SLACK_ESCALATION_WEBHOOK`,
   `SLACK_WEBHOOK_URL`, `PAGERDUTY_ROUTING_KEY`, `WORKFLOW_DASHBOARD_URL`, `REPORT_DESTINATIONS`,
   `MAX_CHECKPOINTS`. Absent integrations degrade to a skip-with-message, never a hard failure.

## Hard rules

1. **Every step is idempotent.** A step may be retried (`onFailure: retry`) or resumed from a
   checkpoint; running it twice must equal running it once. Key side effects on `run_id + step_id`.
2. **No secrets in the workflow definition or run state.** `workflow.json`, checkpoints, and
   outcome reports are persisted/shared. Pass an identifier and look the secret up at the edge —
   same rule as [`frameworks/observability`](../observability/README.md).
3. **Definitions are versioned.** Changing a workflow's step shape requires a `version` bump; in-flight
   runs drain on the old shape.
4. **State is local + disposable.** Checkpoints/reports live under `~/.claude/state/workflows` and are
   per-machine — they are a resume aid, not the system of record. Durable outcomes go to a `reporting`
   destination.

## When to use this engine vs a vendor durable runtime

This engine is for **agent** workflows — ordered, checkpointed, human-escalatable task graphs that
spawn agents and call tools, run from a shell, and resume from a checkpoint. For high-volume,
crash-durable *service* workflows (billing reconciliation, encoding pipelines, retried external APIs)
reach for a hosted durable runtime instead:

| Tool | Best for | Notes |
|------|----------|-------|
| **Inngest** | TypeScript-native, event-driven service workflows | Typed functions; replay, fan-out, throttle built in. Free tier covers most. |
| **Trigger.dev** | Jobs-style durable work | v3 is a real durable runtime; pick if Inngest's DX doesn't fit. |
| **Temporal** | Polyglot, enterprise scale, complex sagas | Heaviest setup; worth it at very high volume with cross-language teams. |
| **AWS Step Functions** | AWS-only, JSON-defined workflows | Verbose for complex logic; fine if already deep in AWS. |
| **GitHub Actions** | CI/CD orchestration only | Build/test/deploy chains — not runtime workflows. |
| **Cron + queue (DIY)** | Simple, low-volume async | Fine for "send digest Mondays 9am"; avoid for multi-step. |

Rule of thumb: **agent task graph that needs checkpoints + human escalation → this engine;
fire-and-forget → a queue; crash-durable multi-step service work → a vendor runtime.**

## Anti-patterns

- ❌ Editing the engine to add a workflow — author a `workflow.json` against the schema instead.
- ❌ Hard-coding a Slack/PagerDuty/dashboard URL in a `.sh` — pass it by env (see authoring step 5).
- ❌ Putting a credential in `workflow.json`, a checkpoint, or an outcome report.
- ❌ A non-idempotent step behind `onFailure: retry` (double-charge, double-ship).
- ❌ Treating `~/.claude/state/workflows` as durable — ship outcomes to a `reporting` destination.

## Relation to other frameworks

- [`observability`](../observability/README.md) — workflow failures route to Sentry like everything
  else; the no-secrets-in-payload rule is shared.
- [`audit-trail`](../audit-trail/README.md) — a workflow that mutates a tracked resource still writes
  an `audit_events` row; the outcome report is the run record, not the audit record.
- [`gates`](../gates/README.md) — the shell files here pass the same shell ratchet every consumer runs.
- [`notifications`](../notifications/README.md) — escalation/outcome sends must be idempotent (rule 1).
- [`secrets-management`](../secrets-management/README.md) — the no-secrets-in-definition rule (rule 2).
