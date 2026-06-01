---
name: wave-execute
description: Use when executing an approved, task-atomized plan — runs it wave-by-wave with milestone gates, marks tasks in_progress → completed, runs npx tsc --noEmit at each MILESTONE, and never starts Wave N+1 while Wave N has incomplete tasks.
allowed-tools: TaskList, TaskUpdate, TaskGet, TaskCreate, Bash, Task
argument-hint: "[plan-file-or-task-list]"
---

# Wave Execute

Execute the current plan's tasks wave by wave. Uses TaskList/TaskUpdate. Enforces the wave-execution-discipline.

## What This Does

1. Reads all tasks via TaskList
2. Finds the lowest-ID unblocked task in Wave 1
3. Marks it `in_progress`, executes the work, marks it `completed`
4. When all Wave N tasks complete, runs `npx tsc --noEmit` (must pass zero errors)
5. Marks the MILESTONE task `completed` only after the gate passes
6. Advances to Wave N+1
7. Repeats until all waves done
8. Announces: ready for `/plan-audit`

## Rules (Non-Negotiable)

- NEVER mark a MILESTONE `completed` without running `npx tsc --noEmit` first
- NEVER start Wave N+1 tasks while any Wave N task is `pending` or `in_progress`
- NEVER mark a task `completed` without making the corresponding file change
- ALWAYS create a new task (subject: "DISCOVERED: ...") when finding unplanned work

## When to Spawn a Team

Spawn parallel agents for Wave N when ALL are true:

1. Wave has 5+ tasks
2. Tasks span different domains (frontend, backend, DB, docs)
3. No shared file modifications between task groups
4. Working tree is clean (no uncommitted changes from prior wave)

Team pattern: `tech-[feature]-strike` with domain specialists.

## On Completion

After all tasks are `completed` and the final MILESTONE passes, announce:
> "All tasks complete. Run `/plan-audit` to verify before committing."

## Related

- `plan-to-action` skill — atomizes an approved plan into the tasks this skill executes
- `plan-audit` skill — run after completion to verify the implementation matches the plan

(Enforcement rules are stated inline above under "Rules (Non-Negotiable)" so this skill is
self-contained when installed.)
