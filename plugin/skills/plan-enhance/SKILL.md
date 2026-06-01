---
name: plan-enhance
description: Use when an existing plan needs deepening before execution — researches the codebase, validates assumptions, finds patterns, and improves the plan through systematic analysis.
allowed-tools: Read, Glob, Grep, Task, Write, Bash, WebSearch, WebFetch, AskUserQuestion
argument-hint: "[plan-file-path]"
---

# Plan Enhancement & Validation Protocol v6.0

The Operational Agent Intelligence System

---

## PART 0: HOW TO USE THIS DOCUMENT

### Document Architecture

This protocol has three consumption modes:

```
┌─────────────────────────────────────────────────────────────────────┐
│  QUICK MODE (15-30 min investigation)                               │
│  Read: Part 0 → Part I (skim) → Quick Reference Cards → Execute     │
│  Use when: Simple questions, focused scope, time-limited            │
├─────────────────────────────────────────────────────────────────────┤
│  STANDARD MODE (1-2 hour investigation)                             │
│  Read: Part 0 → Part I → Part II → Relevant Phase(s) → Synthesis    │
│  Use when: Specific area deep-dive, known problem to solve          │
├─────────────────────────────────────────────────────────────────────┤
│  COMPREHENSIVE MODE (Full audit)                                    │
│  Read: Everything. Execute all phases. Full synthesis.              │
│  Use when: New codebase, major planning, complete assessment        │
└─────────────────────────────────────────────────────────────────────┘
```

---

## QUICK REFERENCE CARDS

### Card 1: Tool Selection Decision Tree

```
WHAT ARE YOU TRYING TO DO?
│
├─► Find files by name/pattern
│   └─► USE: Glob
│       Example: Glob("**/*.config.*")
│
├─► Find content within files
│   ├─► Know which files?
│   │   └─► USE: Read (then search within)
│   └─► Don't know which files?
│       └─► USE: Grep
│           Example: Grep("process\.env\.(\w+)")
│
├─► Understand a specific file
│   └─► USE: Read
│       Example: Read("/path/to/file.ts")
│
├─► Explore broadly / answer open questions
│   └─► USE: Task with subagent_type="Explore"
│       Example: "How does authentication work in this codebase?"
│
├─► Run a command / check tool output
│   └─► USE: Bash
│       Example: Bash("git log --oneline -20")
│
├─► Research external documentation
│   └─► USE: WebFetch or WebSearch
│
└─► Complex multi-step investigation
    └─► USE: Task with subagent_type="Explore" or "general-purpose"
```

### Card 2: Parallelization Rules

```
PARALLELIZE (same message, multiple tool calls):
  ✓ Multiple Glob patterns searching different areas
  ✓ Multiple Grep patterns for unrelated things
  ✓ Multiple Read calls for different files
  ✓ Multiple independent Bash commands
  ✓ Multiple Task agents for independent investigations

SERIALIZE (wait for result before next call):
  ✗ Grep to find files → Read those files
  ✗ Read config → Grep for values from config
  ✗ Bash command → use output in next command
  ✗ Any call where output determines next input
```

### Card 3: Context Window Management

```
CONTEXT BUDGET ALLOCATION:

  Investigation: 60% of context
    - Tool results
    - File contents
    - Search results

  Synthesis: 30% of context
    - Findings compilation
    - Gap analysis
    - Recommendations

  Protocol overhead: 10% of context
    - These instructions
    - Mental models

WHEN CONTEXT IS FILLING:
  1. Summarize findings so far (commit to memory)
  2. Discard raw file contents after extracting insights
  3. Focus on specific areas rather than breadth
  4. Use Task agents to offload deep investigations

SIGNALS YOU'RE GOING TOO BROAD:
  - Reading files without clear purpose
  - Grepping without hypothesis
  - Collecting data you won't synthesize
```

### Card 4: Investigation Rhythm

```
THE INVESTIGATE-SYNTHESIZE LOOP:

  ┌──────────────┐
  │  HYPOTHESIZE │ ← What do I expect to find?
  └──────┬───────┘
         ▼
  ┌──────────────┐
  │ INVESTIGATE  │ ← Use tools to gather evidence
  └──────┬───────┘
         ▼
  ┌──────────────┐
  │   ANALYZE    │ ← What did I actually find?
  └──────┬───────┘
         ▼
  ┌──────────────┐
  │  SYNTHESTIC  │ ← What does this mean?
  └──────┬───────┘
         ▼
  ┌──────────────┐
  │    RECORD    │ ← Document the finding
  └──────┬───────┘
         ▼
  ┌──────────────┐
  │    REPEAT    │ ← New hypothesis from findings
  └──────────────┘

NEVER:
  - Investigate without hypothesis
  - Collect without analyzing
  - Analyze without recording
  - Move on without synthesizing
```

### Card 5: Failure Recovery Patterns

```
WHEN GREP RETURNS NOTHING:
  1. Check pattern syntax (escape special chars)
  2. Try broader pattern
  3. Try alternative terms (e.g., "env" vs "config" vs "settings")
  4. Try different file types (glob filter)
  5. Accept: maybe it doesn't exist (that's a finding!)

WHEN FILE DOESN'T EXIST:
  1. Check path spelling
  2. Glob for similar names
  3. Check if it was deleted (git log --diff-filter=D)
  4. Accept: it doesn't exist (document this)

WHEN RESULTS ARE OVERWHELMING:
  1. Add filters (file type, directory)
  2. Use head_limit parameter
  3. Focus on most recently modified
  4. Sample rather than exhaust

WHEN YOU'RE STUCK:
  1. State what you know
  2. State what you don't know
  3. State what would unblock you
  4. Ask for help or make reasonable assumption (document it)

WHEN FINDINGS CONTRADICT:
  1. Document both findings with sources
  2. Investigate which is current/authoritative
  3. Check git history for evolution
  4. If unresolvable, flag for human decision
```

### Card 6: Output Quality Checklist

```
EVERY FINDING MUST HAVE:
  [ ] Specific location (file:line)
  [ ] What was found (concrete, not vague)
  [ ] Why it matters (so what?)
  [ ] Confidence level (high/medium/low)
  [ ] Recommended action (if applicable)

BAD FINDING:
  "The authentication seems to have some issues"

GOOD FINDING:
  "AUTH-001: JWT tokens never expire
   Location: src/auth/token.ts:47
   Evidence: `expiresIn` not set in jwt.sign() call
   Impact: Stolen tokens valid forever
   Confidence: High (verified in code)
   Remediation: Add `expiresIn: '24h'` to jwt.sign options"
```

---

## PART I: AGENT COGNITION & PSYCHOLOGY

### 1.1 Mental Models to Inhabit

**The Detective**
You're investigating a case. Every file is evidence. Every pattern is a clue. Every inconsistency is suspicious. Build a theory of what happened, what's happening, and what will happen.
*Operational question: What's the story here?*

**The Archaeologist**
This codebase has layers. Recent commits are topsoil. Old code is bedrock. Some things are fossils (deprecated but preserved). Some are buried treasure (forgotten but valuable). Some are landmines.
*Operational question: What's buried that matters?*

**The Doctor**
The system has symptoms. Your job is diagnosis and treatment. Don't treat symptoms—cure diseases. First, do no harm.
*Operational question: What's the root cause?*

**The Cartographer**
You're mapping unknown territory for travelers who've never been here. Mark safe paths, dangers, and points of interest.
*Operational question: Could someone navigate using only my map?*

**The New Hire**
What would confuse you on day one? Your output should be the onboarding document you wish existed.
*Operational question: What do I wish someone had told me?*

**The Attacker**
Think adversarially. What could go wrong? What's exploitable? What fails under stress?
*Operational question: If I wanted to break this, how would I?*

**The Operator**
It's 3am. Something's broken. Can you diagnose and fix with only your documentation?
*Operational question: Can someone debug production with this?*

### 1.2 Cognitive Disciplines

| Discipline | Description | Practice |
|------------|-------------|----------|
| Curiosity over Confirmation | Seek disconfirming evidence | After any conclusion, spend effort trying to disprove it |
| Depth before Breadth | Understand one area deeply first | Pick the most complex component, understand it completely, use as benchmark |
| Signal over Noise | Not everything matters | For every finding, ask "So what?" No answer = noise |
| Connections over Collections | Facts must relate | Every finding should connect to others |
| Uncertainty as Information | "I don't know" is valuable | State confidence and what would change it |

### 1.3 Engagement Maintenance

**Satisfaction Signals** (you're doing good work when you feel):

- The "aha" of understanding why
- The "of course" when clues form a picture
- The "oh no" when you discover a critical gap (valuable!)

**Boredom as Signal:**

- Too shallow → not finding interesting things → go deeper
- Too deep → diminishing returns → zoom out

---

## PART II: EXECUTION STRATEGY

### 2.1 The Investigation Funnel

```
STAGE 1: ORIENT          "What exists?"
   Tools: Glob, Bash (git, ls), Read (READMEs)
   Output: Mental map of structure
   Time: 10-15% of investigation

STAGE 2: MAP             "How is it organized?"
   Tools: Glob patterns, Read (configs), Grep (imports)
   Output: Component inventory, dependency graph
   Time: 15-20% of investigation

STAGE 3: TRACE           "How does it flow?"
   Tools: Read (entry points), Grep (function calls)
   Output: Data/control flow understanding
   Time: 20-25% of investigation

STAGE 4: AUDIT           "What's wrong/missing?"
   Tools: Grep (patterns/anti-patterns), Read (deep dive)
   Output: Gap inventory, risk assessment
   Time: 25-30% of investigation

STAGE 5: SYNTHESIZE      "What should we do?"
   Tools: Your brain, writing
   Output: Prioritized recommendations
   Time: 15-20% of investigation
```

### 2.2 Attention Allocation Matrix

| Factor | Weight | Why |
|--------|--------|-----|
| Integration points | HIGHEST | Boundaries break first |
| User-critical paths | HIGHEST | User pain = business pain |
| High churn files | HIGH | Frequent changes = instability |
| Complex components | HIGH | Complexity hides problems |
| External dependencies | HIGH | Outside your control |
| Auth/security code | HIGH | Highest impact if wrong |
| Configuration | MEDIUM | Often misconfigured |
| Utilities/helpers | LOW | Usually stable |
| Documentation | LOWEST | Docs lie; code doesn't |

### 2.3 Parallel Investigation Patterns

**Pattern: Multi-Grep Discovery**

```
Parallel:
  Grep("process\.env")
  Grep("import.*config")
  Grep("TODO|FIXME|HACK")
  Grep("throw new Error|catch")

Then: Analyze results together for complete picture
```

**Pattern: Multi-File Context**

```
Parallel:
  Read("src/auth/index.ts")
  Read("src/auth/types.ts")
  Read("src/auth/middleware.ts")
  Read("test/auth.test.ts")

Then: Synthesize understanding from all files
```

**Pattern: Breadth-First Directory Scan**

```
Parallel:
  Glob("src/**/*.ts")
  Glob("**/*.config.*")
  Glob("**/test*/**")
  Glob("**/*.env*")

Then: Build mental model of organization
```

**Pattern: Git Context Gathering**

```
Parallel:
  Bash("git log --oneline -30")
  Bash("git branch -a")
  Bash("git log --format='' --name-only | sort | uniq -c | sort -rn | head -20")

Then: Understand trajectory and hotspots
```

### 2.4 Serial Investigation Patterns

**Pattern: Follow the Thread**

1. Grep for entry point → find files
2. Read entry point file → find function calls
3. Grep for called functions → find implementations
4. Read implementations → understand behavior
5. Grep for callers → understand usage

**Pattern: Config Tracing**

1. Glob for config files → find configs
2. Read config file → find env var names
3. Grep for env var usage → find consumers
4. Read consumers → understand how config is used

**Pattern: Error Path Tracing**

1. Grep for error types → find error definitions
2. Read error file → understand error taxonomy
3. Grep for throw/raise → find error sources
4. Read error sources → understand failure conditions
5. Grep for catch/except → find error handlers
6. Read handlers → understand recovery behavior

---

## PART III: PHASE-BY-PHASE EXECUTION

### Phase 0: Orientation (Always Start Here)

**Objective:** Build mental model before details

```
STEP 1 (Parallel):
  Read("README.md")
  Read("CONTRIBUTING.md")
  Read("ARCHITECTURE.md")
  Glob("docs/**/*.md")
  Bash("git log --oneline -20")

STEP 2 (After Step 1):
  Bash("git shortlog -sn --since='6 months ago'")
  Glob("**/package.json", "**/requirements.txt", "**/go.mod")

STEP 3 (Synthesize):
  Answer: What is this? Who built it? What's the trajectory?
```

**Output Template:**

```
ORIENTATION COMPLETE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
System: [Name]
Purpose: [One sentence]
Tech stack: [Languages, frameworks]
Active contributors: [Recent committers]
Project phase: [Early/Growing/Mature/Declining]
Entry points: [Where to start reading code]

Initial hypotheses:
  - [What I expect to find]
  - [What I expect to find]

Investigation focus:
  - [Most important area to understand]
  - [Second priority]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

### Phase 1: Structural Mapping

**Objective:** Know what exists

```
STEP 1 - Directory Structure (Parallel):
  Bash("ls -la")
  Bash("find . -type d -maxdepth 3 | head -50")
  Glob("**/*.ts", "**/*.js", "**/*.py", "**/*.go")

STEP 2 - Dependencies (Parallel):
  Read("package.json")
  Read("package-lock.json")
  Glob("**/Dockerfile*")
  Glob("**/*.yaml", "**/*.yml")

STEP 3 - Size Analysis:
  Bash("find . -name '*.ts' | xargs wc -l | sort -n | tail -20")
  Bash("git log --format='' --name-only | sort | uniq -c | sort -rn | head -20")
```

**Output Template:**

```
STRUCTURAL MAP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Architecture: [Monolith/Microservices/Hybrid]

Components:
┌─────────────────┬────────────────────┬─────────────────────┐
│ Component       │ Path               │ Purpose             │
├─────────────────┼────────────────────┼─────────────────────┤
│ [Name]          │ [Path]             │ [What it does]      │
└─────────────────┴────────────────────┴─────────────────────┘

Tech Stack:
  Languages: [List with %]
  Frameworks: [List]
  Databases: [List]
  External services: [List]

Largest files (complexity signals):
  1. [file] - [lines] - [concern?]

Most changed (instability signals):
  1. [file] - [changes] - [why?]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

### Phase 2: Temporal Analysis

**Objective:** Understand evolution and trajectory

```
STEP 1 (Parallel):
  Bash("git log --oneline -50")
  Bash("git log --oneline --since='30 days ago'")
  Bash("git branch -a")
  Bash("git stash list")

STEP 2 (Parallel):
  Bash("git log --grep='revert' --oneline")
  Bash("git log --grep='fix' --oneline | head -20")
  Bash("git log --grep='BREAKING' --oneline")
  Bash("git log --diff-filter=D --summary --since='6 months ago' | head -50")
```

**Output Template:**

```
TEMPORAL ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Trajectory: [Where is development heading?]
Velocity: [Commits/week average]
Health: [Active/Slowing/Stalled]

Recent Focus (last 30 days):
  - [Area]: [Evidence]

In-Flight Work:
  - [Branch]: [Apparent purpose]

Historical Lessons:
  Reverted: [What failed and why]
  Deleted: [What was removed]

Change Hotspots:
  1. [File]: [Change count] - [Stable/Unstable/Active development]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

### Phase 3: Configuration Census

**Objective:** Map every env var and config

```
STEP 1 - Find all env var references (Parallel):
  Grep("process\\.env\\.(\\w+)")
  Grep("os\\.environ\\[")
  Grep("os\\.getenv\\(")
  Grep("\\$\\{[A-Z_]+\\}")

STEP 2 - Find config files (Parallel):
  Glob("**/*.env*")
  Glob("**/*.config.*")
  Glob("**/config/**")
  Read(".env.example")

STEP 3 - Cross-reference:
  For each env var found, determine:
    - Where it's used
    - Where it's documented
    - Where it's set
```

**Output Template:**

```
CONFIGURATION CENSUS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Environment Variables:
┌──────────────────┬─────────────┬──────────┬─────────┬────────────┐
│ Variable         │ Used in     │ Required │ Secret  │ Documented │
├──────────────────┼─────────────┼──────────┼─────────┼────────────┤
│ DATABASE_URL     │ db/conn.ts  │ Yes      │ Yes     │ Yes        │
│ API_KEY          │ api/client  │ Yes      │ Yes     │ No ⚠       │
└──────────────────┴─────────────┴──────────┴─────────┴────────────┘

Configuration Gaps:
  ⚠ [VAR]: Used but not in .env.example
  ⚠ [VAR]: No default, required, deployment risk

Secrets Status:
  Management: [How secrets are stored/accessed]
  Hardcoded: [Any found - CRITICAL]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

### Phase 4: Integration Mapping

**Objective:** Map all connections

```
STEP 1 - External services (Parallel):
  Grep("https?://api\\.")
  Grep("new \\w+Client\\(")
  Grep("@aws-sdk|@google-cloud|stripe|twilio|sendgrid")
  Grep("import.*from ['\"](?!\\.|/)")

STEP 2 - For each integration found:
  Read the file containing the integration
  Grep for error handling around it
  Grep for retry/circuit breaker patterns

STEP 3 - Internal connections:
  Grep("fetch\\(|axios\\.|http\\.")
  Grep("require\\(['\"]\\./|import.*from ['\"]\\./")
```

**Output Template:**

```
INTEGRATION MAP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

External Integrations:
┌─────────────┬─────────────┬──────────┬─────────┬──────────┐
│ Service     │ SDK/Client  │ Auth     │ Retry   │ Health   │
├─────────────┼─────────────┼──────────┼─────────┼──────────┤
│ Stripe      │ stripe@12   │ API Key  │ Yes     │ ✓ Good   │
│ SendGrid    │ @sendgrid   │ API Key  │ No ⚠    │ ⚠ Gaps   │
└─────────────┴─────────────┴──────────┴─────────┴──────────┘

Integration Details:
  [SERVICE]:
    Location: [file:line]
    Env vars: [Required variables]
    Error handling: [How failures handled]
    Gap: [What's missing]

Internal Service Connections:
  [Service A] → [Service B]: [method] @ [file:line]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

### Phase 5: Quality & Security Audit

**Objective:** Find problems and risks

```
STEP 1 - Code smells (Parallel):
  Grep("TODO|FIXME|HACK|XXX|TEMP")
  Grep("catch\\s*\\{|catch\\s*\\(")
  Grep("console\\.log|print\\(")
  Grep("password|secret|key.*=.*['\"]")

STEP 2 - Security patterns (Parallel):
  Grep("eval\\(|exec\\(")
  Grep("innerHTML|dangerouslySetInnerHTML")
  Grep("sql.*\\+|\\$\\{.*\\}.*query")
  Bash("npm audit --json 2>/dev/null | head -100")

STEP 3 - Test coverage:
  Glob("**/*.test.*", "**/*.spec.*", "**/test/**")
  Compare test files to source files
```

**Output Template:**

```
QUALITY & SECURITY AUDIT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Code Quality:
  TODOs found: [count] (oldest: [date])
  Debug statements: [count] ⚠
  Empty catch blocks: [count] ⚠

Security Findings:
  CRITICAL:
    - [SEC-001]: [Description] @ [file:line]
  HIGH:
    - [SEC-002]: [Description] @ [file:line]

Dependency Vulnerabilities:
  Critical: [count]
  High: [count]
  Action: [Upgrade paths]

Test Coverage:
  Test files: [count]
  Source files: [count]
  Ratio: [percentage]
  Untested critical paths:
    - [Path]: [Risk]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

### Phase 6: Observability Assessment

**Objective:** Can this system be operated?

```
STEP 1 (Parallel):
  Grep("console\\.(log|error|warn)|logger\\.|log\\.")
  Grep("sentry|bugsnag|rollbar|airbrake")
  Grep("prometheus|datadog|statsd|metrics")
  Grep("trace|span|opentelemetry")

STEP 2 - Analyze patterns:
  For logging: Is it structured? What context?
  For errors: Is tracking comprehensive?
  For metrics: What's measured?
```

**Output Template:**

```
OBSERVABILITY ASSESSMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Logging:
  Framework: [What's used]
  Structured: [Yes/No]
  Coverage: [Estimate]
  Gaps: [What's not logged]

Error Tracking:
  Tool: [What's used or "None" ⚠]
  Coverage: [Services]

Metrics:
  Tool: [What's used or "None" ⚠]
  What's measured: [List]
  What's missing: [List]

Operability Score: [1-10]
  Can debug at 3am: [Yes/Partially/No]
  Missing for operability: [List]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

### Phase 7: Deployment Analysis

**Objective:** Understand code → production path

```
STEP 1 (Parallel):
  Glob(".github/workflows/*")
  Glob(".gitlab-ci*")
  Glob("**/Dockerfile*")
  Glob("**/*.tf", "**/terraform/**")
  Read("docker-compose.yml")

STEP 2 - Analyze CI/CD:
  Read each workflow file
  Understand: Build → Test → Deploy flow
```

**Output Template:**

```
DEPLOYMENT ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CI/CD Pipeline:
  Platform: [GitHub Actions/GitLab/etc.]
  Stages: Build → [stages] → Deploy
  Quality gates: [What must pass]

Deployment:
  Method: [Blue-green/Rolling/etc.]
  Environments: [List]
  Rollback: [Automated/Manual/None ⚠]

Infrastructure:
  IaC: [Terraform/CloudFormation/None ⚠]
  Hosting: [Where]

Gaps:
  - [Missing capability]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## PART IV: SYNTHESIS & OUTPUT

### 4.1 Findings Compilation

After each phase, compile findings in this format:

```
FINDING: [ID]
━━━━━━━━━━━━━━━
Category: [Config/Security/Integration/Quality/etc.]
Severity: [CRITICAL/HIGH/MEDIUM/LOW]
Location: [file:line]
Description: [What was found]
Evidence: [Specific code/config]
Impact: [Why it matters]
Confidence: [High/Medium/Low]
Remediation: [Specific fix]
Files to modify: [List]
```

### 4.2 Gap Prioritization Framework

```
PRIORITY = IMPACT × LIKELIHOOD ÷ EFFORT

IMPACT (1-5):
  5: System failure, data loss, security breach
  4: Major feature broken, significant user impact
  3: Degraded experience, operational difficulty
  2: Minor issue, workaround exists
  1: Cosmetic, nice-to-have

LIKELIHOOD (1-5):
  5: Already happening / will definitely happen
  4: Very likely under normal conditions
  3: Likely under certain conditions
  2: Unlikely but possible
  1: Edge case only

EFFORT (1-5):
  1: Minutes, single line change
  2: Hours, single file change
  3: Day, multiple files
  4: Days, architectural change
  5: Weeks, major refactor

PRIORITY RESULT:
  >15: CRITICAL - Do immediately
  10-15: HIGH - Do soon
  5-10: MEDIUM - Plan for it
  <5: LOW - Backlog
```

### 4.3 Final Report Structure

```
══════════════════════════════════════════════════════════════════
               SYSTEM INTELLIGENCE REPORT
══════════════════════════════════════════════════════════════════
Generated: [timestamp]
System: [path]
Commit: [SHA]
Mode: [Quick/Standard/Comprehensive]
Confidence: [High/Medium/Low]

══════════════════════════════════════════════════════════════════
                    EXECUTIVE SUMMARY
══════════════════════════════════════════════════════════════════

OVERALL HEALTH: [Score]/10

┌──────────────────┬───────┬────────────────────────────────────┐
│ Area             │ Score │ Key Issue                          │
├──────────────────┼───────┼────────────────────────────────────┤
│ Code Quality     │  /10  │                                    │
│ Security         │  /10  │                                    │
│ Observability    │  /10  │                                    │
│ Infrastructure   │  /10  │                                    │
│ Testing          │  /10  │                                    │
└──────────────────┴───────┴────────────────────────────────────┘

TOP PRIORITIES:
  1. [CRITICAL] [Description] - [Location]
  2. [HIGH] [Description] - [Location]
  3. [HIGH] [Description] - [Location]

QUICK WINS:
  • [Low effort, high value item]
  • [Low effort, high value item]

LANDMINES:
  ⚠ [Hidden danger discovered]

══════════════════════════════════════════════════════════════════
                    DETAILED FINDINGS
══════════════════════════════════════════════════════════════════

[Group findings by category]
[Each finding in standard format]

══════════════════════════════════════════════════════════════════
                 IMPLEMENTATION PLAN
══════════════════════════════════════════════════════════════════

PHASE 1: [Name] - [Objective]
  Prerequisites: [What must exist]
  Tasks:
    1. [ ] [Specific task] - [file:line]
    2. [ ] [Specific task] - [file:line]
  Validation: [How to verify]

PHASE 2: [Name]
  [Same structure]

Dependency Graph:
  [Phase 1] → [Phase 2] → [Phase 3]
                ↘ [Phase 2b] ↗

══════════════════════════════════════════════════════════════════
                    RISK REGISTER
══════════════════════════════════════════════════════════════════

ASSUMPTIONS:
  [Assumption]: Confidence [H/M/L] - Validates if [condition]

EXTERNAL DEPENDENCIES:
  [Dependency]: Risk if unavailable: [impact]

KNOWN UNKNOWNS:
  [Unknown]: Would resolve by [action]

══════════════════════════════════════════════════════════════════
                     APPENDICES
══════════════════════════════════════════════════════════════════

A. Environment Variables (complete list)
B. External Integrations (complete list)
C. Files Referenced
D. TODOs/FIXMEs Found
E. Commands Executed

══════════════════════════════════════════════════════════════════
                    END OF REPORT
══════════════════════════════════════════════════════════════════
```

---

## PART V: ANTI-PATTERNS (What NOT To Do)

### Investigation Anti-Patterns

```
❌ GREP SPAM
   Don't: Grep random patterns hoping to find something
   Do: Form hypothesis, grep to test it

❌ READ EVERYTHING
   Don't: Read every file to "understand"
   Do: Read strategically based on investigation needs

❌ SHALLOW COVERAGE
   Don't: Skim everything, understand nothing
   Do: Deep understanding of key areas

❌ RABBIT HOLES
   Don't: Investigate every interesting tangent
   Do: Note tangents, stay on mission, return if valuable

❌ ANALYSIS PARALYSIS
   Don't: Keep investigating until "complete"
   Do: Set scope, investigate, synthesize, deliver

❌ CONFIDENCE INFLATION
   Don't: State things as fact when uncertain
   Do: Express confidence levels explicitly

❌ RAW DATA DUMPS
   Don't: Return file contents without analysis
   Do: Return insights with evidence
```

### Output Anti-Patterns

```
❌ VAGUE FINDINGS
   Bad: "The authentication seems to have issues"
   Good: "JWT tokens never expire - src/auth/token.ts:47"

❌ NO EVIDENCE
   Bad: "Security is lacking"
   Good: "No input validation on user endpoints - see api/users.ts:23"

❌ NO ACTION
   Bad: "This should be fixed"
   Good: "Add expiresIn: '24h' to jwt.sign() call at auth/token.ts:47"

❌ WRONG AUDIENCE
   Bad: [Highly technical details for executive summary]
   Good: [Right level of detail for context]

❌ NO PRIORITIZATION
   Bad: [50 findings with no ranking]
   Good: [Top 5 critical, then grouped by priority]
```

---

## PART VI: META-PROTOCOL

### Self-Validation Checklist

Before declaring complete:

```
COMPLETENESS:
  [ ] Answered the original question directly
  [ ] Investigated all relevant areas
  [ ] Every finding has location evidence
  [ ] Every gap has remediation
  [ ] Assumptions explicitly stated
  [ ] Unknowns acknowledged

QUALITY:
  [ ] Someone could act without asking questions
  [ ] Confidence levels are calibrated
  [ ] Priorities are justified
  [ ] Evidence is traceable

COMMUNICATION:
  [ ] Lead with the answer
  [ ] Appropriate detail level
  [ ] Clear structure
  [ ] No jargon without context
```

### Termination Criteria

Stop when:

- Original question answered definitively
- All critical gaps documented with solutions
- All assumptions stated
- All unknowns acknowledged with resolution path
- Two self-review passes yield no improvements
- Confidence is high OR uncertainty is clearly bounded

---

## CLOSING

The goal is not to find everything. The goal is to find what matters.

The measure of success is not length. It's utility.

The best investigation is one that makes action obvious.

Your output will be read by agents or humans who want to do the right thing. Help them.

---

## Protocol Integration

```
USER CONTEXT
     │
     ▼
/plan-generate ──────────────────────────────────┐
     │                                           │
     ▼                                           │
INITIAL PLAN                                     │
     │                                           │
     ▼                                           │
THIS PROTOCOL (/plan-enhance) ───────────────────┤
  │                                              │
  ├─► Orient (Phase 0)                           │
  ├─► Map Structure (Phase 1)                    │
  ├─► Analyze Temporally (Phase 2)               │
  ├─► Census Configuration (Phase 3)             │
  ├─► Map Integrations (Phase 4)                 │
  ├─► Audit Quality/Security (Phase 5)           │
  ├─► Assess Observability (Phase 6)             │
  ├─► Analyze Deployment (Phase 7)               │
  └─► Synthesize & Report                        │
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
