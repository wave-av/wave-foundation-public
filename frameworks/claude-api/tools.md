# Tool Use

The full tool-use family for the Claude API. Tool access is the highest-leverage agent primitive (outsized gains on SWE-bench / LAB-Bench). The model never executes anything — it emits a structured `tool_use` request; your code (client tools) or Anthropic's servers (server tools) run it and the result flows back.

> **WAVE rule:** Tool-heavy chains route through the [model-routing Leveragizer](../model-routing/README.md). Never hardcode `claude-opus-4-8` in a call site; never bypass the gateway to hit Anthropic direct. Side-effecting tools (anything that writes, sends, pays, or deletes) MUST pass a security gate before execution.

## Where tools run (the only axis that matters)

| Bucket | Tools | Execution | You build |
|--------|-------|-----------|-----------|
| User-defined (client) | your `name`/`input_schema` | your app | schema + handler + the loop |
| Anthropic-schema (client) | `bash`, `text_editor`, `computer`, `memory` | your app | handler + the loop (schema is trained-in) |
| Server | `web_search`, `web_fetch`, `code_execution`, `tool_search` | Anthropic | enable + read final answer |

Anthropic-schema tools call **trained-in** signatures — Claude calls them more reliably than an equivalent custom tool. Prefer them for standard dev ops.

## Define tools + `tool_choice`

A tool definition: `name` (`^[a-zA-Z0-9_-]{1,64}$`), `description` (extremely detailed — the single biggest performance lever; 3-4+ sentences), `input_schema` (JSON Schema). Optional: `input_examples`, `cache_control`, `strict`, `defer_loading`, `allowed_callers`, `eager_input_streaming`.

```python
client.messages.create(
    model=route("Expert"),  # never literal "claude-opus-4-8" in app code
    max_tokens=1024,
    tools=[{
        "name": "github_list_prs",          # namespace by service
        "description": "List open PRs for a repo. Returns slug + number + title. "
                       "Use when the user asks what PRs exist; does NOT return diffs.",
        "input_schema": {"type": "object",
            "properties": {"repo": {"type": "string", "description": "owner/name"}},
            "required": ["repo"]},
    }],
    tool_choice={"type": "auto"},
    messages=[{"role": "user", "content": "What PRs are open on wave-online/foundation?"}],
)
```

`tool_choice`: `auto` (default w/ tools) · `any` (must use one) · `tool` (force one) · `none` (default w/o tools). `any`/`tool` prefill the assistant turn → no preamble text. **Extended thinking only supports `auto` and `none`** — `any`/`tool` error. Design rules: consolidate related ops into one tool with an `action` param; namespace names; return high-signal stable IDs only.

```bash
curl https://$WAVE_GATEWAY/v1/messages -H "content-type: application/json" \
  -d '{"model":"claude-opus-4-8","max_tokens":1024,
       "tools":[{"name":"get_weather","description":"...","input_schema":{...}}],
       "tool_choice":{"type":"auto"}}'
```

## Tool-runner vs manual loop

The agentic loop is `while stop_reason == "tool_use": execute, append tool_results (single user message), resend`. Two ways to drive it:

| | Tool Runner (SDK, beta) | Manual loop |
|--|--------------------------|-------------|
| Loop, error-wrap, type-safety | automatic | you write it |
| Use when | most cases; fast path | **human-in-the-loop approval, security gating, custom logging, conditional exec** |
| Define tools | `@beta_tool` / `betaZodTool` / `BaseTool` | raw `tools` array |

```python
runner = client.beta.messages.tool_runner(
    model="claude-opus-4-8", max_tokens=1024,
    tools=[get_weather, calculate_sum],
    messages=[{"role": "user", "content": "Weather in Paris? And 15+27?"}],
)
final = runner.until_done()   # or `for message in runner:` to gate each turn
```

Runner extras: `max_iterations` (bound the loop, all 7 SDKs); take-over-message-history (retry/inject — modifying messages skips the auto-append); `generate_tool_call_response()` to intercept errors (`is_error`) before Claude sees them; mutate tool results to add `cache_control`; `ANTHROPIC_LOG=info|debug` for stack traces; built-in [client-side compaction](../../frameworks/claude-api/context-management.md) for long runs.

> **WAVE:** any tool with side effects → use the **manual loop or runner intercept** to insert the security gate between `tool_use` and execution. The Runner's full-auto `until_done()` is for read-only/internal tools only.

## Parallel tool use

On by default for Claude 4 models. Calls in one assistant turn are **unordered** — run them concurrently (`asyncio.gather`/`Promise.all`). **All tool_results for a turn go in ONE user message** — splitting them across messages teaches Claude to stop parallelizing.

```text
✅ [{role:assistant, content:[tool_use_1, tool_use_2]}, {role:user, content:[result_1, result_2]}]
❌ ...two separate user messages    # kills parallelism
```

Disable: `disable_parallel_tool_use=true` (≤1 tool on `auto`; exactly 1 on `any`/`tool`). If batched calls turn out dependent, return `is_error:true` with the natural error — Claude reissues. Boost with system prompt: *"whenever you perform multiple independent operations, invoke all relevant tools simultaneously."* Verify: avg tools per tool-calling message > 1.0.

## Fine-grained tool streaming

`eager_input_streaming:true` per user-defined tool + `stream:true` → tool-input JSON streams without server-side buffering/validation (lower latency for big params). **ZDR-eligible. All models/platforms.** Risk: you may get **invalid/partial JSON**, especially if `max_tokens` hits mid-param — write handling. Accumulate `input_json_delta.partial_json` fragments; parse on `content_block_stop`. Wrap bad JSON as `{"INVALID_JSON":"..."}` when returning it.

## Strict tool use

`strict:true` → grammar-constrained sampling guarantees inputs match the schema (typed args, no retries). Requires `additionalProperties:false`. Combine with `tool_choice:{"type":"any"}` to guarantee a call AND valid shape. Schemas cached ≤24h; **HIPAA: no PHI in schema** (property names, enums, const, pattern). **Not compatible with programmatic tool calling.**

## Programmatic tool calling (PTC)

Claude writes Python in a code-execution container that calls your tools as `await` functions — N round-trips collapse to 1, intermediate results never enter context (token + latency win; key unlock on BrowseComp/DeepSearchQA). Requires `code_execution_20260120`; **Opus 4.8/4.7/4.6, Sonnet 4.6, Opus 4.5, Sonnet 4.5**. Mark tools `allowed_callers:["code_execution_20260120"]`; response `tool_use` blocks carry `caller`. **NOT ZDR-eligible.** Not with `strict`, forced `tool_choice`, `disable_parallel_tool_use`, or MCP-connector tools. When responding to a pending PTC call, the user message must contain **only** `tool_result` blocks. Validate tool outputs — they are strings that run in the container (injection risk).

```python
tools=[{"type":"code_execution_20260120","name":"code_execution"},
       {"name":"query_database","description":"Runs SQL; returns JSON rows.",
        "input_schema":{...}, "allowed_callers":["code_execution_20260120"]}]
```

## Tool search

For hundreds/thousands of tools: include `tool_search_tool_regex_20251119` (regex) or `tool_search_tool_bm25_20251119` (NL), mark the rest `defer_loading:true`. Claude searches names/descriptions/args, the API returns 3-5 `tool_reference` blocks, auto-expanded. Cuts definition tokens ~85% and keeps selection accuracy high past the 30-50-tool degradation cliff. **ZDR-eligible.** `defer_loading` preserves the prompt-cache prefix (discovered tools append inline) and is independent of strict-grammar construction. (Bedrock: InvokeModel API only, not Converse.)

## Advisor tool (beta `advisor-tool-2026-03-01`)

Pair a fast **executor** with a higher-intelligence **advisor** that gives mid-generation strategy (~400-700 text tokens). Advisor must be ≥ executor. Maps cleanly onto the Leveragizer: run executor at a cheaper tier, consult `claude-opus-4-8` as advisor.

| Executor | Valid advisor |
|----------|---------------|
| haiku-4-5 / sonnet-4-6 / opus-4-6 / opus-4-7 | opus-4-8, opus-4-7 |
| opus-4-8 | opus-4-8 |

```json
{"type":"advisor_20260301","name":"advisor","model":"claude-opus-4-8"}
```
Not on Bedrock/Vertex/Foundry. ZDR-eligible.

## Server tools — code execution / web search / web fetch

Anthropic runs an internal loop. Latest version strings (pin them):

| Tool | Latest type string | Notes |
|------|-------------------|-------|
| code_execution | `code_execution_20260120` | sandboxed Python; powers PTC; containers idle-out 4.5m, 30-day max |
| web_search | `web_search_20260209` | `max_uses`, `allowed_domains`/`blocked_domains` (mutually exclusive), `user_location` |
| web_fetch | `web_fetch_20260209` | cite-then-fetch: search → pick → fetch only the relevant URLs |
| tool_search | `tool_search_tool_bm25_20251119` / `_regex_20251119` | see above |

`server_tool_use` blocks show what ran (execution already done). **Side-effect note:** web_fetch can pull attacker-controlled content — treat fetched text as untrusted input to any downstream side-effecting tool.

## Anthropic-schema client tools — bash / text-editor / computer / memory

You execute these; sandbox + allowlist them. Latest version strings:

| Tool | Latest type string | Sandbox guidance |
|------|-------------------|------------------|
| bash | `bash_20250124` | command allowlist; constrained cwd; per [sandbox-execution rule](../../rules/sandbox-execution.md) |
| text_editor | `text_editor_20250728` (name `str_replace_based_edit_tool`) | restrict to a working dir |
| computer | `computer_20251124` (or `_20250124`) | full desktop = broadest blast radius; screenshot-per-action = slow; prefer narrower tools |
| memory | `memory_20250818` | client-side; restrict ALL ops to `/memories`; Claude checks it before tasks |

Memory is orthogonal — bolt it onto any toolset for cross-session state. Computer use subsumes most tools but is the slowest and highest-risk; gate it hard.

## Tool combinations (canonical patterns)

- **Research:** `web_search` + `code_execution` — search then compute over results.
- **Coding agent:** `text_editor` + `bash` — inspect, edit, test, repeat (both client; allowlist on untrusted code).
- **Cite-then-fetch:** `web_search` + `web_fetch` — fetch only relevant URLs.
- **Long-running:** `memory` + any toolset — persist state across sessions.
- **All-in-one:** `computer` — arbitrary GUI when nothing narrower fits.

## Tool use + prompt caching

Cache prefix is `tools → system → messages`; a change at one level invalidates it and everything after. Put `cache_control:{"type":"ephemeral"}` on the **last** tool to cache the whole tool-definitions prefix (≤4 breakpoints). Min cacheable prefix on opus-4-8 = **1024** (live-doc authoritative; older cached table said 4096 — flag), sonnet-4-6 = 1024, haiku-4-5 = 4096. Reads 0.1x; 5m write 1.25x; 1h write 2x. Verify with `usage.cache_read_input_tokens`. **Prompt caching IS ZDR-eligible.**

| Change | Invalidates |
|--------|-------------|
| tool definitions | entire cache |
| toggle web search / citations | system + messages |
| `tool_choice` / `disable_parallel_tool_use` / thinking params / images toggle | messages |

`defer_loading` (tool search) keeps the prefix cache intact when tools load mid-conversation.

## Handling stop reasons

The loop is keyed on `stop_reason`:

| stop_reason | Meaning | Action |
|-------------|---------|--------|
| `tool_use` | Claude wants ≥1 client tool | execute, return `tool_result`(s) in one user msg, resend |
| `pause_turn` | server-tool internal loop hit its iteration cap (web_search/code_exec) | **resend the conversation including the paused response** to continue |
| `end_turn` | final answer | exit loop |
| `max_tokens` | truncated | raise budget + retry (Runner can auto-retry the turn) |
| `stop_sequence` / `refusal` | stopped for another reason | handle in app |

Tool errors: return `{"type":"tool_result","tool_use_id":...,"is_error":true,"content":"<natural error>"}` — Claude recovers. Error: "tool_use ids without tool_result blocks" → every `tool_use` needs a matching `tool_result` immediately after.

## Anti-patterns

- ❌ Literal model string in app code → route via the Leveragizer's named profiles (`Fast/Expert/Heavy/Code`).
- ❌ Direct Anthropic call for tool chains, bypassing the gateway (loses billing/obs/retry).
- ❌ Auto-running a side-effecting tool with `until_done()` and no gate.
- ❌ Splitting parallel `tool_result`s across user messages (kills parallelism).
- ❌ Parsing free-form model text with regex to recover a decision → that decision should be a tool call.
- ❌ `strict:true` with PTC, or PHI in a strict schema.
- ❌ Treating fetched/searched/tool-returned strings as trusted before a side-effecting step.
- ❌ Ignoring `pause_turn` (drops server-tool work mid-flight).
- ❌ `disable_parallel_tool_use` as a workaround for "dependent" batched calls — return `is_error` instead.

## Env vars

| Var | Purpose |
|-----|---------|
| `WAVE_GATEWAY` / `VERCEL_AI_GATEWAY_API_KEY` | tier 2; default path for all tool chains |
| `ANTHROPIC_API_KEY` | tier-4 direct fallback only |
| `OLLAMA_API_KEY` | tier-1 local (tool-incapable models bypass per eval gate) |
| `ANTHROPIC_LOG` | `info`/`debug` — Tool Runner stack traces |

## Sources

snapshot `agents-and-tools/tool-use/`: overview.md, define-tools.md, how-tool-use-works.md, handle-tool-calls.md, parallel-tool-use.md, fine-grained-tool-streaming.md, strict-tool-use.md, programmatic-tool-calling.md, tool-runner.md, tool-search-tool.md, advisor-tool.md, tool-combinations.md, tool-use-with-prompt-caching.md, bash-tool.md, text-editor-tool.md, computer-use-tool.md, memory-tool.md, web-search-tool.md, web-fetch-tool.md, code-execution-tool.md
