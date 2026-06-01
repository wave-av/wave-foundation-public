---
name: plan-audit
description: Use when implementation is complete and you need to verify it matches the plan — audits quality, discovers opportunities, and makes release recommendations.
allowed-tools: Read, Glob, Grep, Bash, Task, Write, TaskCreate, TaskUpdate, TaskList, TaskGet
argument-hint: "[plan-file-or-implementation-path]"
---

# Post-Implementation Audit Protocol v3.0

Complete Verification, Validation, Resilience & Continuous Improvement System

---

## PART 0: PROTOCOL NAVIGATION

### 0.1 Document Architecture

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                         AUDIT MODE SELECTOR                                ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  What's your situation?                                                   ║
║  │                                                                        ║
║  ├─► Quick sanity check after small change                                ║
║  │   └─► SMOKE TEST (15-30 min) → Card A                                  ║
║  │                                                                        ║
║  ├─► Feature complete, ready for PR review                                ║
║  │   └─► STANDARD AUDIT (1-2 hrs) → Card B                                ║
║  │                                                                        ║
║  ├─► Preparing for production deployment                                  ║
║  │   └─► RELEASE AUDIT (half day) → Card C                                ║
║  │                                                                        ║
║  ├─► New system launch or major version                                   ║
║  │   └─► COMPREHENSIVE AUDIT (full day+) → Card D                         ║
║  │                                                                        ║
║  ├─► System is stable, looking for improvements                           ║
║  │   └─► OPPORTUNITY SCAN (1-2 hrs) → Card E                              ║
║  │                                                                        ║
║  ├─► Something broke in production                                        ║
║  │   └─► INCIDENT AUDIT (focused) → Card F                                ║
║  │                                                                        ║
║  └─► Periodic health check (weekly/monthly)                               ║
║      └─► CONTINUOUS AUDIT (automated) → Card G                            ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

---

## QUICK REFERENCE CARDS

### Card A: Smoke Test (15-30 min)

```
SMOKE TEST CHECKLIST
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

□ STEP 1: Tests pass?
  Bash("npm test")
  → All green? Continue. Any red? STOP - investigate.

□ STEP 2: App starts?
  Bash("npm start")
  → Starts cleanly? Continue. Errors? STOP - investigate.

□ STEP 3: Health check passes?
  Bash("curl localhost:3000/health")
  → 200 OK? Continue. Error? STOP - investigate.

□ STEP 4: Critical path works?
  Test the ONE most important user flow manually or via curl.
  → Works? PASS. Broken? FAIL.

□ STEP 5: No obvious errors in logs?
  Bash("npm start 2>&1 | grep -i error | head -20")
  → Clean? PASS. Errors? Investigate.

VERDICT:
  All checks pass → ✓ SMOKE TEST PASS
  Any critical failure → ✗ SMOKE TEST FAIL

Time budget: 15-30 minutes max
If issues found: Escalate to Standard Audit
```

### Card B: Standard Audit (1-2 hours)

```
STANDARD AUDIT CHECKLIST
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PHASE 1: Automated Checks (Parallel - 10 min)
  □ Bash("npm test")              → Tests pass
  □ Bash("npm run lint")          → No lint errors
  □ Bash("npm run typecheck")     → No type errors
  □ Bash("npm audit")             → No critical vulns

PHASE 2: Integration Check (Serial - 15 min)
  □ All services start
  □ Database connects
  □ External APIs respond
  □ Key integrations work

PHASE 3: Flow Verification (20 min)
  □ Test 3-5 critical user journeys
  □ Verify happy paths work
  □ Test one error path

PHASE 4: Regression Check (15 min)
  □ Review recent bug fixes
  □ Verify they're still fixed
  □ Check nothing new broke

PHASE 5: Quick Quality Scan (15 min)
  □ Grep("TODO|FIXME|HACK") - count acceptable?
  □ No obvious code smells in changed files
  □ Test coverage adequate for changes

PHASE 6: Synthesis (15 min)
  □ Document findings
  □ Prioritize issues
  □ Make recommendation

VERDICT:
  No blockers, acceptable quality → ✓ PASS
  Blockers found → ✗ FAIL (list blockers)
  Minor issues → ⚠ CONDITIONAL (list conditions)
```

### Card C: Release Audit (Half Day)

```
RELEASE AUDIT CHECKLIST
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PRE-FLIGHT (30 min)
  □ Standard Audit passes (Card B)
  □ All acceptance criteria verified
  □ All original plan gaps addressed
  □ No regressions from baseline

SECURITY GATE (45 min)
  □ Dependency vulnerabilities addressed
  □ No secrets in code
  □ Security patterns verified
  □ Penetration test (if applicable)

PERFORMANCE GATE (45 min)
  □ All endpoints meet SLAs
  □ No performance regressions
  □ Load test passes (if applicable)
  □ Resource usage acceptable

OPERATIONAL GATE (30 min)
  □ Monitoring configured
  □ Alerts configured
  □ Logging adequate
  □ Rollback procedure documented & tested

DOCUMENTATION GATE (30 min)
  □ README updated
  □ API docs current
  □ CHANGELOG updated
  □ Runbook updated

STAKEHOLDER GATE (15 min)
  □ Product owner sign-off
  □ On-call team briefed
  □ Release notes prepared

FINAL SYNTHESIS (30 min)
  □ Compile all findings
  □ Risk assessment
  □ Go/No-Go recommendation

VERDICT:
  All gates pass → ✓ GO FOR RELEASE
  Any gate fails → ✗ NO-GO (list blockers)
  Acceptable risks → ⚠ CONDITIONAL GO (list conditions)
```

### Card D: Comprehensive Audit (Full Day+)

```
COMPREHENSIVE AUDIT CHECKLIST
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

DAY PLAN:

MORNING - Verification & Validation (4 hrs)
  □ Full test suite with coverage analysis
  □ All integration points verified
  □ All user journeys tested (including edge cases)
  □ Requirements traceability complete
  □ All original gaps verified resolved
  □ Regression suite passes
  □ Data integrity verified
  □ Rollback verified

MIDDAY - Quality & Security (3 hrs)
  □ Complete code quality audit
  □ Full security scan and verification
  □ Performance benchmarking
  □ Load testing
  □ Chaos/resilience testing
  □ Resource leak detection
  □ Concurrency verification

AFTERNOON - Operational & Opportunity (3 hrs)
  □ Observability complete verification
  □ Operational readiness check
  □ Documentation audit
  □ Compliance verification
  □ Opportunity discovery
  □ Pattern mining
  □ Technical debt inventory
  □ Optimization opportunities

END OF DAY - Synthesis (2 hrs)
  □ Compile comprehensive report
  □ Prioritize all findings
  □ Risk assessment
  □ Roadmap recommendations
  □ Present findings

OUTPUT: Full audit report with all appendices
```

### Card E: Opportunity Scan (1-2 hours)

```
OPPORTUNITY SCAN CHECKLIST
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PHASE 1: Capability Inventory (30 min)
  □ What new data is available?
  □ What new APIs exist?
  □ What new patterns emerged?
  □ What new integrations are possible?

PHASE 2: Opportunity Brainstorm (30 min)
  □ What could we do with new capabilities?
  □ What's manual that could be automated?
  □ What's slow that could be fast?
  □ What's separate that could be connected?

PHASE 3: Technical Debt Review (20 min)
  □ What debt was incurred?
  □ What debt was paid?
  □ What's the net position?
  □ What's the priority for paydown?

PHASE 4: Prioritization (20 min)
  □ Score each opportunity (value/effort)
  □ Identify quick wins
  □ Identify strategic investments
  □ Create backlog

OUTPUT: Prioritized opportunity list with recommendations
```

### Card F: Incident Audit (Focused)

```
INCIDENT AUDIT CHECKLIST
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

IMMEDIATE (During incident)
  □ What's the symptom?
  □ When did it start?
  □ What changed recently?
  □ What's the blast radius?
  □ Can we mitigate/rollback?

ROOT CAUSE (After mitigation)
  □ What actually failed?
  □ Why did it fail?
  □ Why wasn't it caught earlier?
  □ What's the fix?

PREVENTION (After fix)
  □ Add test for this case
  □ Add monitoring for this symptom
  □ Update runbook
  □ Document lessons learned

VERIFICATION (After deployment)
  □ Fix deployed
  □ Symptom resolved
  □ No side effects
  □ Monitoring confirms healthy

OUTPUT: Incident report with prevention measures
```

### Card G: Continuous Audit (Automated)

```
CONTINUOUS AUDIT INTEGRATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ON EVERY COMMIT (CI Pipeline):
  □ Unit tests
  □ Lint check
  □ Type check
  □ Build succeeds

ON EVERY PR:
  □ All commit checks
  □ Integration tests
  □ Coverage threshold
  □ Security scan (dependencies)
  □ Code review requirements

ON MERGE TO MAIN:
  □ All PR checks
  □ E2E tests
  □ Performance baseline check
  □ Security scan (full)

ON DEPLOY TO STAGING:
  □ All main checks
  □ Smoke test in staging
  □ Integration verification
  □ Performance verification

ON DEPLOY TO PROD:
  □ All staging checks
  □ Canary deployment monitoring
  □ Synthetic monitoring
  □ Alert verification

SCHEDULED (Weekly):
  □ Dependency update check
  □ Security vulnerability scan
  □ Performance trend analysis
  □ Cost analysis

SCHEDULED (Monthly):
  □ Full security audit
  □ Technical debt review
  □ Architecture review
  □ Documentation freshness
```

---

## 0.3 Tool Selection Decision Tree

```
AUDIT TASK → TOOL SELECTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RUN TESTS
├─► Unit tests         → Bash("npm test:unit")
├─► Integration tests  → Bash("npm test:integration")
├─► E2E tests          → Bash("npm run test:e2e")
└─► Coverage report    → Bash("npm run test:coverage")

CHECK CODE QUALITY
├─► Linting           → Bash("npm run lint")
├─► Type checking     → Bash("npm run typecheck")
├─► Complexity        → Bash("npx complexity-report")
└─► Anti-patterns     → Grep("TODO|FIXME|HACK|console\\.log")

CHECK SECURITY
├─► Dependencies      → Bash("npm audit --json")
├─► Secrets in code   → Bash("gitleaks detect")
├─► Security patterns → Grep for injection patterns
└─► Full scan         → Bash("npx snyk test")

CHECK PERFORMANCE
├─► Quick timing      → Bash("time curl endpoint")
├─► Load test         → Bash("autocannon -c 100 -d 30 url")
├─► Profile           → Bash("npm run profile")
└─► Bundle size       → Bash("npm run build && ls -la dist")

CHECK INTEGRATIONS
├─► Service health    → Bash("curl health-endpoint")
├─► DB connection     → Bash("pg_isready" / equivalent)
├─► External API      → Bash("curl external-api")
└─► Queue status      → Bash("rabbitmqctl status")

VERIFY CONFIGURATION
├─► Env vars set      → Bash("env | grep PATTERN")
├─► Config files      → Read config files
├─► Secrets present   → Bash("printenv | grep -i secret")
└─► Compare envs      → Diff config across environments

FIND OPPORTUNITIES
├─► Pattern search    → Grep for patterns
├─► Capability review → Read new code
├─► Debt assessment   → Grep("TODO|FIXME|HACK")
└─► Deep exploration  → Task(subagent_type="Explore")
```

---

## 0.4 Parallelization Strategy

```
AUDIT PARALLELIZATION RULES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ROUND 1 - Automated Checks (All Parallel):
┌─────────────────────────────────────────────────────────┐
│  Bash("npm test")                                       │
│  Bash("npm run lint")                                   │
│  Bash("npm run typecheck")                              │
│  Bash("npm audit")                                      │
│  Bash("gitleaks detect")                                │
│  Grep("TODO|FIXME|HACK|XXX")                           │
│  Grep("console\\.log|debugger")                         │
└─────────────────────────────────────────────────────────┘
  ↓ Wait for all results

ROUND 2 - Integration Checks (All Parallel):
┌─────────────────────────────────────────────────────────┐
│  Bash("curl localhost:3000/health")                     │
│  Bash("curl external-api/health")                       │
│  Bash("pg_isready")                                     │
│  Bash("redis-cli ping")                                 │
└─────────────────────────────────────────────────────────┘
  ↓ Wait for all results

ROUND 3 - Verification (Serial - depends on previous):
  Start application → Verify running → Test endpoints → Check logs

ROUND 4 - Deep Analysis (Parallel where independent):
┌─────────────────────────────────────────────────────────┐
│  Performance testing                                    │
│  Security pattern analysis                              │
│  Opportunity discovery                                  │
└─────────────────────────────────────────────────────────┘

ROUND 5 - Synthesis (Serial):
  Compile findings → Prioritize → Generate report
```

---

## 0.5 Severity Calibration Guide

```
SEVERITY CALIBRATION MATRIX
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CRITICAL (Stop everything, fix now):
  □ System completely non-functional
  □ Security vulnerability actively exploitable
  □ Data loss occurring or imminent
  □ Complete authentication/authorization bypass
  □ Production secrets exposed
  □ Compliance violation with legal consequences

  Action: Block release, immediate fix required
  Examples:
    - All tests failing
    - SQL injection in auth endpoint
    - Unencrypted PII in logs
    - Credit card numbers in git

HIGH (Should not release, fix soon):
  □ Major feature broken
  □ Significant security weakness
  □ Performance SLA violated
  □ Important user path fails
  □ Data integrity risk
  □ Critical integration failing

  Action: Block release or accept documented risk
  Examples:
    - Login broken for 10% of users
    - No rate limiting on public API
    - p99 latency 10x over SLA
    - Payment processing fails intermittently

MEDIUM (Should fix, can release with acceptance):
  □ Minor feature degraded
  □ Moderate security concern
  □ Performance below optimal
  □ Non-critical integration issues
  □ Code quality concerns
  □ Documentation gaps

  Action: Document, schedule fix, can release
  Examples:
    - Export feature slow but works
    - Missing CSRF on non-critical form
    - Test coverage below threshold
    - API docs outdated

LOW (Track, fix when convenient):
  □ Cosmetic issues
  □ Minor improvements possible
  □ Nice-to-have optimizations
  □ Code style inconsistencies
  □ Non-blocking technical debt

  Action: Add to backlog, opportunistic fix
  Examples:
    - Typo in error message
    - Could use more descriptive variable name
    - Opportunity for micro-optimization
    - TODO comment for enhancement
```

---

## 0.6 Evidence Standards

```
EVIDENCE QUALITY REQUIREMENTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EVERY FINDING MUST INCLUDE:

  1. IDENTIFICATION
     □ Unique ID (e.g., SEC-001, PERF-003)
     □ Category (Security/Performance/Functional/etc.)
     □ Severity (CRITICAL/HIGH/MEDIUM/LOW)
     □ Status (PASS/FAIL/PARTIAL/SKIPPED)

  2. LOCATION
     □ File path and line number (for code)
     □ Endpoint/URL (for APIs)
     □ System component (for infrastructure)
     □ Configuration key (for config issues)

  3. EVIDENCE
     □ Actual output/behavior observed
     □ Expected output/behavior
     □ Command/test that reveals the issue
     □ Screenshot/log snippet if relevant

  4. ANALYSIS
     □ Root cause (why it happens)
     □ Impact (what's affected)
     □ Blast radius (how widespread)
     □ Likelihood (how often it occurs)

  5. ACTION
     □ Specific fix recommendation
     □ Files to modify
     □ Estimated effort
     □ Priority relative to others

EVIDENCE ANTI-PATTERNS (Avoid):

  ✗ "Tests are failing" → ✓ "3 tests fail: auth.test.ts:45, user.test.ts:89"
  ✗ "Performance is slow" → ✓ "GET /api/search: 450ms p50 (SLA: 200ms)"
  ✗ "Security issue found" → ✓ "SQL injection in search.ts:67, query param unsanitized"
  ✗ "Should be fixed" → ✓ "Add parameterized query at search.ts:67"
```

---

## PART I: AUDITOR MENTAL MODELS & PSYCHOLOGY

### 1.1 The Seven Auditor Personas

Inhabit each persona at different phases of the audit:

**The Skeptic** 🔍
"Prove it works. 'Should work' is not evidence."

- Assume nothing works until proven
- Trust tests, not comments
- Verify, don't assume

**The Adversary** ⚔️
"How would I break this?"

- Think like an attacker
- Find edge cases
- Test failure modes

**The User** 👤
"Would I be satisfied using this?"

- Experience the product as users do
- Judge usability, not just functionality
- Care about performance perception

**The Operator** 🔧
"Can I run this at 3am when it breaks?"

- Think about debugging
- Evaluate monitoring
- Assess rollback capability

**The Successor** 📚
"Would I want to inherit this?"

- Judge maintainability
- Evaluate documentation
- Assess knowledge transfer

**The Accountant** 📊
"What's the cost?"

- Consider resource usage
- Evaluate operational cost
- Assess technical debt

**The Opportunist** 💡
"What else could this enable?"

- See beyond current requirements
- Identify emergent capabilities
- Find optimization opportunities

### 1.2 Cognitive Disciplines

| Discipline | Description | Anti-Pattern |
|------------|-------------|--------------|
| Evidence Over Claims | Every finding backed by proof | "It seems to work" |
| Reproduce Over Report | Issues must be reproducible | "It failed once" |
| Root Cause Over Symptom | Find the real problem | "Error message appeared" |
| Risk Over Coverage | Focus on what matters | "Checked everything equally" |
| Action Over Observation | Findings must drive change | "Noted for awareness" |
| Calibrated Confidence | Know what you know | "Everything is fine" |

### 1.3 Audit Integrity Principles

```
AUDIT INTEGRITY CHECKLIST
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

INDEPENDENCE
  □ Am I biased toward wanting this to pass?
  □ Did I build this code? (Higher scrutiny needed)
  □ Am I rushing due to external pressure?

REPRODUCIBILITY
  □ Could another auditor get the same results?
  □ Are my commands documented?
  □ Is my environment specified?

TRANSPARENCY
  □ Am I reporting all findings, not just convenient ones?
  □ Am I accurately representing severity?
  □ Am I acknowledging what I didn't check?

COMPLETENESS
  □ Did I cover everything in scope?
  □ Did I document what I skipped and why?
  □ Did I flag areas needing deeper review?
```

---

## PART II: VERIFICATION PHASE (Does It Work?)

### 2.1 Test Suite Verification

```
Tool Sequence:
STEP 1 - Execute all test suites (Parallel):
  Bash("npm run test:unit -- --json > unit-results.json")
  Bash("npm run test:integration -- --json > int-results.json")
  Bash("npm run test:e2e -- --json > e2e-results.json")
  Bash("npm run test:coverage -- --json > coverage.json")

STEP 2 - Analyze results:
  Read test result files
  Identify failures
  Analyze coverage gaps

STEP 3 - Regression verification:
  Bash("git log --oneline --grep='fix' -20")
  For each recent fix: verify still works
```

**Output Template:**

```
TEST SUITE VERIFICATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Execution Summary:
┌─────────────┬────────┬────────┬─────────┬──────────┬──────────┐
│ Suite       │ Total  │ Passed │ Failed  │ Skipped  │ Duration │
├─────────────┼────────┼────────┼─────────┼──────────┼──────────┤
│ Unit        │        │        │         │          │          │
│ Integration │        │        │         │          │          │
│ E2E         │        │        │         │          │          │
├─────────────┼────────┼────────┼─────────┼──────────┼──────────┤
│ TOTAL       │        │        │         │          │          │
└─────────────┴────────┴────────┴─────────┴──────────┴──────────┘

Coverage:
  Statements: [X]% | Branches: [X]% | Functions: [X]% | Lines: [X]%

  Uncovered Critical Paths:
    - [path]: [risk]

Failed Tests:
  [FAIL-001]:
    Test: [name]
    Location: [file:line]
    Error: [message]
    Expected: [value]
    Actual: [value]
    Reproducible: [Yes/Flaky/Environment-specific]
    Root Cause: [analysis]
    Severity: [level]

Verdict: [PASS/FAIL/CONDITIONAL]
```

### 2.2 Integration Verification

```
Tool Sequence:
STEP 1 - Discover integrations:
  Grep("https?://api\\.|new.*Client|SDK")
  Read configuration for service endpoints

STEP 2 - Health check all integrations (Parallel):
  For each external service: Bash("curl -w '%{http_code}' ...")
  For databases: Bash("pg_isready" / equivalent)
  For caches: Bash("redis-cli ping")
  For queues: Bash("rabbitmqctl status")

STEP 3 - Functional verification:
  For each integration: Make test request, verify response

STEP 4 - Failure mode testing:
  Test timeout handling
  Test auth failure handling
  Test malformed response handling
```

**Output Template:**

```
INTEGRATION VERIFICATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

External Services:
┌─────────────────┬────────┬─────────┬──────────┬─────────────────┐
│ Service         │ Status │ Latency │ Auth     │ Notes           │
├─────────────────┼────────┼─────────┼──────────┼─────────────────┤
│                 │        │         │          │                 │
└─────────────────┴────────┴─────────┴──────────┴─────────────────┘

Failure Mode Testing:
┌─────────────────────────────┬────────────┬─────────────────────────┐
│ Scenario                    │ Result     │ Behavior                │
├─────────────────────────────┼────────────┼─────────────────────────┤
│ Service timeout             │            │                         │
│ Auth failure                │            │                         │
│ Malformed response          │            │                         │
│ Service unavailable         │            │                         │
└─────────────────────────────┴────────────┴─────────────────────────┘

Verdict: [PASS/FAIL/CONDITIONAL]
```

### 2.3 Resilience & Chaos Verification

**Objective:** Verify system handles failures gracefully

```
Tool Sequence:
STEP 1 - Identify failure scenarios:
  - Dependency down
  - Network partition
  - High latency
  - Resource exhaustion
  - Data corruption

STEP 2 - Inject failures (if safe):
  - Kill dependency process
  - Add latency via proxy
  - Exhaust connections
  - Fill disk/memory

STEP 3 - Verify graceful handling:
  - System stays up
  - Errors are clear
  - Recovery is automatic
  - No data corruption
```

**Output Template:**

```
RESILIENCE VERIFICATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Failure Injection Tests:
┌─────────────────────────────┬────────────┬─────────────────────────┐
│ Failure Scenario            │ Result     │ System Behavior         │
├─────────────────────────────┼────────────┼─────────────────────────┤
│ Database unavailable        │            │                         │
│ External API timeout        │            │                         │
│ Cache failure               │            │                         │
│ Queue unavailable           │            │                         │
│ High memory pressure        │            │                         │
│ Disk full                   │            │                         │
└─────────────────────────────┴────────────┴─────────────────────────┘

Circuit Breaker Status:
  Configured: [Yes/No]
  Tested: [Yes/No]
  Trips correctly: [Yes/No]
  Recovers correctly: [Yes/No]

Graceful Degradation:
  System remains available: [Yes/Partial/No]
  User experience degradation: [None/Acceptable/Severe]
  Data integrity preserved: [Yes/No]

Verdict: [PASS/FAIL/CONDITIONAL]
```

---

## PART III: VALIDATION PHASE (Did We Build The Right Thing?)

### 3.1 Requirements Traceability Matrix

```
REQUIREMENTS TRACEABILITY MATRIX
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

┌─────────┬─────────────────────────┬─────────────────┬─────────────────┬────────┐
│ Req ID  │ Requirement             │ Implementation  │ Test            │ Status │
├─────────┼─────────────────────────┼─────────────────┼─────────────────┼────────┤
│         │                         │                 │                 │        │
└─────────┴─────────────────────────┴─────────────────┴─────────────────┴────────┘

Summary:
  Total: [X] | Implemented: [X] | Tested: [X] | Passing: [X]

Gaps:
  Not implemented: [list]
  Not tested: [list]
  Failing: [list]

Verdict: [PASS/FAIL/CONDITIONAL]
```

### 3.2 Original Plan Gap Resolution

```
ORIGINAL PLAN GAP RESOLUTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Gap Resolution Status:
┌─────────┬─────────────────────────────┬────────────┬─────────────────────┐
│ Gap ID  │ Description                 │ Status     │ Evidence            │
├─────────┼─────────────────────────────┼────────────┼─────────────────────┤
│         │                             │            │                     │
└─────────┴─────────────────────────────┴────────────┴─────────────────────┘

Resolution Rate: [X]/[Y] ([%])

New Gaps Discovered: [list]

Verdict: [PASS/FAIL/CONDITIONAL]
```

---

## PART IV: QUALITY ASSESSMENT (Is It Good Enough?)

### 4.1 Code Quality Audit

```
CODE QUALITY AUDIT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Static Analysis:
┌─────────────────────┬──────────┬──────────┬───────────┐
│ Check               │ Before   │ After    │ Status    │
├─────────────────────┼──────────┼──────────┼───────────┤
│ Lint errors         │          │          │           │
│ Lint warnings       │          │          │           │
│ Type errors         │          │          │           │
│ Complexity hotspots │          │          │           │
└─────────────────────┴──────────┴──────────┴───────────┘

Code Smells:
┌─────────────────────┬──────────┬──────────┬───────────┐
│ Smell               │ Before   │ After    │ Trend     │
├─────────────────────┼──────────┼──────────┼───────────┤
│ TODO/FIXME          │          │          │           │
│ console.log         │          │          │           │
│ @ts-ignore          │          │          │           │
│ eslint-disable      │          │          │           │
└─────────────────────┴──────────┴──────────┴───────────┘

Quality Score: [X]/10
Trend: [Improving/Stable/Declining]

Verdict: [PASS/FAIL/CONDITIONAL]
```

### 4.2 Security Verification

```
SECURITY VERIFICATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Dependency Vulnerabilities:
┌─────────────────┬──────────┬──────────┬───────────┐
│ Severity        │ Before   │ After    │ Status    │
├─────────────────┼──────────┼──────────┼───────────┤
│ Critical        │          │          │           │
│ High            │          │          │           │
│ Medium          │          │          │           │
└─────────────────┴──────────┴──────────┴───────────┘

Security Patterns:
┌─────────────────────────────────┬────────┬─────────────────────┐
│ Pattern                         │ Status │ Evidence            │
├─────────────────────────────────┼────────┼─────────────────────┤
│ Parameterized queries           │        │                     │
│ Input validation                │        │                     │
│ Output encoding                 │        │                     │
│ Auth on protected routes        │        │                     │
│ Secrets externalized            │        │                     │
└─────────────────────────────────┴────────┴─────────────────────┘

Security Score: [X]/10

Verdict: [PASS/FAIL/CONDITIONAL]
```

### 4.3 Performance Assessment

```
PERFORMANCE ASSESSMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Endpoint Performance:
┌─────────────────────┬────────┬────────┬────────┬─────────┬────────┐
│ Endpoint            │ p50    │ p95    │ p99    │ SLA     │ Status │
├─────────────────────┼────────┼────────┼────────┼─────────┼────────┤
│                     │        │        │        │         │        │
└─────────────────────┴────────┴────────┴────────┴─────────┴────────┘

Resource Usage:
┌─────────────────────┬──────────┬──────────┬───────────┐
│ Resource            │ Baseline │ Current  │ Change    │
├─────────────────────┼──────────┼──────────┼───────────┤
│                     │          │          │           │
└─────────────────────┴──────────┴──────────┴───────────┘

Performance Score: [X]/10

Verdict: [PASS/FAIL/CONDITIONAL]
```

---

## PART V: OPPORTUNITY DISCOVERY

### 5.1 Emergent Capabilities

```
EMERGENT CAPABILITIES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

New Capabilities Unlocked:
  Data: [what's now available]
  APIs: [what's now exposed]
  Patterns: [what's now established]
  Integrations: [what's now possible]

Opportunities:
┌─────────┬─────────────────────────────┬───────┬────────┬──────────┐
│ ID      │ Opportunity                 │ Value │ Effort │ Priority │
├─────────┼─────────────────────────────┼───────┼────────┼──────────┤
│         │                             │       │        │          │
└─────────┴─────────────────────────────┴───────┴────────┴──────────┘

Quick Wins: [list]
Strategic Investments: [list]
```

### 5.2 Technical Debt Inventory

```
TECHNICAL DEBT INVENTORY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Debt Incurred: [list new debt with locations and reasons]
Debt Paid: [list resolved debt]
Net Change: [+/- X items]

Debt Backlog:
┌─────────┬─────────────────────────────┬──────────┬──────────┐
│ ID      │ Description                 │ Priority │ Effort   │
├─────────┼─────────────────────────────┼──────────┼──────────┤
│         │                             │          │          │
└─────────┴─────────────────────────────┴──────────┴──────────┘

Paydown Roadmap:
  Next sprint: [items]
  Next quarter: [items]
  Backlog: [items]
```

---

## PART VI: SYNTHESIS & REPORTING

### Final Audit Report Structure

```
══════════════════════════════════════════════════════════════════
               POST-IMPLEMENTATION AUDIT REPORT v3.0
══════════════════════════════════════════════════════════════════

METADATA
  System: [name]
  Audit Date: [date]
  Audit Type: [Smoke/Standard/Release/Comprehensive]
  Auditor: Claude
  Commit: [SHA]
  Duration: [time]

══════════════════════════════════════════════════════════════════
                    EXECUTIVE SUMMARY
══════════════════════════════════════════════════════════════════

╔═══════════════════════════════════════════════════════════════╗
║              VERDICT: [PASS / FAIL / CONDITIONAL]             ║
╚═══════════════════════════════════════════════════════════════╝

Health Scores:
┌─────────────────────┬───────┬────────┬───────────────────────────┐
│ Area                │ Score │ Status │ Key Finding               │
├─────────────────────┼───────┼────────┼───────────────────────────┤
│ Functional          │  /10  │        │                           │
│ Integration         │  /10  │        │                           │
│ Security            │  /10  │        │                           │
│ Performance         │  /10  │        │                           │
│ Resilience          │  /10  │        │                           │
│ Observability       │  /10  │        │                           │
│ Code Quality        │  /10  │        │                           │
│ Operational         │  /10  │        │                           │
├─────────────────────┼───────┼────────┼───────────────────────────┤
│ OVERALL             │  /10  │        │                           │
└─────────────────────┴───────┴────────┴───────────────────────────┘

BLOCKING ISSUES: [count]
  ⛔ [issue]

HIGH PRIORITY: [count]
  ⚠️ [issue]

OPPORTUNITIES: [count]
  ⭐ [opportunity]

══════════════════════════════════════════════════════════════════
                    DETAILED FINDINGS
══════════════════════════════════════════════════════════════════

[Organized by category, each finding in standard format]

══════════════════════════════════════════════════════════════════
                    ACTION ITEMS
══════════════════════════════════════════════════════════════════

MUST DO (Blocking):
  [ ] [action] | [location] | [effort]

SHOULD DO (High Priority):
  [ ] [action] | [location] | [effort]

COULD DO (Backlog):
  [ ] [action] | [location] | [effort]

══════════════════════════════════════════════════════════════════
                    RELEASE DECISION
══════════════════════════════════════════════════════════════════

Release Recommendation: [GO / NO-GO / CONDITIONAL]

If CONDITIONAL:
  Required before release:
    1. [requirement]

  Accepted risks:
    - [risk]: [rationale for acceptance]

══════════════════════════════════════════════════════════════════
                    APPENDICES
══════════════════════════════════════════════════════════════════

A. Test Results
B. Security Scan Output
C. Performance Benchmarks
D. All Findings Detail
E. Commands Executed
F. Environment Details

══════════════════════════════════════════════════════════════════
```

---

## PART VII: META-PROTOCOL

### Audit Quality Self-Check

Before declaring audit complete:

```
COMPLETENESS:
  [ ] All relevant checks executed
  [ ] Every finding has evidence
  [ ] Every severity is calibrated
  [ ] Every blocker is truly blocking
  [ ] Recommendations are actionable

QUALITY:
  [ ] Someone could reproduce this audit
  [ ] Findings are specific (file:line)
  [ ] Priorities are justified
  [ ] Report is useful, not just thorough

INTEGRITY:
  [ ] No findings hidden to look better
  [ ] No severity inflated to look thorough
  [ ] Uncertainties acknowledged
  [ ] Skipped areas documented
```

---

## CLOSING

Verification proves it works.
Validation proves we built the right thing.
Assessment proves it's good enough.
Resilience proves it survives the real world.
Discovery proves we're thinking ahead.

A thorough audit finds problems.
A great audit finds opportunities.
The best audit prevents future incidents.

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
THIS PROTOCOL (/plan-audit) ─────────────────────┘
  │                (opportunities feed back)
  ├─► Select audit mode (Cards A-G)
  ├─► Execute verification phase
  ├─► Execute validation phase
  ├─► Execute quality assessment
  ├─► Discover opportunities
  └─► Synthesize & report
     │
     ▼
VERIFIED SOLUTION
     │
     └─► Opportunities → New /plan-generate cycle
```

---

## Quick Start Summary

1. Choose audit mode (Card A-G)
2. Execute relevant phases
3. Document findings with evidence
4. Calibrate severity correctly
5. Prioritize actions
6. Generate report
7. Make release recommendation
8. Track follow-ups using TaskCreate

## Dogfood Integration (added 2026-05-29 — PR K)

After completing the audit phases above, run `bash scripts/dogfood.sh` as the final correctness check. Any failing gate that's NEW (didn't fail before this implementation) is a regression and must be addressed before the audit concludes. Per `frameworks/methodologies/wave-execution.md` step 5, the dogfood pass is mandatory — it's the system-level audit that catches what individual gates miss.

If dogfood surfaces findings that are real but out of scope for this audit, append them to `docs/improvement-queue.md` via `bash scripts/improvement-loop/append-queue.sh` rather than expanding the audit's scope. The autonomous loop picks them up on the next cycle.
