---
name: plan-to-action
description: Use when a plan has just been approved — transforms it into atomic, trackable tasks via TaskCreate, immediately, before any code.
allowed-tools: TaskCreate, TaskUpdate, TaskList, TaskGet, Read, Glob, Grep
argument-hint: "[plan-file-path]"
---

# Plan-to-Action Protocol v1.0

Transform approved plans into executable task lists that survive context compaction.

## CRITICAL: Why This Matters

Tasks created with TaskCreate are **stored separately** from the conversation. When context gets compacted (summarized), your tasks persist with full detail. This enables:

- 50-500+ tasks for complex projects
- Long-running implementations across sessions
- No lost context on complex projects

## Your Task

Convert the approved plan into atomic tasks using **TaskCreate**.

**Plan file:** $ARGUMENTS (if provided, read it first)

If no plan file specified, use the most recently approved plan from the conversation.

---

## PHASE 1: Analyze the Plan

1. **Read the plan** (from file or conversation)
2. **Identify phases** - what are the major stages?
3. **Count expected tasks** - estimate based on complexity:
   - Small feature: 15-40 tasks
   - Medium feature: 50-150 tasks
   - Large system: 150-300+ tasks

---

## PHASE 2: Decompose into Tasks

For each plan item, create atomic tasks following these rules:

### Rule 1: ATOMIC = Verifiable Completion

Each task must have a clear "done" or "not done" state.

```
BAD:  "Work on authentication"
GOOD: "Create JWT token utility in lib/auth/token.ts"
```

### Rule 2: ONE Action Per Task

```
BAD:  "Create user model and add validation"
GOOD: "Create user model in models/user.ts"
GOOD: "Add email validation to user model"
```

### Rule 3: Include Location

```
BAD:  "Add login endpoint"
GOOD: "Add POST /api/auth/login endpoint in routes/auth.ts"
```

### Rule 4: Self-Contained Context

Task description must make sense WITHOUT any other context.

```
BAD:  "Implement the approach discussed above"
GOOD: "Implement bcrypt password hashing (cost factor 12) in auth.service.ts"
```

---

## PHASE 3: Create Tasks with TaskCreate

Use this structure for each task:

```
Subject: "[PREFIX]: [Verb] [what] in [where]"

Description:
  What: [Specific action to take]
  Where: [File path(s)]
  How: [Approach if not obvious]
  Done when: [Acceptance criteria]
```

### Prefixes to Use

| Prefix | Use For |
|--------|---------|
| `P1-SETUP:` | Phase 1 setup tasks |
| `P1-IMPL:` | Phase 1 implementation |
| `P2-IMPL:` | Phase 2 implementation |
| `TEST:` | Testing tasks |
| `DOC:` | Documentation |
| `MILESTONE:` | Verification checkpoints |

### Example Task

```
Subject: "P1-AUTH: Create JWT token utility in lib/auth/token.ts"

Description:
  What: Create JWT generation and verification functions
  Where: lib/auth/token.ts

  Functions needed:
  - generateToken(userId, role) → signed JWT string
  - verifyToken(token) → decoded payload or throws

  Requirements:
  - Use RS256 algorithm
  - 24-hour expiration
  - Read keys from JWT_PRIVATE_KEY and JWT_PUBLIC_KEY env vars

  Done when:
  - Can generate a valid token
  - Can verify a valid token
  - Throws on expired/invalid tokens
```

---

## PHASE 4: Sequence and Dependencies

Create tasks in order of execution:

1. **Foundation first** - config, types, utilities
2. **Dependencies before dependents** - models → services → routes
3. **Tests after implementation** - or use TDD (tests first)
4. **Milestones at boundaries** - verification checkpoints

### Add MILESTONE Tasks

At each phase boundary:

```
Subject: "MILESTONE: Phase 1 complete - verify auth foundation"

Description:
  Verify Phase 1 is working before starting Phase 2.

  Checks:
  - JWT tokens can be generated
  - Tokens verify correctly
  - Middleware blocks invalid tokens

  If any check fails, fix before proceeding.
```

---

## PHASE 5: Validate and Report

After creating all tasks:

1. **Use TaskList** to verify all tasks created
2. **Count tasks** by category
3. **Report summary** to user:

```
Created X tasks:
- P1-SETUP: Y tasks
- P1-IMPL: Z tasks
- P2-IMPL: W tasks
- TEST: V tasks
- MILESTONE: N tasks

Ready to begin execution. Start with task #1.
```

---

## Task Templates

### Setup Task

```
Subject: "P1-SETUP: Initialize [what] in [where]"
Description:
  What: [Action]
  Where: [Path]
  Done when: [Criteria]
```

### Implementation Task

```
Subject: "P1-IMPL: Create [component] in [file]"
Description:
  What: [What to build]
  Where: [File path]

  Requirements:
  - [Requirement 1]
  - [Requirement 2]

  Done when: [Acceptance criteria]
```

### Test Task

```
Subject: "TEST: Add tests for [what] in [test file]"
Description:
  What: Create tests for [component]
  Where: [Test file path]

  Test cases:
  - [Case 1]: [Expected]
  - [Case 2]: [Expected]

  Done when: All tests pass
```

### Milestone Task

```
Subject: "MILESTONE: [Phase] complete - verify [what]"
Description:
  Checkpoint for [phase].

  Verify:
  - [Check 1]
  - [Check 2]

  Do not proceed until all checks pass.
```

---

## BEGIN NOW

1. Read/recall the approved plan
2. Create tasks using TaskCreate
3. Report task count when complete

**DO NOT write code. Create tasks ONLY.**
