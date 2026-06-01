---
name: plan-generate
description: Use when starting a new feature, project, or task that needs planning — transforms user context, ideas, or requirements into a structured initial plan.
allowed-tools: Read, Glob, Grep, Write, Bash, WebSearch, WebFetch, AskUserQuestion
argument-hint: "[context-file-or-description]"
---

# Initial Plan Generation Protocol v3.0

The Complete Context-to-Plan Transformation System

---

## PART 0: PROTOCOL OVERVIEW

### 0.1 What This Protocol Does

```
┌─────────────────────────────────────────────────────────────────┐
│                    THE TRANSFORMATION                           │
│                                                                 │
│   USER'S CONTEXT          YOUR OUTPUT                          │
│   ─────────────          ───────────────                       │
│   • Raw ideas            • Structured plan                     │
│   • Vague requirements   • Clear requirements                  │
│   • Implicit needs       • Explicit tasks                      │
│   • Hidden constraints   • Documented constraints              │
│   • Unclear priorities   • Prioritized phases                  │
│   • Unknown risks        • Identified mitigations              │
│                                                                 │
│   Result: A plan ready for /plan-enhance                       │
└─────────────────────────────────────────────────────────────────┘
```

### 0.2 The Complete Flow

```
USER PROVIDES CONTEXT
        │
        ▼
┌─────────────────────────┐
│ 1. CLASSIFY & CALIBRATE │ What type? What scale? How urgent?
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│ 2. ABSORB & EXTRACT     │ Deep read, identify requirements
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│ 3. ASSESS FEASIBILITY   │ Can this be done? Scope realistic?
└───────────┬─────────────┘
            │
            ├──► Not feasible → NEGOTIATE SCOPE
            │
            ▼
┌─────────────────────────┐
│ 4. CLARIFY (if needed)  │ Ask critical questions OR assume
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│ 5. INVESTIGATE          │ Codebase, research, fill gaps
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│ 6. ANALYZE OPTIONS      │ Build vs buy, multiple approaches?
└───────────┬─────────────┘
            │
            ├──► Multiple viable options → PRESENT COMPARISON
            │
            ▼
┌─────────────────────────┐
│ 7. CONSTRUCT PLAN       │ Build structured, phased plan
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│ 8. VALIDATE & PRESENT   │ Self-check, deliver to user
└───────────┬─────────────┘
            │
            ▼
      PLAN READY FOR /plan-enhance
```

---

## QUICK DECISION CARDS

### Card A: Request Classification Matrix

```
CLASSIFY THE REQUEST
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

BY TYPE:
┌─────────────────┬────────────────────────────────────────────┐
│ Type            │ Focus                                      │
├─────────────────┼────────────────────────────────────────────┤
│ Bug fix         │ Root cause, minimal change, verification   │
│ New feature     │ Requirements, design, integration          │
│ Enhancement     │ Current state, incremental improvement     │
│ Refactor        │ Current problems, target state, migration  │
│ Migration       │ Source, target, data, rollback             │
│ Integration     │ Both systems, contracts, error handling    │
│ Investigation   │ Questions to answer, decision criteria     │
│ Optimization    │ Current metrics, targets, trade-offs       │
└─────────────────┴────────────────────────────────────────────┘

BY SCALE:
┌─────────────────┬───────────────────┬────────────────────────┐
│ Scale           │ Plan Depth        │ Investigation          │
├─────────────────┼───────────────────┼────────────────────────┤
│ Micro           │ 10-20 lines       │ 5-10 min               │
│ Small           │ 50-100 lines      │ 15-30 min              │
│ Medium          │ 100-300 lines     │ 30-60 min              │
│ Large           │ 300-500 lines     │ 1-2 hours              │
│ Massive         │ 500+ lines        │ Half day+              │
└─────────────────┴───────────────────┴────────────────────────┘

BY URGENCY:
┌─────────────────┬────────────────────────────────────────────┐
│ Urgency         │ Planning Approach                          │
├─────────────────┼────────────────────────────────────────────┤
│ Emergency       │ Minimal viable plan, fast, can iterate     │
│ Urgent          │ Focused plan, prioritize critical path     │
│ Normal          │ Full planning process                      │
│ Exploratory     │ Thorough, consider alternatives            │
└─────────────────┴────────────────────────────────────────────┘
```

### Card B: Feasibility Quick Check

```
CAN THIS BE DONE?
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

TECHNICAL FEASIBILITY:
  □ Is this technically possible?
  □ Do the required technologies exist?
  □ Are there known solutions to similar problems?
  □ Are there fundamental blockers?

RESOURCE FEASIBILITY:
  □ Does the scope match available resources?
  □ Are dependencies available?
  □ Is timeline realistic?

CONSTRAINT COMPATIBILITY:
  □ Can all stated constraints be satisfied?
  □ Are constraints contradictory?

IF NOT FEASIBLE:
  → Go to Scope Negotiation Protocol (Part III)
```

### Card C: Clarify vs. Assume Decision Tree

```
SHOULD I ASK OR ASSUME?
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Is the information critical to the plan?
│
├─► NO → Make reasonable assumption, document it
│
└─► YES → Can I find it by investigating?
    │
    ├─► YES → Investigate first
    │   │
    │   └─► Found it? → Use it
    │       Not found? → Continue to asking
    │
    └─► NO → Is there a reasonable default?
        │
        ├─► YES → Would being wrong significantly change the plan?
        │   │
        │   ├─► YES → ASK the user
        │   │
        │   └─► NO → Assume default, document, flag in plan
        │
        └─► NO → ASK the user (this is critical)

ASKING PRIORITY:
  1. Goal/scope clarification (blocks everything)
  2. Major technical decisions (changes approach)
  3. Constraints (may invalidate approach)
  4. Preferences (can usually assume)
```

### Card D: Build vs. Buy Analysis

```
BUILD CUSTOM OR USE EXISTING?
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CHECK FOR EXISTING SOLUTIONS:
  □ Is there a library/package for this?
  □ Is there a service/API for this?
  □ Is there existing code in the codebase?
  □ Is there an open-source solution?

EVALUATION CRITERIA:
┌─────────────────┬──────────────────┬──────────────────────┐
│ Factor          │ Build Custom     │ Use Existing         │
├─────────────────┼──────────────────┼──────────────────────┤
│ Time            │ Longer           │ Shorter              │
│ Customization   │ Full control     │ Limited              │
│ Maintenance     │ We own it        │ Dependency           │
│ Learning curve  │ Our patterns     │ New patterns         │
│ Cost            │ Dev time         │ License/usage        │
│ Risk            │ Unknown unknowns │ Known limitations    │
└─────────────────┴──────────────────┴──────────────────────┘

DECISION FRAMEWORK:
  Use existing when:
    - Well-maintained, popular solution exists
    - Our needs are standard
    - Time is constrained
    - Not a core differentiator

  Build custom when:
    - Unique requirements
    - Existing solutions don't fit
    - Need full control
    - Core to the product
    - Security/compliance requires it
```

### Card E: Multi-Option Presentation

```
WHEN MULTIPLE APPROACHES ARE VIABLE:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. IDENTIFY OPTIONS (2-3 max)
   Don't overwhelm with too many choices

2. EVALUATE EACH OPTION:
   ┌────────────────┬──────────┬──────────┬──────────┐
   │ Criterion      │ Option A │ Option B │ Option C │
   ├────────────────┼──────────┼──────────┼──────────┤
   │ Complexity     │          │          │          │
   │ Time to build  │          │          │          │
   │ Maintainability│          │          │          │
   │ Scalability    │          │          │          │
   │ Risk           │          │          │          │
   │ User's stated  │          │          │          │
   │ priorities     │          │          │          │
   └────────────────┴──────────┴──────────┴──────────┘

3. MAKE A RECOMMENDATION:
   "I recommend Option [X] because [reasons],
    but Option [Y] would be better if [conditions]."

4. OFFER TO DETAIL:
   "I can provide a full plan for any of these approaches.
    Which would you like me to develop?"
```

### Card F: Confidence Indicators

```
PLAN CONFIDENCE LEVELS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

HIGH CONFIDENCE (✓✓✓):
  - Based on direct codebase investigation
  - Similar work done before
  - Well-understood technology
  - Clear requirements

  "This approach will work because [evidence]"

MEDIUM CONFIDENCE (✓✓):
  - Based on reasonable inference
  - Some unknowns remain
  - Technology is familiar but not expert
  - Requirements mostly clear

  "This approach should work, assuming [assumption]"

LOW CONFIDENCE (✓):
  - Based on research, not direct experience
  - Significant unknowns
  - New technology or pattern
  - Requirements have gaps

  "This approach might work, but needs validation of [unknown]"

SPECULATIVE (?):
  - Limited information available
  - Many unknowns
  - Novel problem

  "This is my best guess, but [major caveat]"

USE IN PLAN:
  [Task] ✓✓✓
  [Task] ✓✓ - depends on [assumption]
  [Task] ✓ - needs validation
```

---

## PART I: CONTEXT ABSORPTION

### 1.1 The Absorption Framework

When reading user context, extract systematically:

```
CONTEXT EXTRACTION FRAMEWORK
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

LAYER 1: THE ASK
  What: [What they literally asked for]
  Why: [The underlying need/problem]
  Success: [What "done" looks like]

LAYER 2: REQUIREMENTS
  Explicit: [Stated requirements]
  Implicit: [Obviously needed but unstated]
  Constraints: [Limitations, must-haves]

LAYER 3: CONTEXT
  Current state: [What exists now]
  History: [How we got here]
  Environment: [Technical/organizational context]

LAYER 4: STAKEHOLDERS
  Primary: [Who's asking]
  Affected: [Who else cares]
  Blockers: [Who could say no]

LAYER 5: PRIORITIES
  Must have: [Non-negotiable]
  Should have: [Important]
  Could have: [Nice to have]
  Won't have: [Explicitly out]

LAYER 6: RISKS & CONCERNS
  Stated: [Worries they mentioned]
  Implied: [Concerns they didn't voice]

LAYER 7: GAPS
  Unknown: [What you need to know]
  Ambiguous: [What could mean multiple things]
  Contradictory: [What conflicts]
```

### 1.2 Stakeholder Analysis

```
STAKEHOLDER MAPPING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PRIMARY STAKEHOLDER (the requester):
  Who: [Name/role]
  Goal: [What they want]
  Success metric: [How they'll judge success]

USERS (who will use this):
  Who: [User types]
  Needs: [What they need from this]
  Impact: [How this affects them]

AFFECTED PARTIES (impacted by changes):
  Who: [Other teams, systems, people]
  Impact: [How they're affected]
  Concerns: [What they'd worry about]

DECISION MAKERS (who approves):
  Who: [Who can say yes/no]
  Criteria: [What they care about]

MAINTAINERS (who supports this after):
  Who: [Who runs/maintains this]
  Needs: [What they need for operability]

POTENTIAL CONFLICTS:
  [Stakeholder A] wants [X] but [Stakeholder B] wants [Y]
  Resolution: [How to address]
```

### 1.3 Context Quality Assessment

```
CONTEXT QUALITY SCORECARD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                              Score (1-5)
                              ───────────
Goal clarity:                 [  ]
  5 = Crystal clear
  1 = Can't tell what they want

Requirement detail:           [  ]
  5 = Specific, measurable
  1 = Vague handwaving

Constraint clarity:           [  ]
  5 = All constraints stated
  1 = Hidden landmines likely

Context completeness:         [  ]
  5 = Full background provided
  1 = Major gaps

Priority clarity:             [  ]
  5 = Clear what matters most
  1 = Everything "critical"

Timeline/urgency:             [  ]
  5 = Clear expectations
  1 = Unknown deadline

TOTAL:                        [  ]/30

INTERPRETATION:
  25-30: Excellent - proceed with high confidence
  20-24: Good - minor clarifications may help
  15-19: Adequate - some assumptions needed
  10-14: Weak - clarification recommended
  <10:   Insufficient - request more information
```

---

## PART II: FEASIBILITY & SCOPE ASSESSMENT

### 2.1 Feasibility Check

```
FEASIBILITY ASSESSMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

TECHNICAL FEASIBILITY:
  □ Is this technically possible with current technology?
  □ Have similar things been built before?
  □ Are there fundamental technical barriers?
  □ Do we have access to required resources/APIs/data?

  Verdict: [Feasible / Partially feasible / Not feasible]
  Notes: [Details]

RESOURCE FEASIBILITY:
  □ Is the implied scope realistic?
  □ Are required skills available?
  □ Are dependencies available?
  □ Is timeline (if stated) achievable?

  Verdict: [Feasible / Partially feasible / Not feasible]
  Notes: [Details]

CONSTRAINT COMPATIBILITY:
  □ Can all stated constraints be satisfied simultaneously?
  □ Are any constraints contradictory?
  □ Are any constraints unrealistic?

  Verdict: [Compatible / Tension exists / Incompatible]
  Notes: [Details]

OVERALL FEASIBILITY:
  [Fully feasible / Feasible with caveats / Partially feasible / Not feasible]

  If not fully feasible:
  → Proceed to Scope Negotiation (Part III)
```

### 2.2 Scope Reality Check

```
SCOPE REALITY CHECK
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SCOPE SIGNALS FROM CONTEXT:
  Stated scope: [What they said they want]
  Implied effort: [What this actually requires]
  Gap: [Difference between stated and reality]

SCOPE WARNING SIGNS:
  □ "Just" or "simply" before complex task
  □ Many features listed casually
  □ Ambitious timeline for complex work
  □ "And also" adding scope
  □ Everything is "must have"

SCOPE ASSESSMENT:
  □ Scope is clear and realistic
  □ Scope is ambitious but achievable
  □ Scope is larger than they may realize
  □ Scope is unrealistic as stated

IF SCOPE IS PROBLEMATIC:
  → Proceed to Scope Negotiation (Part III)
```

---

## PART III: SCOPE NEGOTIATION

### 3.1 When to Negotiate

```
NEGOTIATE SCOPE WHEN:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✓ Request is technically impossible
✓ Request violates physical/logical constraints
✓ Scope is unrealistic for implied timeline
✓ Requirements contradict each other
✓ "Must haves" exceed available capacity
✓ Request would cause more problems than it solves
✓ Better alternative exists they may not know about

DON'T NEGOTIATE WHEN:
✗ It's just hard (hard is okay)
✗ You'd prefer a different approach (but theirs works)
✗ It's unfamiliar to you (learn it)
✗ It's not how you'd do it (their choice)
```

### 3.2 How to Negotiate Constructively

```
SCOPE NEGOTIATION APPROACH
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. VALIDATE THE GOAL
   "I understand you want to [goal] because [reason]..."
   Show you understand what they're trying to achieve

2. EXPLAIN THE CHALLENGE
   "The challenge is [specific issue]..."
   Be specific, not vague ("it's complex")

3. OFFER ALTERNATIVES
   "Here are some options:

    Option A: [Full scope, realistic implications]
      - Gets you: [everything]
      - Requires: [realistic resources/time]

    Option B: [Reduced scope, faster delivery]
      - Gets you: [core value]
      - Requires: [less]
      - Defers: [what's left out]

    Option C: [Different approach]
      - Gets you: [similar outcome]
      - Requires: [different trade-offs]"

4. MAKE A RECOMMENDATION
   "I'd recommend Option [X] because [reason],
    but the choice depends on [their priorities]..."

5. AWAIT DIRECTION
   Let them choose or provide more context
```

### 3.3 Handling Impossible Requests

```
IF THE REQUEST IS TRULY IMPOSSIBLE:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. CONFIRM UNDERSTANDING
   "Let me make sure I understand: you want [X]?"
   (Maybe you misunderstood)

2. EXPLAIN WHY IT'S IMPOSSIBLE
   "This isn't possible because [fundamental reason]..."
   Be specific and technical

3. OFFER WHAT IS POSSIBLE
   "What IS possible is [closest achievable alternative]..."

4. EXPLAIN THE GAP
   "This differs from your request in [specific ways]..."

5. ASK IF ALTERNATIVE HELPS
   "Would this alternative solve your underlying need?"

EXAMPLE:
  Request: "Make the app work offline with real-time sync"

  Response: "Real-time sync by definition requires being
  online, so fully offline + real-time isn't possible.

  What IS possible:
  - Offline mode with sync-when-online (queue changes)
  - Near-real-time with aggressive reconnection
  - Offline read-only with online write

  Which of these would best serve your users?"
```

---

## PART IV: INVESTIGATION

### 4.1 Investigation Strategy Matrix

```
INVESTIGATION APPROACH BY REQUEST TYPE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

BUG FIX:
  Priority: Find root cause
  Investigate:
    1. Error location/message
    2. Related code paths
    3. Recent changes (git)
    4. Test coverage
  Tools: Grep for error, Read affected files, git log

NEW FEATURE:
  Priority: Understand integration points
  Investigate:
    1. Where this fits architecturally
    2. Similar existing features
    3. Affected components
    4. Required dependencies
  Tools: Structure scan, pattern search, Read examples

ENHANCEMENT:
  Priority: Understand current implementation
  Investigate:
    1. Current functionality
    2. Current limitations
    3. User of this code
    4. Test coverage
  Tools: Read current impl, Find usages, Read tests

REFACTOR:
  Priority: Understand impact radius
  Investigate:
    1. All usages of target code
    2. Dependencies on target
    3. Test coverage
    4. Related patterns
  Tools: Grep usages, dependency analysis, Read tests

INTEGRATION:
  Priority: Understand both sides
  Investigate:
    1. Our system's interface
    2. External system's interface
    3. Data formats/contracts
    4. Error scenarios
  Tools: Read APIs, WebFetch docs, Find examples

MIGRATION:
  Priority: Understand source and target
  Investigate:
    1. Current state completely
    2. Target state requirements
    3. Data transformation needs
    4. Rollback requirements
  Tools: Full current state analysis, target research
```

### 4.2 Build vs. Buy Analysis

```
BUILD VS. BUY ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. SEARCH FOR EXISTING SOLUTIONS:
   □ npm/pip/cargo search for packages
   □ GitHub search for implementations
   □ Google for services/APIs
   □ Check if it exists in codebase already

2. EVALUATE FOUND OPTIONS:
   For each option:

   [OPTION NAME]:
     Type: [Library / Service / Existing code]
     Fit: [How well it matches needs] (1-5)
     Maturity: [Popularity, maintenance, age]
     Cost: [Free / Paid / Effort to integrate]
     Trade-offs:
       Pros: [Benefits]
       Cons: [Drawbacks]
     Verdict: [Use / Don't use / Consider]

3. COMPARE TO CUSTOM BUILD:
   ┌─────────────────┬──────────────────┬──────────────────┐
   │ Factor          │ Use Existing     │ Build Custom     │
   ├─────────────────┼──────────────────┼──────────────────┤
   │ Time to working │                  │                  │
   │ Customization   │                  │                  │
   │ Long-term maint │                  │                  │
   │ Team familiarity│                  │                  │
   │ Risk            │                  │                  │
   └─────────────────┴──────────────────┴──────────────────┘

4. RECOMMENDATION:
   [Use existing / Build custom / Hybrid]
   Rationale: [Why]
```

### 4.3 Investigation Parallelization

```
EFFICIENT INVESTIGATION PATTERN
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ROUND 1 - Orientation (Parallel):
┌─────────────────────────────────────────────────────────┐
│ Read(README.md)                                         │
│ Read(package.json or equivalent)                        │
│ Glob("src/**/*" or relevant pattern)                    │
│ Bash("git log --oneline -10")                           │
└─────────────────────────────────────────────────────────┘

ROUND 2 - Targeted Search (Parallel, based on Round 1):
┌─────────────────────────────────────────────────────────┐
│ Grep(patterns relevant to request)                      │
│ Glob(file patterns for affected area)                   │
│ Read(files likely to be important)                      │
└─────────────────────────────────────────────────────────┘

ROUND 3 - Deep Dive (Serial, based on findings):
  For each important file found:
    Read fully → Understand → Note insights
  Follow dependency/call chains as needed

ROUND 4 - External Research (Parallel if needed):
┌─────────────────────────────────────────────────────────┐
│ WebSearch(best practices, patterns)                     │
│ WebFetch(official documentation)                        │
└─────────────────────────────────────────────────────────┘

ROUND 5 - Synthesis:
  Combine all findings into coherent understanding
```

---

## PART V: PLAN CONSTRUCTION

### 5.1 Plan Structure by Scale

#### Micro Plan (Bug fix, tiny change)

```
═══════════════════════════════════════════════════════════════════
                    FIX: [Brief description]
═══════════════════════════════════════════════════════════════════

PROBLEM:
  [What's wrong - specific]

ROOT CAUSE:
  [Why it happens]
  Location: [file:line] ✓✓✓

FIX:
  [Exact change to make]

VERIFICATION:
  [How to confirm it's fixed]

RISKS:
  [Any risks with this fix]

═══════════════════════════════════════════════════════════════════
```

#### Small Plan (Single feature)

```
═══════════════════════════════════════════════════════════════════
                    PLAN: [Feature Name]
═══════════════════════════════════════════════════════════════════

OBJECTIVE:
  [What and why - one paragraph]

APPROACH:
  [Strategy - one paragraph]
  Confidence: ✓✓✓ / ✓✓ / ✓

TASKS:
  1. [ ] [Task] ✓✓✓
         Files: [files]
         Details: [specifics]

  2. [ ] [Task] ✓✓
         Files: [files]
         Details: [specifics]

DECISIONS:
  [DEC-001]: [Decision]
    Why: [Rationale]

VALIDATION:
  - [How to verify]

RISKS:
  - [Risk]: [Mitigation]

ASSUMPTIONS:
  - [Assumption]: [Basis]

═══════════════════════════════════════════════════════════════════
```

#### Medium Plan (Multi-component feature)

```
═══════════════════════════════════════════════════════════════════
                    IMPLEMENTATION PLAN
                    [Project Name]
═══════════════════════════════════════════════════════════════════

OVERVIEW
────────────────────────────────────────────────────────────────────

Objective:
  [What we're building and why]

Success Criteria:
  - [Measurable outcome]
  - [Measurable outcome]

Scope:
  In: [Included]
  Out: [Excluded]


APPROACH
────────────────────────────────────────────────────────────────────

Strategy:
  [High-level approach]

  Confidence: ✓✓✓ / ✓✓ / ✓
  Basis: [Why this confidence level]

Key Decisions:
  [DEC-001]: [Decision]
    Context: [Why decision was needed]
    Choice: [What was decided]
    Rationale: [Why this choice]
    Alternatives: [What else considered]
    Confidence: ✓✓✓


PHASE 1: [Name]
────────────────────────────────────────────────────────────────────

Objective: [What this achieves]
Confidence: ✓✓✓

Tasks:
  1.1 [Task] ✓✓✓
      Files: [files to modify/create]
      Details: [implementation specifics]

  1.2 [Task] ✓✓
      Files: [files]
      Details: [specifics]
      Note: [any uncertainty]

Validation:
  - [How to verify phase complete]

Deliverables:
  - [What's produced]


PHASE 2: [Name]
────────────────────────────────────────────────────────────────────
[Same structure]


TECHNICAL DETAILS
────────────────────────────────────────────────────────────────────

Architecture:
  [How components fit together]

Data Model:
  [Schemas if relevant]

API Changes:
  [Endpoints if relevant]

Configuration:
  [Settings/env vars needed]


RISKS & MITIGATIONS
────────────────────────────────────────────────────────────────────

[R-001]: [Risk]
  Likelihood: [H/M/L]
  Impact: [H/M/L]
  Mitigation: [Strategy]
  Contingency: [If it happens]


ASSUMPTIONS
────────────────────────────────────────────────────────────────────

[A-001]: [Assumption] ✓✓
  Basis: [Why reasonable]
  If wrong: [Impact]


OPEN QUESTIONS
────────────────────────────────────────────────────────────────────

[Q-001]: [Question]
  Impact: [What it affects]
  Default: [Assumption if unanswered]


DEPENDENCIES
────────────────────────────────────────────────────────────────────

Prerequisites:
  - [What must exist first]

External:
  - [External dependencies]


SUCCESS METRICS
────────────────────────────────────────────────────────────────────

How we'll know it worked:
  - [Metric]


NEXT STEPS
────────────────────────────────────────────────────────────────────

1. [Immediate next action]
2. [Following action]

═══════════════════════════════════════════════════════════════════
```

### 5.2 Incremental Value Delivery

```
INCREMENTAL DELIVERY DESIGN
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PRINCIPLE:
  Each phase should deliver usable value
  Don't front-load all the "infrastructure"
  User should see progress

PHASE DESIGN PATTERN:
  Phase 1: Minimal viable [feature]
    → User can [do basic thing]

  Phase 2: Enhanced [feature]
    → User can [do more things]

  Phase 3: Complete [feature]
    → Full functionality

  Phase 4: Polish
    → Edge cases, optimization

EXAMPLE - Search Feature:
  Phase 1: Basic search that returns results
    → User can search and find things

  Phase 2: Filtering and sorting
    → User can refine results

  Phase 3: Advanced search (fuzzy, operators)
    → Power users get advanced features

  Phase 4: Performance optimization
    → Fast at scale
```

### 5.3 Fallback Planning

```
FALLBACK PLANNING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

FOR HIGH-RISK ELEMENTS:

Primary approach: [Main plan]
  Confidence: ✓✓
  Risk: [What could go wrong]

Fallback approach: [Alternative if primary fails]
  Trigger: [When to switch]
  Trade-offs: [What we lose]

Decision point: [When we'll know if primary works]

EXAMPLE:
  Primary: Use Elasticsearch for search
    Confidence: ✓✓
    Risk: May be overkill, complex setup

  Fallback: Use PostgreSQL full-text search
    Trigger: If ES setup takes >1 day
    Trade-offs: Less powerful, but simpler

  Decision point: After Phase 1, evaluate complexity
```

---

## PART VI: VALIDATION & PRESENTATION

### 6.1 Plan Self-Validation

```
PLAN VALIDATION CHECKLIST
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

COMPLETENESS:
  □ All explicit requirements addressed
  □ All implicit requirements addressed
  □ All constraints respected
  □ Success criteria defined
  □ Risks identified
  □ Assumptions documented

CLARITY:
  □ Objective is crystal clear
  □ Each task is specific and actionable
  □ Technical choices are explicit
  □ Sequence is logical
  □ Dependencies are clear

CONFIDENCE:
  □ Confidence levels are marked
  □ Basis for confidence is stated
  □ Uncertainties are flagged
  □ Fallbacks for high-risk items

FEASIBILITY:
  □ Approach is technically sound
  □ Scope is realistic
  □ Risks have mitigations

ACTIONABILITY:
  □ Someone could start immediately
  □ Next steps are clear
  □ Validation criteria exist
  □ Phase boundaries are clear

ENHANCEMENT-READY:
  □ Structure supports /plan-enhance deep-dive
  □ Open questions flagged
  □ Investigation areas identified
```

### 6.2 How to Present

```
PRESENTATION STRUCTURE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. CONFIRM UNDERSTANDING (2-3 sentences)
   "Based on your request, I understand you need [X]
    because [Y], with the key constraints being [Z]."

2. GIVE THE HEADLINE (1 sentence)
   "My recommended approach is [strategy] which will
    deliver [outcome]."

3. PRESENT THE PLAN
   [Full structured plan]

4. HIGHLIGHT KEY DECISIONS
   "Key decisions in this plan:
    - [Decision 1]: [Brief rationale]
    - [Decision 2]: [Brief rationale]"

5. SURFACE UNCERTAINTY
   "Areas of lower confidence:
    - [Uncertainty]: [Why uncertain, what would resolve]

    Assumptions I made:
    - [Assumption]: [Would change plan if wrong]"

6. OFFER OPTIONS (if multiple approaches viable)
   "Alternative approaches worth considering:
    - [Alternative]: [When it would be better]"

7. CLEAR NEXT STEPS
   "If this plan looks good:
    - We can enhance it further with /plan-enhance
    - Or start implementation with [first task]

    Questions that would improve this plan:
    - [Question 1]"
```

---

## PART VII: ANTI-PATTERNS

### Common Mistakes

```
PLAN GENERATION ANTI-PATTERNS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

❌ JUMPING TO SOLUTION
   Started writing plan without understanding problem
   → Always absorb and clarify first

❌ VAGUE TASKS
   "Handle the edge cases" / "Make it robust"
   → Specify WHICH edge cases, HOW to handle

❌ HIDDEN CONFIDENCE
   Presenting uncertain things as certain
   → Use confidence indicators (✓✓✓, ✓✓, ✓)

❌ SCOPE CREEP
   Adding unrequested features
   → Stick to what was asked

❌ TECHNOLOGY TOURISM
   Proposing new tech because it's interesting
   → Use existing stack unless justified

❌ IGNORING CONSTRAINTS
   Planning something that violates stated limits
   → Re-read constraints, respect them

❌ NO VALIDATION CRITERIA
   No way to know when done
   → Define success criteria

❌ COMPLEXITY MISMATCH
   10-phase plan for simple task (or vice versa)
   → Match plan depth to task complexity

❌ ASSUMPTION HIDING
   Making decisions without documenting
   → Every assumption explicit

❌ RISK BLINDNESS
   Ignoring what could go wrong
   → Identify and mitigate risks

❌ NO FALLBACK
   Single path with no alternative
   → For high-risk elements, have Plan B
```

---

## PART VIII: SELF-DIAGNOSTIC

### Pre-Delivery Checklist

```
BEFORE PRESENTING PLAN:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

UNDERSTANDING:
  □ Can I state the goal in one sentence?
  □ Do I know why they want this?
  □ Have I identified all stakeholders?

COVERAGE:
  □ Every requirement addressed?
  □ Every constraint respected?
  □ Success criteria defined?

QUALITY:
  □ Confidence levels marked?
  □ Uncertainties flagged?
  □ Risks identified?
  □ Assumptions documented?

ACTIONABILITY:
  □ Could someone implement this?
  □ Are next steps clear?
  □ Is validation defined?

PRESENTATION:
  □ Is complexity appropriate to ask?
  □ Is structure clear?
  □ Are key decisions highlighted?
```

### Quality Signals

```
SIGNS YOUR PLAN IS GOOD:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✓ You can explain it in 30 seconds
✓ Each phase delivers value
✓ Tasks are estimatable
✓ Dependencies are clear
✓ Risks are acknowledged
✓ Someone else could implement it
✓ You'd want to receive this plan

SIGNS IT NEEDS MORE WORK:

✗ You're unsure what they want
✗ Phases are vague
✗ No validation criteria
✗ Hiding uncertainty
✗ Doesn't match request scale
✗ Missing obvious considerations
✗ You wouldn't want to implement from this
```

---

## CLOSING

Your mission: Transform raw intent into actionable structure.

A great initial plan:

- Demonstrates deep understanding
- Provides clear direction with confidence indicators
- Makes all decisions and assumptions explicit
- Acknowledges uncertainty honestly
- Delivers value incrementally
- Prepares for what could go wrong
- Is ready for /plan-enhance

The quality of this plan determines the quality of everything that follows.

---

## Protocol Integration

```
USER CONTEXT
     │
     ▼
THIS PROTOCOL (/plan-generate) ──────────────────┐
  │                                              │
  ├─► Classify & calibrate                       │
  ├─► Absorb & extract                           │
  ├─► Assess feasibility ──► Negotiate scope     │
  ├─► Clarify (if needed)                        │
  ├─► Investigate                                │
  ├─► Analyze options ──► Present comparison     │
  ├─► Construct plan                             │
  └─► Validate & present                         │
     │                                           │
     ▼                                           │
INITIAL PLAN                                     │
     │                                           │
     ▼                                           │
/plan-enhance ───────────────────────────────────┤
     │                                           │
     ▼                                           │
ENHANCED PLAN                                    │
     │                                           │
     ▼                                           │
/plan-to-action                                  │
     │                                           │
     ▼                                           │
IMPLEMENTATION                                   │
     │                                           │
     ▼                                           │
/plan-audit ─────────────────────────────────────┘
     │                (opportunities feed back)
     ▼
VERIFIED SOLUTION
```
