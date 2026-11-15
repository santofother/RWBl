#!/usr/bin/env bash
# C12: combat unit test (rwbl/game/combat/tests/combat_test.tscn) headless and offline: scripted rams break
# wheels (limp, crawl, wreck), horse hits stun, kill/self_kill attribution, respawn < 3 s, crow drops.
# Then a 4-bot standalone race checks the real wiring runs clean.
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
TEST_SCENE=res://game/combat/tests/combat_test.tscn launch_peer unit
TEST_SCENE=res://game/match/match.tscn launch_peer match --no-human --bots=4 --rounds=1 --phase=race --phase-time=12 --quit-after=20
wait_peers 90 || { echo "COMBAT TEST FAILED (peer exit/timeout, see $OUT)"; grep -E '^\[(TEST|Combat)\]' "$OUT/unit.log"; exit 1; }
fail=0
grep -E '^\[(TEST|Combat)\]' "$OUT/unit.log"
assert_log unit '^\[TEST\] COMBAT PASSED' || fail=1
assert_log unit '^\[Combat\] FX wheel 0 ' || fail=1
assert_log unit '^\[Combat\] FX burst 0' || fail=1
assert_clean_logs || fail=1
if [ $fail -eq 0 ]; then echo "COMBAT TEST PASSED"; else echo "COMBAT TEST FAILED (see $OUT)"; fi
exit $fail
