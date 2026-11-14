# C03 — Lobby: LAN discovery, Steam lobby, 5 slots, ready-up, match start (N2, N3)
Agent: **Either** (suggested Codex) · Tier: **T2** · Wave 1 · Branch: `c03-lobby`
Depends on: C02

Owns: `rwbl/game/lobby/**`, `tools/tests/lobby_test.sh`, `rwbl/project.godot` (**`run/main_scene` line only**),
`rwbl/core/steam_manager.gd` (only if Steam friend-invite joining needs a callback; keep it game-agnostic)
Read: `DESIGN.md` §8 · `docs/ARCHITECTURE.md` §1, §2 · handoffs `C01`, `C02` · `rwbl/core/network_manager.gd`,
`rwbl/core/steam_manager.gd` (headers + public funcs) · `rwbl/game/sandbox/sandbox.gd` (menu pattern to copy) ·
headers of `rwbl/game/common/player_info.gd`, `game_mode.gd`, `rwbl/game/match/match.gd`

## Goal
Up to 5 players find each other on LAN or Steam, sit in slots, ready up, and the host starts a match that
loads on every peer. When the match ends, everyone is back in the lobby.

## Steps
- `lobby/main.tscn` (root `Main`, child `Game` Node) becomes the main scene. Menu: name field, Host (LAN),
  Join IP, **LAN games list** (auto-found), Steam Host, Steam Join (lobby list), Invite (Steam), Quit.
- `lobby/lan_discovery.gd`: host broadcasts a small UDP packet every 1 s on `DEFAULT_PORT + 1`
  (`{"game":"rwbl","name","port","players"}`); clients listen and list hosts. Keep it free of `game/` imports
  (it moves to `core/` in wave 6).
- Lobby screen: 5 slots (name, colour from `PlayerInfo.color_for_slot`, ready tick, "Bot" when filled by AI),
  host options: **fill empty slots with bots** (default on), rounds (default 6). Start button (host) enabled when
  every human is ready. Players joining mid-lobby take the first free slot; leaving frees it.
- Start: host builds `Array[PlayerInfo]` (humans keep their slot, bots `peer_id = 1`), sends
  `to_dict()`s + rules by reliable RPC; every peer instances `res://game/match/match.tscn` as `Main/Game/Match`,
  calls `setup()`; host calls `start()`. Players who try to join during a match are refused with a message.
- `finished(results)`: show a simple results list for 5 s, free the match, back to the lobby (same session).
  `NetworkManager.session_ended` (host left) → free match, back to menu showing the reason.
- CLI for tests: `--auto-ready`, `--lobby-autostart=N` (host starts once N humans are ready),
  `--discover` (client joins the first LAN host it finds). Add them to `AGENTS.md` Commands.

## Tests
- `lobby_test.sh`: host `--host --lobby-autostart=5` + 4 clients `--join=127.0.0.1 --auto-ready`
  (`--rounds=1` style rules via your own CLI, short phase times) → every log has `[Game] Match setup: 5 players`
  and `[Game] PHASE draft 1`; host logs `[Lobby] START`. A second case: 1 host + 1 client with `--discover`
  (no IP) joins via LAN discovery (`[Lobby] Found host`). `net_test` and `contract_test` still pass.
- Manual (user): 1) Export both builds (`docs/STEAM_EXPORT_AND_TESTING.md`). 2) Machine A: run, **Host (LAN)**.
  3) Machine B: the host appears under **LAN games**: click it. 4) Both click **Ready**, A clicks **Start**: the
  match loads on both. 5) Repeat with **Steam Host** / **Steam Join** (both Steam clients logged in, app 480).

## Finish
Handoff `docs/handoffs/C03.md` (public API: how a later hub starts a match, CLI flags), land per AGENTS.md step 8.
