#!/usr/bin/env bash
# C24 playtest fixes. (1) unit: respawn waits for a rival to pass (max-wait cap), race cut after every human
# finished, spectate after finishing, no free items without a drafted card, clean item ghosts.
# (2) LAN host + client: the client gets its own draft cards, and the host sees the client's build cursor and
# the card it holds (--test-cursor).
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
TEST_SCENE=res://game/match/tests/playtest_fixes_test.tscn launch_peer unit
L=res://game/lobby/main.tscn
TEST_SCENE=$L launch_peer host --host --name=Host --lobby-autostart=2 --rounds=1 --phase-time=6 \
	"--discovery-port=$((PORT + 1))" --quit-after=60
wait_log host '\[Net\] Hosting' 15 || exit 1
TEST_SCENE=$L launch_peer client --join=127.0.0.1 --name=C1 --auto-ready --test-cursor=column \
	"--discovery-port=$((PORT + 1))" --quit-after=60
fail=0
wait_log unit '\[TEST\] C24 (PASSED|FAILED)' 90 || fail=1
wait_log host '\[Game\] PHASE race 1' 60 || fail=1
cleanup_peers; sleep 0.5
grep '^\[TEST\]' "$OUT/unit.log"
assert_log unit '^\[TEST\] C24 PASSED' || fail=1
assert_log client '^\[HUD\] DRAFT show slot 1 ' && echo "  ok   client got its draft cards" || fail=1
assert_log host '^\[Build\] CURSOR 1 column' && echo "  ok   host sees the client's cursor holding a column" || fail=1
if [ $fail -eq 0 ]; then echo "PLAYTEST FIXES TEST PASSED"; else echo "PLAYTEST FIXES TEST FAILED (see $OUT)"; fi
exit $fail
