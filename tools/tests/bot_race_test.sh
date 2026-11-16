#!/usr/bin/env bash
# C06/C23: 5 bots drive a headless race on their own from the start line to the finish line: every bot logs
# [Bot] FINISH, none gets STUCK more than twice, no errors.
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
TEST_SCENE=res://game/match/match.tscn launch_peer match --no-human --bots=5 --phase=race --rounds=1 \
	--phase-time=90 --autotest=85 --quit-after=95
fail=0
wait_log match '\[TEST\] CHARIOT 4 ' 100 || fail=1
cleanup_peers; sleep 0.5
grep -E '^\[Bot\]|^\[TEST\]' "$OUT/match.log" | tail -n 40
for s in 0 1 2 3 4; do
	fin=$(grep -c "^\[Bot\] FINISH slot $s " "$OUT/match.log")
	stuck=$(grep -c "^\[Bot\] STUCK slot $s " "$OUT/match.log")
	echo "slot $s: finished=$fin stuck=$stuck"
	[ "$fin" -eq 1 ] || { echo "slot $s: did not reach the finish"; fail=1; }
	[ "$stuck" -le 2 ] || { echo "slot $s: stuck more than twice"; fail=1; }
done
assert_log match '^\[Race\] OVER order=\[[0-9], [0-9], [0-9], [0-9], [0-9]\] finished=5' || fail=1
assert_clean_logs || fail=1
if [ $fail -eq 0 ]; then echo "BOT RACE TEST PASSED"; else echo "BOT RACE TEST FAILED (see $OUT)"; fi
exit $fail
