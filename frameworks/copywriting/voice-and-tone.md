# WAVE Copywriting Standard — voice, tone & the human/agent taxonomy

_Foundation standard. Ported from wave-surfer-connect `.claude/rules/80-copywriting` + agent-experience.
Every WAVE surface — spoke pages, docs, emails, agent surfaces — runs its copy through this._

## Brand voice (constant)

WAVE's voice is always: **Professional · Clear · Human · Confident · Empowering.**

| Attribute | Do | Don't |
|---|---|---|
| Professional | "Enterprise-grade encryption protects your stream" | "Our super-amazing encryption is the best ever" |
| Clear | "Go live in seconds" | "Initiate broadcast instantiation" |
| Human | "We're here to help" | "Assistance is available upon request" |
| Confident | "WAVE handles millions of concurrent viewers" | "WAVE may be able to support large audiences" |
| Empowering | "You're in control of your stream" | "Users must configure their stream parameters" |

## Tone by context (variable)

| Context | Tone |
|---|---|
| Marketing | Inspiring, ambitious |
| Product UI | Helpful, efficient |
| Errors | Reassuring, solution-focused ([what happened]. [how to fix].) |
| Docs | Clear, instructive |
| Support | Empathetic, patient |
| Legal | Precise, formal |

## The human ⇄ agent taxonomy (WAVE-specific)

Every WAVE surface is dual-addressed — a human page and an agent endpoint at the same URL — so copy is
written for **two audiences with different needs**, never one at the expense of the other.

| | Human-facing (landing, footer, marketing, UI) | Agent-facing (llms.txt, skill.md, openapi, errors-as-JSON) |
|---|---|---|
| Goal | inspire, orient, build trust | enable a correct call with zero ambiguity |
| Voice | warm, plain-language, benefit-first | terse, imperative, literal, schema-first |
| Sentence | varied rhythm; short sentences punch | declarative; one fact per line |
| Jargon | avoid for general audiences | precise technical terms expected (scopes, x402, OpenAPI) |
| Example | "Turn any recording into shareable clips." | "POST /v1/clips {source,in,out} → {url,thumb}. Scope: clips:write." |
| Never | buzzwords, unsubstantiated claims, salesy urgency | prose padding, marketing adjectives, ambiguity |

Rule: a human sentence states the **benefit**; the agent line states the **contract**. If a surface
serves both (e.g. a landing page that also exposes `/llms.txt`), write each in its own register — don't
blend them into clever-but-vague copy.

## Core principles

1. **Clarity over cleverness** — "Start streaming in seconds", not "Dive into the stream of possibilities".
2. **Active voice** — "Settings saved", not "Your settings have been saved by the system".
3. **Respect time** — cut filler; every word earns its place.
4. **Be human** — write to a person, not a "user".
5. **Specificity** — "sub-16ms", "100M viewers", "same URL, same price" — not "fast", "scalable", "seamless".
6. **Empower, don't lecture.**

## Quick rules

- **Sentence case everywhere** (not Title Case).
- **WAVE is always all-caps** in prose. (The lowercase `wave` logotype + the gradient "the wave"
  wordmark are brand stylizations — logo treatment, not prose — and are allowed as marks only.)
- Contractions OK (except legal).
- Oxford comma required.
- **Max one exclamation per page** (ideally zero).
- Buttons: action verbs, 1–3 words, sentence case ("Get a key", "Talk to sales").
- Links: descriptive text — **never "click here"**.
- Errors: `[What happened]. [How to fix].` Never blame the user; never "Something went wrong."

## Terminology

| Use | Not |
|---|---|
| live stream | livestream |
| real-time | realtime |
| sign in | log in |
| allowlist / blocklist | whitelist / blacklist |
| primary / replica | master / slave |

## Forbidden patterns

- Salesy/pushy: "Don't miss out!", "LIMITED TIME!", urgency manipulation.
- Robotic: "The system has processed your request.", "Operation completed successfully."
- Condescending: "Simply…", "As you probably already know…", "easy steps".
- Vague: "Something went wrong.", "Click here", "powerful", "seamless", "next-gen", "revolutionary".
- Unsubstantiated claims: any number/superlative without a basis.

## Enforcement

- `copy-checker.sh` (PostToolUse, non-blocking) flags: "click here", whitelist/blacklist, title-case "Wave".
- `copy-reviewer` agent for prose review on marketing/landing surfaces.
- Severity: blaming errors = Critical; robotic voice = Major; jargon-for-general / salesy = Minor.

## Applying to a spoke

Run landing taglines, CTAs, footer copy, and page bodies through the human column; run `/llms.txt`,
`/skill.md`, `/openapi.json` descriptions, and JSON error messages through the agent column. The chassis
`shell()` + `nav.ts` strings are user-facing copy and MUST comply.
