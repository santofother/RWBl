#!/usr/bin/env bash
# C03: real ENet peers cover ready gate, five slots, discovery, bots and session lifecycle.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://game/lobby/main.tscn
echo "Logs: $OUT"
launch_lobby() { launch_peer "$1" "--discovery-port=$((PORT + 1))" "${@:2}"; }
check_errors() {
    if grep -En 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load' "${logs[@]}" | grep -v 'max channels: 0'; then
        echo "LOBBY TEST FAILED (errors, see $OUT)"; exit 1
    fi
}
# Hold at four ready humans; the fifth arrival must load/start on all peers.
launch_lobby host --host --name=Host --lobby-autostart=5 --rounds=1 --phase-time=0.3 --quit-after=12
wait_log host '\[Lobby\] JOIN Host slot=0' 15
for i in 1 2 3; do
    launch_lobby "c$i" --join=127.0.0.1 "--name=C$i" --auto-ready --quit-after=11
done
wait_log host '\[Lobby\] READY C3 true' 10
if grep -q '\[Lobby\] START' "$OUT/host.log"; then echo "Started without five humans"; exit 1; fi
launch_lobby c4 --join=127.0.0.1 --name=C4 --auto-ready --quit-after=11
for peer in host c1 c2 c3 c4; do
    wait_log "$peer" '\[Game\] PHASE draft 1' 15
    assert_log "$peer" '\[Game\] Match setup: 5 players, 1 rounds'
    wait_log "$peer" '\[Lobby\] RETURNED' 15
done
assert_log host '\[Lobby\] START humans=5 players=5'
wait_peers 20
check_errors
# Discovery must join without an IP, fill the other three slots with bots, then return.
PORT=$((PORT + 2))
launch_lobby discovery_host --host --name=LanHost --lobby-autostart=2 --rounds=1 --phase-time=0.3 --quit-after=12
wait_log discovery_host '\[Net\] Hosting' 10
launch_lobby discovered --discover --name=Discovered --auto-ready --quit-after=10
wait_log discovered '\[Lobby\] Found host' 8
for peer in discovery_host discovered; do
    wait_log "$peer" '\[Game\] Match setup: 5 players, 1 rounds' 10
    wait_log "$peer" '\[Game\] PHASE draft 1' 10
    wait_log "$peer" '\[Lobby\] RETURNED' 15
done
assert_log discovery_host '\[Lobby\] START humans=2 players=5'
wait_peers 20
check_errors
# An unready human blocks start, leaving frees its slot, and no-fill sends only humans.
PORT=$((PORT + 2))
launch_lobby slots_host --host --name=SlotsHost --lobby-autostart=3 --no-fill-bots --rounds=1 --phase-time=0.2 --quit-after=12
wait_log slots_host '\[Lobby\] JOIN SlotsHost slot=0' 10
launch_lobby leaver --join=127.0.0.1 --name=Leaver --quit-after=2
wait_log slots_host '\[Lobby\] JOIN Leaver slot=1' 10
launch_lobby keeper --join=127.0.0.1 --name=Keeper --auto-ready --quit-after=11
wait_log slots_host '\[Lobby\] READY Keeper true' 10
if grep -q '\[Lobby\] START' "$OUT/slots_host.log"; then echo "Started with unready human"; exit 1; fi
wait_log slots_host '\[Lobby\] LEFT slot freed' 6
launch_lobby replacement --join=127.0.0.1 --name=Replacement --auto-ready --quit-after=9
wait_log slots_host '\[Lobby\] JOIN Replacement slot=1' 8
for peer in slots_host keeper replacement; do
    wait_log "$peer" '\[Game\] Match setup: 3 players' 10
    wait_log "$peer" '\[Lobby\] RETURNED' 15
done
wait_peers 20
check_errors
# Late joins get an explicit refusal before match RPCs; host exit cleans up on clients.
PORT=$((PORT + 2))
launch_lobby leaving_host --host --name=LeavingHost --lobby-autostart=2 --no-fill-bots --rounds=1 --phase-time=3 --quit-after=6
wait_log leaving_host '\[Net\] Hosting' 10
launch_lobby survivor --join=127.0.0.1 --name=Survivor --auto-ready --quit-after=8
wait_log survivor '\[Game\] PHASE draft 1' 10
launch_lobby late --join=127.0.0.1 --name=Late --auto-ready --quit-after=2
wait_log late '\[Lobby\] REJECTED Match already in progress' 6
if grep -q '\[Game\] Match setup' "$OUT/late.log"; then echo "Admitted a late join"; exit 1; fi
wait_log survivor 'Session ended: Host left the game' 10
wait_peers 15
check_errors
echo 'LOBBY TEST PASSED'
