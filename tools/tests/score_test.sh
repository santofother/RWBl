#!/usr/bin/env bash
# C11: scoring unit test (rwbl/game/scoring/tests/score_test.tscn) headless and offline, then a 4-bot standalone
# round checks the real wiring: `[Score] ROUND` after the race.
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
TEST_SCENE=res://game/scoring/tests/score_test.tscn launch_peer unit
TEST_SCENE=res://game/match/match.tscn launch_peer match --no-human --bots=4 --rounds=1 --phase=race --phase-time=9 --quit-after=30
wait_peers 90 || { echo "SCORE TEST FAILED (peer exit/timeout, see $OUT)"; grep '^\[TEST\]' "$OUT/unit.log"; exit 1; }
fail=0
grep -E '^\[TEST\]' "$OUT/unit.log"
assert_log unit '^\[TEST\] SCORE PASSED' || fail=1
assert_log match '^\[Score\] ROUND 1 ' || fail=1
assert_clean_logs || fail=1
if [ $fail -eq 0 ]; then echo "SCORE TEST PASSED"; else echo "SCORE TEST FAILED (see $OUT)"; fi
exit $fail
