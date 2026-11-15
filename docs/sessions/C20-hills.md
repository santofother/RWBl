# C20 — Track pieces: uphill, downhill, crest/jump, banked turn
Agent: **Claude preferred** · Wave 4 · Branch: `c20-hills`
Model: Claude **Opus 5.5, medium** · or Codex **GPT-6.1 Sol, high**
Depends on: C19

Owns: `rwbl/game/track/**`, `rwbl/game/items/defs/piece_*.tres`, `rwbl/game/chariot/**` (slope handling only),
`rwbl/game/bots/**` (slope handling only), `tools/tests/track_piece_test.sh` (add cases)
Read: `DESIGN.md` §4, §5.6 · handoffs `C04`, `C06`, `C19` · `rwbl/game/track/track.gd` · chariot controller header

## Goal
Pieces with height and banking. Track math, the chariot controller and bots stop assuming flat ground.

## Steps
- Curve points get height (y) and tilt (`Curve3D` tilt for banking). Road/wall generator follows both.
- Controller: gravity component along the slope (uphill slows, downhill speeds up, braking weaker downhill;
  `# TUNE` in the chariot tuning resource), ground snap that follows the road normal; crest launches above a speed.
- Pieces: **uphill/downhill** (a pair: up then down so the loop closes at y=0, common), **crest/jump** (uncommon),
  **banked turn** (uncommon, holds speed through the bend).
- Bots: brake for crests, aim a bit inside on banked turns. Items placed on slopes sit on the road surface
  (`transform_at` returns the road normal).

## Tests
- Extend `track_piece_test.sh`: after a hill splice the curve still closes at y≈0; a chariot driving uphill loses
  speed vs flat; a fast chariot leaves the ground on a crest and lands; 3 bots finish a lap with every piece.
- Manual (user): `--free-build`, place each piece, drive it; tune slope numbers with F2.

## Finish
Handoff `docs/handoffs/C20.md`, land per AGENTS.md step 8.
