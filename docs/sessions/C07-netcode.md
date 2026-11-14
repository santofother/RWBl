# C07 — Host-authoritative chariot netcode: interpolation, light prediction, lag sim (N4)
Agent: **Either** (suggested Claude) · Wave 2 · Branch: `c07-netcode`
Model: Claude **Opus 5.5, high** · or Codex **GPT-6 Astra, low–medium**
Depends on: C03, C04

Owns: `rwbl/game/net/**`, `tools/tests/chariot_net_test.sh`
Read: `DESIGN.md` §8 · `docs/ARCHITECTURE.md` §2, §4 (Input, Snapshot, Chariot, Clock) · handoffs `C02`, `C03`,
`C04` · `rwbl/game/net/chariot_sync.gd` (your stub) · `rwbl/game/common/chariot_input.gd`, `chariot_snapshot.gd`,
`net_clock.gd` · header of `rwbl/game/chariot/chariot.gd` · `rwbl/core/network_manager.gd` (public API only)

## Goal
At 100 ms latency, other chariots move smoothly and your own chariot responds instantly, while the host stays
the only authority (milestone N4).

## Steps
- Snapshot buffer per chariot keyed by the host time in each packet (`NetClock`); render ~100 ms behind
  (`# TUNE` interp delay) and interpolate position/rotation (slerp)/cart angle; extrapolate ≤ 150 ms on gaps.
- Own chariot: light prediction. The client runs `Chariot.step()` locally with its inputs; the host puts the
  last processed input `seq` per slot into the packet (packet format is yours, `ChariotSnapshot` layout isn't);
  the client corrects toward the host state smoothly (snap if error > 3 m). Remote chariots are never predicted.
- Input robustness: send the last 3 inputs per packet (unreliable), host ignores old `seq`.
- `--lag-ms=N` and `--loss=PCT` CLI: simulated one-way delay / drop on both input and snapshot sends (add to
  `AGENTS.md` Commands). Show RTT, interp delay and kB/s in a small F3-adjacent label (don't edit `core/`).
- On `GameEvents.roster_changed` (dropout → bot) update slot owners so the host stops waiting for that peer.
- Keep `submit_input()` the only path into `Chariot.step()` on the host (contract). The sandbox cube must still work.

## Tests
- `chariot_net_test.sh`: host (`--lobby-autostart=3`, bots off) + 2 clients with `--lag-ms=100` start a match
  via C03's CLI, race phase; clients drive scripted inputs. At autotest each peer prints `[TEST] POSAT t slot x z`
  sampled at the same `NetClock` times; remote chariot error vs host < 1.5 m; own chariot moves within 1 tick of
  input (prediction on) and ends < 0.5 m from the host's position. `net_test` still passes.
- Manual (user): 1) Export the macOS build. 2) Run two copies: `RWBL.app/Contents/MacOS/RWBL -- --host --lag-ms=100`
  and `... -- --join=127.0.0.1 --lag-ms=100` (Terminal). 3) Ready, Start, drive. Does your chariot feel
  instant? Do the others move smoothly? Repeat on two machines over LAN.

## Finish
Handoff `docs/handoffs/C07.md` (packet format, tunables, bandwidth at 5 players), land per AGENTS.md step 8.
