# Rome Wasn't Built in a Lap (RWBL) — rules for every coding agent

Read this whole file at the start of every session. Claude Code and Codex both read it, so it's the single
source of truth. `CLAUDE.md` only adds Claude-specific notes.

4–5 player Godot 4 party racer: players take turns placing traps on a shared track, then race Roman chariots
across it. LAN + Steam. Design: `DESIGN.md` (read only the sections your card names).

## Who's who
- **The user** owns the project and makes every final decision. They test builds and run playtests. They're
  new to Godot, so manual test steps in handoffs must say exactly what to click. They've pre-approved builders
  landing on `main` under the self-merge rules below.
- **Head engineer = Claude Code.** Owns `docs/ARCHITECTURE.md`, contracts, cards, triage and merge sessions.
- **Builders = any agent** (Claude or Codex, any model) running one card from `docs/sessions/`.
- **`DESIGN.md` is the user's.** Never change it unless the user asks in this session. If the design seems
  wrong or impossible, say so in your handoff under "Design question".

## How a session works (every agent, every time)
1. Read `AGENTS.md` and your card `docs/sessions/Cxx-*.md`. Read only the other files your card lists, plus the
   handoffs (`docs/handoffs/`) of the cards yours depends on. Don't explore the whole repo.
2. Work on your own branch `c<NN>-<short-name>` in a separate git worktree. In a fresh worktree run the import
   once (see Commands).
3. Touch only the files your card **owns**. Reading other files is fine. Need a change elsewhere? See
   "Cross-agent rules".
4. Add or extend a headless test for what you built whenever it can be tested without a screen.
5. Run `tools/run_tests.sh`. All tests must pass.
6. Write your handoff `docs/handoffs/Cxx.md` (template: `docs/handoffs/README.md`), max ~25 lines.
7. Commit on your branch.
8. **Land it on `main` yourself, without asking**, only if all of this holds:
   1. `git fetch origin && git merge origin/main` into your branch.
   2. Re-run `tools/run_tests.sh` on the merged result. All green.
   3. Update **only your own row** in `docs/STATUS.md`: `DONE`, date, branch. You may flip rows from `TODO` to
      `READY` when every card they depend on is now `DONE`. Don't touch other rows or the merge log.
   4. Commit, then `git push origin HEAD:main`. If rejected (someone pushed first), go back to 8.1. Also push
      your branch (`git push -u origin HEAD`).
   - **Stop instead of landing** if: the merge conflicts in a file you don't own, tests fail outside your files,
     or your handoff has a "Contract change requested". Push your branch, open a PR, set your row to
     `REVIEW (needs merge session: <one-line reason>)` on your branch, and stop.
   - No `origin` remote yet (before the user creates the GitHub repo)? Commit on your branch, set your row to
     `REVIEW (no remote yet)` and stop.
   - Never force-push, never push `main` with failing tests, never rewrite `main`'s history.

## Cross-agent rules
- Don't review, audit, refactor, restyle or rename code outside your card. It wastes tokens and causes conflicts.
- You **may** fix other code only when it blocks your card (crash, wrong contract, failing test in your path).
  Keep it minimal, tag it `# FIX(Cxx, <agent>): <why>`, list it in your handoff under "Touched outside my card".
- If a contract in `docs/ARCHITECTURE.md` is wrong or missing, don't change it. Do the smallest workaround and
  write the proposal under "Contract change requested". The head engineer decides.
- Never delete or rewrite another session's tests to make yours pass.

## Code comments (how agents talk to each other)
- **File header** (`##` doc comments at the top of every `.gd`): what it does, `Owner: Cxx`, its public API,
  which peer runs it.
- **`##` doc comment on every public func, signal and exported var.** Private helpers start with `_`.
- Tags (greppable, exactly these):
  - `# NET:` who runs this and who has authority (`# NET: host only`, `# NET: owner client, prediction`).
  - `# CONTRACT:` an invariant other modules rely on. Changing it needs the head engineer.
  - `# TUNE:` a gameplay number (prefer putting it in a tuning resource).
  - `# TODO(Cxx):` known gap, with the card that handles it.
  - `# FIX(Cxx, agent):` minimal fix in a file you don't own.
  - `# WHY:` a non-obvious decision.

## Token-saving rules
- Edit `.gd`, `.tscn`, `.tres`, `.cfg` as text. Don't open the Godot editor GUI.
- Verify with headless runs and logs, not screenshots. Screenshots only for visual cards, few and small.
- Read files in parts when you only need a section. Don't re-read files you just edited.
- No subagent fan-outs, no repo-wide audits. Batch independent commands.
- Stuck more than ~3 attempts on the same bug: stop, write what you tried in the handoff.
- Things that need a human (feel, fun, two machines, Steam): write a short click-by-click manual test in the
  handoff and stop.
- Gameplay numbers go in tuning resources, so the user can tune them in game instead of asking an agent.

## Layout
- `DESIGN.md`: game design (user owns).
- `rwbl/`: Godot 4.7 project (Forward+, Jolt Physics)
  - `core/`: reusable party layer copied from LastMage (`network_manager.gd`, `steam_manager.gd`,
    `debug_overlay.gd`, `graphics_settings.gd`, `voice_manager.gd` off by default). **`core/` never depends on
    `game/`.** It will become the shared `party_core` addon in wave 6, so keep it game-agnostic.
  - `game/`: this game's systems, one folder per system (map in `docs/ARCHITECTURE.md`).
  - `addons/godotsteam/`: GodotSteam 4.23.2 GDExtension (macOS paths use `*.universal.dylib`).
- `tools/`: `run_tests.sh` runs every `tools/tests/*.sh`; `tools/tests/lib.sh` has shared helpers.
- `docs/PLAN.md`: waves and agent split · `docs/STATUS.md`: board · `docs/ARCHITECTURE.md`: modules + contracts
- `docs/sessions/`: one card per session · `docs/handoffs/`: one note per finished session
- `docs/workflow/RUN_SESSIONS.md`: the user's guide (agents don't need it)
- `build/`: export output (gitignored)

## Commands
Godot binary: `$GODOT`, default `/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot`.
- Import (new worktree, and after adding files): `$GODOT --headless --path rwbl --import`
- All tests: `tools/run_tests.sh`
- Export: `$GODOT --headless --path rwbl --export-debug "Windows Desktop" ../build/windows/RWBL.exe`
  (and `"macOS" ../build/macos/RWBL.app`). macOS preset keeps `codesign/codesign=3` (see LastMage notes).
- CLI args (after `--`): `--host`, `--join=IP`, `--port=N`, `--name=X`, `--no-steam`, `--bots=N`,
  `--autotest=SEC`, `--quit-after=SEC`, `--lag-ms=N`, `--test-target=x,z`, `--voice` (voice is off by default)
  (cards add more; list them here when you do).
- Lobby: `--auto-ready`, `--lobby-autostart=N` (host auto-readies, starts once N humans are ready),
  `--discover`, `--discovery-port=N` (default `DEFAULT_PORT + 1`), `--no-fill-bots`, `--rounds=N`,
  `--phase-time=SEC` (test override for all phase durations).
- Standalone match (run `res://game/match/match.tscn` directly; tests and F6): `--bots=N`, `--no-human`,
  `--phase=draft|build|race|score`, `--rounds=N`, `--phase-time=SEC` (`--laps` is ignored since C23: one run
  from the start line to the finish line) (see `docs/ARCHITECTURE.md` §1).
- Match flow (C09, any scene with a match, read on the host): `--test-totals=slot:points,...` (added to the score
  totals: tests catch-up dealing and the win score), `--free-build` (Build ignores the draft hands).
- Build (C08, C17, C19, any scene with a match): `--test-place=item@progress,lateral,deg[,slot];...` (a track
  piece entry is `piece_hairpin@joint,side,0[,slot]`: joint k = between course pieces k-1 and k, side < 0 =
  flipped left; `demolish@uid[,slot]`),
  `--no-bot-build` (host: bots place nothing).
- Build view (C24, any scene with a match): `--test-cursor=<item_id>` (report a build cursor holding that card
  without a mouse; other peers log `[Build] CURSOR <slot> <item>`).
- Netcode (C07, any scene with `ChariotSync`): `--lag-ms=N` (simulated one-way delay on this peer's input /
  snapshot sends), `--loss=PCT` (simulated drop), `--no-predict` (own chariot interpolated like the others),
  `--net-autotest` (test driver for `chariot_net_test`). F3 also shows a net stats label top-right.

## Conventions
- **Authority (differs from LastMage!):** the host simulates chariots, items, combat and scoring. Clients send
  only inputs (`ChariotInput`) and render host snapshots with interpolation; the local chariot may be lightly
  predicted. Godot physics isn't deterministic: no lockstep, no rollback.
- Chariots use the custom controller (DESIGN §4), never a stock `RigidBody3D` for driving.
- Players and bots drive through the same `ChariotInput` path.
- Items are `ItemDef` resources with tags; interactions go through the tag table, not special cases.
- Log prefixes `[Net]`, `[Steam]`, `[Game]`, `[TEST]`, plus per-system (`[Race]`, `[Build]`, `[Draft]`,
  `[Score]`, `[Item]`, `[Bot]`). Tests grep these.
- GDScript: static types, `snake_case` files/funcs, `PascalCase` classes/nodes, tabs. One system per folder.
- Tests never hard-code a port: `PORT="${PORT:-$(( 20000 + RANDOM % 20000 ))}"` (or the `lib.sh` helper).
