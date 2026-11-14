# Session cards

One card = one session = one branch. A builder reads `AGENTS.md` + its card + the handoffs its card depends on.

Card header fields:
- **Agent**: Either · Lean Claude · Lean Codex · Claude only · ChatGPT only (see `docs/PLAN.md` §2)
- **Tier**: T1 hard … T4 chores (model + effort table in `docs/PLAN.md` §2)
- **Owns**: the only files/folders this card may create or edit (plus its own handoff and tests)
- **Read**: the only other files to open. Section names (e.g. `DESIGN.md §4`) mean "read just that part".

Card body: Goal · Steps · Tests (headless + click-by-click manual test for the user if needed) · Finish.

After C02, folder ownership is fixed in `docs/ARCHITECTURE.md`. If a card disagrees with it, ARCHITECTURE.md wins.
