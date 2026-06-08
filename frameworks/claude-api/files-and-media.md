# Files & Media

How to feed Claude **files, images, PDFs, citations, and search-results**, and where embeddings fit. Default model is `claude-opus-4-8`. All Claude traffic routes through the [model-routing Leveragizer](../model-routing/README.md) — never hardcode a model, never call Anthropic direct without going through the gateway tier first.

This is the substrate for the **media spokes** (clips/transcribe): upload-once, reference-many, cache the document, cite the source.

## The five content paths

| Path | Block type | Source kinds | Beta header | Cache it? |
|------|-----------|--------------|-------------|-----------|
| Files API | `image` / `document` / `container_upload` | `file` (`file_id`) | `files-api-2025-04-14` | yes (on the referencing block) |
| Vision | `image` | `base64`, `url`, `file` | none | yes |
| PDF | `document` | `base64`, `url`, `file` | none (Files needs header) | yes — strongly |
| Citations | `document` / `search_result` | text/pdf/content/`file` | none | yes (source, not the cites) |
| Search results | `search_result` | inline `content[]` | none | yes |

Embeddings are **not** an Anthropic API call — see [Embeddings](#embeddings) (Voyage AI).

## Files API — upload once, reference many

Create-once, use-many. Avoids re-uploading documents/images on every turn. Beta header **required**: `anthropic-beta: files-api-2025-04-14`.

- **Max file size: 500 MB.** Total storage 500 GB/org.
- Free: upload/download/list/metadata/delete. You only pay input tokens when the file is used in a Messages request.
- Files persist until deleted; scoped to the **workspace** of the API key (any key in the same workspace can use them).
- **You can only download files created by Skills or the code execution tool** — your own uploads are not downloadable.
- **NOT ZDR-eligible.** Standard retention applies. (PDF/Citations/Search-results/Caching *are* ZDR-eligible — Files is the odd one out.)
- Not on Bedrock or Vertex (is on Claude API, AWS Claude Platform, Microsoft Foundry).

```python
# Upload once (free), then reference by file_id across many requests.
up = client.beta.files.upload(
    file=("episode.pdf", open("episode.pdf", "rb"), "application/pdf"),
)  # -> up.id == "file_011C..."

msg = client.beta.messages.create(
    model="claude-opus-4-8",
    max_tokens=1024,
    betas=["files-api-2025-04-14"],
    messages=[{"role": "user", "content": [
        {"type": "document", "source": {"type": "file", "file_id": up.id}},
        {"type": "text", "text": "Summarize this transcript."},
    ]}],
)
```

```bash
curl -X POST https://api.anthropic.com/v1/files \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: files-api-2025-04-14" \
  -F "file=@episode.pdf"   # -> { "id": "file_011C...", "downloadable": false }
```

| File type | MIME | Block |
|-----------|------|-------|
| PDF | `application/pdf` | `document` |
| Plain text | `text/plain` | `document` |
| Images | `image/jpeg|png|gif|webp` | `image` |
| Datasets / other (code exec) | varies | `container_upload` |

`.csv`/`.xlsx`/`.docx`/`.md`/`.txt` are NOT document blocks — convert to plain text and inline. For `.docx` with images, convert to PDF first to keep visual parsing + citations.

## Vision — images

Three source kinds: `base64`, `url`, `file` (Files API). On Bedrock/Vertex only `base64`.

- **Tokens ≈ `width * height / 750`.**
- **Hi-res on Opus 4.7+ (and `claude-opus-4-8`):** native cap rises to **2576 px** long edge / **~4784 tokens** (vs 1568 px / 1568 tokens on older models). Automatic, no beta header. Costs **up to ~3x** the image tokens — **downsample if you don't need the fidelity.** Sonnet/Haiku stay at 1568.
- Limits: ≤100 images/request (200k-context models) or ≤600 (others); ≤5 MB/image (API); ≤8000×8000 px (≤2000×2000 if >20 images). 32 MB request cap is usually hit first → prefer Files API for many/large images.
- Put images **before** text. Formats: JPEG/PNG/GIF/WebP (first frame only). No people-ID, no image generation.

```python
{"type": "image", "source": {"type": "file", "file_id": up.id}}        # Files (best for multi-turn)
{"type": "image", "source": {"type": "url",  "url": "https://..."}}     # URL
{"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": b64}}
```

In multi-turn/agentic loops, base64 images are resent in full **every turn** → upload to Files and reference by `file_id` to keep payloads small.

## PDF support

Each page is rendered as **text + image** (full visual understanding — charts, tables, layouts). **ZDR-eligible.** All active models. Three sources: `url`, `base64`, `file_id`.

- Limits: **32 MB** request / **600 pages** (100 on 200k-context models). Both apply to the whole payload.
- Cost: ~1,500–3,000 text tokens/page **plus** per-page image tokens (vision math above). Use [token counting](https://platform.claude.com/) to estimate.
- Dense PDFs can exhaust the context window before the page limit — split into sections, downsample embedded images.
- **Place PDF before text. Cache it.** (See below.)
- On **Bedrock Converse API**, visual PDF understanding requires **citations enabled** — without it you get text-extraction-only fallback. (Not a limit on the native Claude API.)

```python
{"type": "document",
 "source": {"type": "file", "file_id": pdf_id},        # or base64 / url
 "cache_control": {"type": "ephemeral"}}                # cache for repeated analysis
```

## Citations

Verifiable, source-grounded claims. `cited_text` does **not** count toward output tokens (nor input tokens on later turns). All active models except Haiku 3. **ZDR-eligible.**

- Set `"citations": {"enabled": true}` on each document. **All-or-none** within a request — mixing on/off is a 400.
- Chunking & citation format by source type:

| Source | Chunking | Citation type | Index |
|--------|----------|---------------|-------|
| Plain text | sentence | `char_location` | char (0-idx, excl. end) |
| PDF | sentence | `page_location` | page (1-idx, excl. end) |
| Custom content | none (your blocks) | `content_block_location` | block (0-idx, excl. end) |

- Image citations are NOT supported — scanned PDFs without extractable text aren't citable.
- **INCOMPATIBLE with Structured Outputs** — citations + `output_config.format` (or deprecated `output_format`) → 400. Citations interleave cite blocks with text, which breaks strict JSON.
- Use **custom content** documents when you want to control granularity (transcripts, bullets, RAG chunks).

### Caching × Citations (load-bearing)

Citation blocks in the response **cannot be cached**, but the **source document can**. Put `cache_control` on the top-level document block; enable citations on the same block. Subsequent requests reuse the cached document and still emit fresh citations.

```python
{"type": "document",
 "source": {"type": "text", "media_type": "text/plain", "data": long_doc},
 "citations": {"enabled": True},
 "cache_control": {"type": "ephemeral"}}   # cache source; cites generated each call
```

## Search-results — RAG citations

`search_result` content blocks give web-search-quality citations to **your** content (custom RAG). Available on `claude-opus-4-8`, Opus 4.7/4.6/4.5/4.1, Sonnet 4.6/4.5, Haiku 4.5, etc.

Two delivery modes: **(1) returned from your tool** (dynamic RAG) or **(2) top-level user-message content** (pre-fetched/cached).

```json
{"type": "search_result",
 "source": "https://docs.example.com/guide",   // required
 "title": "User Guide",                         // required
 "content": [{"type": "text", "text": "..."}],  // required, ≥1 text block
 "citations": {"enabled": true},                // default OFF; all-or-none
 "cache_control": {"type": "ephemeral"}}         // optional
```

- Citations **default OFF**; if enabled it's **all-or-none** across all search results (else error). Returns `search_result_location` (source/title/`search_result_index`/`start_block_index`/`end_block_index`).
- **The text block is the minimal citable unit** — Claude cites whole blocks, not substrings. Split content into smaller blocks for finer citation boundaries.
- Text only (no images). Available on Claude API, Bedrock, Vertex.

## Embeddings

**Anthropic ships no embedding model.** Recommended vendor: **Voyage AI** (`voyage-4`/`-4-large`/`-4-lite`/`-4-nano`, 32k context, dims 256/512/1024/2048; multimodal `voyage-multimodal-3.5`; domain models `voyage-code-3`/`-finance-2`/`-law-2`). Normalized to length 1 → cosine == dot-product. Use `input_type="query"|"document"` for retrieval.

**WAVE routing:** treat embeddings as a routed inference call — **tier 1 local (Mac Studio) is the default for embeddings** per the Leveragizer; Voyage is a tier-4 direct-vendor fallback for quality/domain-specific retrieval. Never hardcode the embedder in spoke code; read it from routing config.

## WAVE patterns — media spokes (clips / transcribe)

- **Ingest → `file_id`.** On media upload to a spoke, push the artifact (transcript PDF, source image, thumbnail) to the Files API **once**; persist `file_id` alongside the asset row. Every downstream Claude call references `file_id` — no re-upload, smaller payloads, lower latency.
- **Cache the document.** Long transcripts / source PDFs get `cache_control: ephemeral` on the document block. Min cacheable prefix `claude-opus-4-8` = **1024 tokens** (live doc; the older cached pricing table said 4096 — opus-4-8/sonnet-4-6 = 1024, haiku-4-5 = 4096). Verify hits via `usage.cache_read_input_tokens`. Cache reads 0.1x; 5m write 1.25x, 1h write 2x.
- **Citations for transcribe.** Enable citations on the transcript document so summaries/answers carry verifiable `page`/`char` pointers back to the source — surface these as deep-links in the spoke UI.
- **Search-results for clip RAG.** When a spoke retrieves candidate clips, return them as `search_result` blocks (one text block per clip segment for tight citation boundaries) so highlight rationales cite the exact segment.
- **Hi-res cost control.** Clip thumbnails/screenshots on `claude-opus-4-8` get hi-res automatically (~3x tokens). Downsample to ≤1568 px in the spoke before upload unless the task needs 2576 px fidelity (OCR, dense charts).
- **Batch the bulk.** High-volume PDF/transcript analysis → Batch API (50% off). But **Batch is NOT ZDR-eligible** and Files is NOT ZDR-eligible — route any ZDR-required tenant through the inline base64/PDF path (PDF/citations/caching are ZDR-OK) and skip Files+Batch.
- **Stream long outputs.** When `max_tokens > 16000` (long summaries over big media), stream — handle `citations_delta` events to attach cites to the current text block.

## Anti-patterns

- ❌ Re-sending base64 images/PDFs every turn in a multi-turn loop — upload to Files, reference `file_id`.
- ❌ Hardcoding a model string in media-spoke code — route via the Leveragizer.
- ❌ Calling Anthropic direct (skipping the gateway tier) for media calls — loses billing aggregation/observability/retry.
- ❌ Citations + Structured Outputs in the same request — 400. Pick one.
- ❌ Mixing `citations.enabled` true/false across documents or search-results in one request — error.
- ❌ Putting all RAG content in one big text block — kills citation granularity; split into blocks.
- ❌ Routing a ZDR-required tenant through Files API or Batch (neither is ZDR-eligible).
- ❌ Sending hi-res Opus screenshots without downsampling when fidelity isn't needed — ~3x image-token bill.
- ❌ Trying to download your own uploaded files — only Skills/code-exec outputs are downloadable.

## Env vars

| Var | Purpose |
|-----|---------|
| `ANTHROPIC_API_KEY` | tier-4 direct fallback only (Files/Vision/PDF/Citations/Search) |
| `VERCEL_AI_GATEWAY_API_KEY` | tier-2 gateway (default path for Claude calls) |
| `VOYAGE_API_KEY` | Voyage embeddings (tier-4 vendor fallback) |
| `OLLAMA_API_KEY` | tier-1 local embeddings/inference (Mac Studio) |

Beta header (Files API only): `anthropic-beta: files-api-2025-04-14`.

## Related

- [`model-routing/README.md`](../model-routing/README.md) — the multi-tier Leveragizer all of these calls route through
- [`prompt-caching.md`](./prompt-caching.md) — breakpoints, min-prefix nuance, `cache_read_input_tokens`
- [`batch.md`](./batch.md) — 50%-off bulk media processing + the not-ZDR gate
- [`request-surface.md`](./request-surface.md) — `output_config.format`, streaming, `max_tokens` thresholds

---

Sources: build-with-claude/{files, vision, pdf-support, citations, search-results, embeddings}.md
