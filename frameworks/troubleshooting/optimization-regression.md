# Troubleshooting: Optimization Made Things Worse

## Symptoms

- Performance decreased after "optimization" changes
- Context usage increased after "trimming"
- Response quality degraded after "simplifying"
- Errors increased after "efficiency improvements"

## Root Cause

**Optimization was not A/B tested** - changes were assumed to be improvements without measurement.

## Recovery Steps

### Step 1: Locate the Original

Check for preserved versions:

```bash
# Look for .v1 or .original suffixes
find . -name "*.v1.*" -o -name "*.original.*" | head -20

# Check git history
git log --oneline --all -- path/to/file

# Look in ab-tests archive
ls -la .claude/docs/ab-tests/
```

### Step 2: Restore Original

```bash
# If .v1 exists
cp file.v1.md file.md

# If git history exists
git checkout HEAD~N -- path/to/file

# If no backup exists - this is why we A/B test!
# You'll need to reconstruct from git history or memory
git log -p -- path/to/file | head -200
```

### Step 3: Document the Failure

Create a post-mortem at `.claude/docs/ab-tests/`:

```markdown
# Failed Optimization: [Component]

## What Was Attempted

[Description of the "optimization"]

## What Went Wrong

[Metrics showing degradation]

## Why It Failed

[Root cause analysis]

## Learnings

- [What we learned]
- [What to avoid next time]

## Action Items

- [ ] Restore original
- [ ] Add this pattern to "don't try" list
- [ ] Update documentation
```

### Step 4: Prevent Recurrence

The A/B testing rule exists to prevent this:

1. **Always preserve originals**: `cp file.md file.v1.md` BEFORE changes
2. **Measure before/after**: Use identical test conditions
3. **Document comparison**: Save to `.claude/docs/ab-tests/`
4. **Decide on data**: Not assumptions

## Prevention Checklist

Before ANY optimization work:

- [ ] Created `.v1` backup of original
- [ ] Defined metrics to measure
- [ ] Documented baseline measurements
- [ ] Prepared test protocol
- [ ] Know where to save comparison results

## Related Resources

- Rule: `.claude/rules/00-core/ab-test-optimizations.md`
- Memory: `.claude/memories/workflow/ab-testing-optimizations.md`
- Template: `.claude/docs/AB-TEST-TEMPLATE.md`
- Cross-cutting: `.agents/optimization.md`

## Quick Reference

```
BEFORE optimization:
1. cp file.md file.v1.md
2. Measure baseline
3. Make changes
4. Measure after
5. Compare
6. Keep winner

AFTER bad optimization (no backup):
1. git log -p -- file | head -200
2. Reconstruct original
3. Document failure
4. Follow A/B process next time
```
