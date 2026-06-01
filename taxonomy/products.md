# Product Taxonomy (priority-band convention)

The foundation does **not** own WAVE's product names (those are product-specific). What's
cross-project is the **priority-band scheme + category field** used to classify any product
portfolio.

## Priority bands

| Band | Meaning |
|------|---------|
| **P1** | Critical path — core revenue/usage; highest investment, strictest gates |
| **P2** | High value — significant adoption; standard gates |
| **P3** | Growth — emerging adoption; lighter process |
| **P4** | Emerging/experimental — incubating; minimal process |

## Category field

Each product carries a `category` (e.g., streaming, ai, infrastructure, analytics,
monetization). Categories mirror the agent/skill domain vocabulary so a product maps cleanly
to the agents/skills that serve it.

## Convention

- `priority` ∈ {P1, P2, P3, P4}; gate strictness scales with band.
- A product's `category` SHOULD match a domain in [agents.md](agents.md).
- Product specs live with the product; only this classification convention is shared.
