#!/usr/bin/env bash
# C06: 5 bots drive a headless race on their own: every bot logs >= 2 [Bot] LAP, none gets STUCK more than twice,
# no errors. Laps are set high so the race doesn't end before the autotest report.
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
TEST_SCENE=res://game/match/match.tscn launch_peer match --no-human --bots=5 --phase=race --rounds=1 \
	--laps=6 --phase-time=90 --autotest=85 --quit-after=95
fail=0
wait_log match '\[TEST\] CHARIOT 4 ' 100 || fail=1
cleanup_peers; sleep 0.5
grep -E '^\[Bot\]|^\[TEST\]' "$OUT/match.log" | tail -n 40
for s in 0 1 2 3 4; do
	laps=$(grep -c "^\[Bot\] LAP slot $s " "$OUT/match.log")
	stuck=$(grep -c "^\[Bot\] STUCK slot $s " "$OUT/match.log")
	echo "slot $s: laps=$laps stuck=$stuck"
	[ "$laps" -ge 2 ] || { echo "slot $s: fewer than 2 laps"; fail=1; }
	[ "$stuck" -le 2 ] || { echo "slot $s: stuck more than twice"; fail=1; }
done
assert_clean_logs || fail=1
if [ $fail -eq 0 ]; then echo "BOT RACE TEST PASSED"; else echo "BOT RACE TEST FAILED (see $OUT)"; fi
exit $fail
