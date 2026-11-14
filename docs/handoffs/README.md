# Handoffs

Each finished session writes `Cxx.md` here (max ~25 lines). The next sessions read only the handoffs of the
cards they depend on, so put everything they need here and nothing else.

## Template

```markdown
# Cxx — <title>
Agent: <Claude Opus 5.5 / Codex top model / ...> · effort <low/medium/high> · branch `cNN-name`
Result: DONE | PARTIAL (what's missing) | BLOCKED (why)

## What exists now
- <files/scenes added, one line each>

## Public API (what other cards can use)
- `ClassName.func(args) -> type`: <one line>
- signal `name(args)`: <when it fires, on which peer>

## How to test
- Headless: `<command>` → expect `<log line>`
- Manual (needs the user): <steps, only if needed>

## Touched outside my card
- <file>: <minimal fix, tagged FIX(Cxx, agent)> (or "none")

## Contract change requested
- <proposal> (or "none")

## Design question
- <where DESIGN.md seems wrong or impossible, for the user> (or "none")

## Known issues / next steps
- <short list>
```
