# Taxonomies

The canonical classification systems used across WAVE projects. Harvested from
an internal WAVE repo (grounded in real category distributions, not invented) and made
product-agnostic. These are the shared vocabularies that keep skills, agents, products,
labels, and docs consistent across repos.

| Taxonomy | File | Validated by |
|----------|------|--------------|
| Skill categories | [skills.md](skills.md) | `scripts/validate-skills.py` (prefix advisory) |
| Agent classification | [agents.md](agents.md) | frontmatter `category` + `model` |
| Product priority bands | [products.md](products.md) | doc convention |
| Labels & severity | [labels.md](labels.md) | `.github/labels.yml` |
| Audiences | [audiences.md](audiences.md) | doc convention |

**Principle:** a new skill/agent/label that doesn't fit an existing category is a signal —
either it belongs in one, or the taxonomy needs a reviewed addition. Don't invent ad-hoc
categories; extend the taxonomy here first (Discovery → Taxonomy → Validator → Gate).
