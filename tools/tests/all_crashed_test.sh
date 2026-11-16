#!/usr/bin/env bash
# C21 session (user): no timed respawn; everyone left crashed and stuck -> round over, points by distance, no
# winner even for a slot over the win score (game/match/tests/all_crashed_test.tscn).
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
TEST_SCENE=res://game/match/tests/all_crashed_test.tscn launch_peer unit --phase-time=20 --quit-after=80
fail=0
wait_log unit '\[TEST\] ALL CRASHED (PASSED|FAILED)' 80 || fail=1
cleanup_peers; sleep 0.5
grep -E '^\[(TEST|Race|Score)\]|WIN' "$OUT/unit.log"
assert_log unit '^\[TEST\] ALL CRASHED PASSED' || fail=1
assert_log unit '^\[Race\] ALL CRASHED$' || fail=1
if grep -q '^\[Game\] WIN' "$OUT/unit.log"; then echo "  FAIL someone won without finishing"; fail=1; fi
assert_clean_logs || fail=1
if [ $fail -eq 0 ]; then echo "ALL CRASHED TEST PASSED"; else echo "ALL CRASHED TEST FAILED (see $OUT)"; fi
exit $fail
