# Label & Severity Taxonomy

One consistent label set across repos. The machine-readable source is
[`.github/labels.yml`](../.github/labels.yml) (sync with a labeler/label-sync action).

## Namespaced labels

`namespace:value` form, grounded in the harvested labeler config:

| Namespace | Examples |
|-----------|----------|
| `app:` | `app:frontend`, `app:api`, `app:streaming`, `app:analytics` |
| `infra:` | `infra:ci-cd`, `infra:docker`, `infra:cloudflare`, `infra:actions` |
| `database:` | `database:migrations`, `database:schema`, `database:functions` |
| `service:` | `service:stripe`, `service:sentry`, `service:supabase`, `service:inngest` |
| `ai:` | `ai:claude`, `ai:embeddings` |
| `testing:` | `testing:unit`, `testing:e2e`, `testing:integration` |
| `config:` | `config:*` |
| `feature:` | `feature:*` |

Standalone: `security` (+ `security:rls`), `documentation`, `dependencies`, `breaking-change`.

## Size bands (mirror the file-size law)

`size:xs` (<10), `size:s` (<50), `size:m` (<250), `size:l` (<1000), `size:xl` (≥1000) lines.

## Severity

- **Review findings:** `Critical`, `Major`, `Minor` (used by the bot-review-gate classifier).
- **Triage:** `P0` (blocker), `P1` (serious), `P2`, `P3`.
- **CI blast radius:** blocks-merge / non-blocking / cosmetic.

## Convention

- Label form: `^[a-z]+(:[a-z-]+)?$`, namespace ∈ the approved set above.
- Add labels in `.github/labels.yml` (one source); a label-sync action applies them per repo.
