#!/usr/bin/env bash
# C05: race rules. (1) unit test in race/tests/race_test.tscn (countdown, grid, ordered checkpoints, teleport
# does not count a lap). (2) full standalone match: 3 bots, 2 laps (test-only RaceTestPilot, because the road has no walls) -> 3 [Race] FINISH lines (places 1-3),
# race_over, and the race phase ends early (PHASE score long before the 150 s phase time).
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
TEST_SCENE=res://game/race/tests/race_test.tscn launch_peer unit
TEST_SCENE=res://game/race/tests/race_full.tscn launch_peer match --quit-after=140
fail=0
wait_log unit '\[TEST\] RACE UNIT (PASSED|FAILED)' 40 || fail=1
wait_log match '\[Game\] PHASE score' 120 || fail=1
cleanup_peers; sleep 0.5
grep '^\[TEST\]' "$OUT/unit.log"
grep '^\[Race\]' "$OUT/match.log"
assert_log unit '^\[TEST\] RACE UNIT PASSED' || fail=1
for place in 1 2 3; do assert_log match "^\[Race\] FINISH [0-9] $place " || fail=1; done
assert_log match '^\[Race\] OVER order=\[[0-9], [0-9], [0-9]\] finished=3' || fail=1
assert_clean_logs || fail=1
if [ $fail -eq 0 ]; then echo "RACE TEST PASSED"; else echo "RACE TEST FAILED (see $OUT)"; fi
exit $fail
