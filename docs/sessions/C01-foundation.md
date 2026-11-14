# C01 — Foundation: project, LastMage net core, cube sync (N1)
Agent: **Claude only** (head engineer) · Wave 0 · Branch: `main`
Model: Claude **Opus 5.5, medium**
Depends on: — · Run in the main `CustomChariot` folder, **no worktree** (there's no git repo yet)

Owns: everything (first session). Source to copy from (read-only): `/Users/santofothergill/PersonalProjects/LastMage`
Read: `DESIGN.md` §1, §8 · LastMage `AGENTS.md` §Layout/§Commands · LastMage `the-last-fire-mage/core/*.gd`
(headers + public API first, full files only when copying) · LastMage `tools/run_tests.sh`, `tools/tests/lib.sh`,
`tools/tests/net_test.sh`, `.gitignore`, `docs/STEAM_EXPORT_AND_TESTING.md`

## Goal
A Godot 4.7 project where 2+ instances connect over LAN (and Steam, untested here) and see each other's cube
move, built from LastMage's proven net core instead of from scratch.

## Steps
- `git init` in `CustomChariot`, `.gitignore` adapted from LastMage (`build/`, `.godot/`, unused GodotSteam platforms).
- Create `rwbl/project.godot`: Godot 4.7, Forward+, Jolt Physics, app name "RWBL".
- Copy into `rwbl/core/`: `network_manager.gd`, `steam_manager.gd`, `debug_overlay.gd`,
  `graphics_settings.gd`, `voice_manager.gd`. Strip anything that references LastMage `game/` code
  (`core/` must not depend on `game/`). Voice stays registered but **disabled by default** (setting off).
  Set `MAX_PLAYERS` to 5 and a different `DEFAULT_PORT` from LastMage so both games can run at once.
- Copy `addons/godotsteam/` (keep the `*.universal.dylib` path fix) and the export plugin that writes
  `steam_appid.txt` (app 480), renamed for this project. Copy `export_presets.cfg` with names changed.
- Copy `tools/run_tests.sh`, `tools/tests/lib.sh`, and adapt `net_test.sh`: host + 2 clients, cube position sync.
- Minimal `game/sandbox/` scene: main menu (Host / Join IP / Steam Host / Steam Join), a flat plane, one cube per
  player moved with WASD. Cube sync can be the LastMage pattern for now; C02 replaces it with the
  host-authoritative design.
- Copy `docs/STEAM_EXPORT_AND_TESTING.md`, adjusted for this project's names and paths.
- Create `docs/handoffs/README.md` (copy LastMage's template, `Sxx` → `Cxx`, add a "Design question" section).
- Commit on `main`.

## Tests
`tools/run_tests.sh` → `NET TEST PASSED`.
Manual for the user (write click-by-click in the handoff): open the project in Godot, Debug → Customize Run
Instances → 2, F5, host in one window, join `127.0.0.1` in the other, move the cube.

## Finish
Write `docs/handoffs/C01.md`, set C01 `DONE` and C02 `READY` in `STATUS.md`, commit. No remote exists yet:
tell the user to create the GitHub repo (`RUN_SESSIONS.md` §Setup) before wave 1.
