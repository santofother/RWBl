#!/usr/bin/env bash
# C06 (long, skipped by --quick): 5 bots race for 5 minutes. No errors, every bot keeps lapping (>= 6 laps each,
# no more than 6 STUCK each).
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
TEST_SCENE=res://game/match/match.tscn launch_peer match --no-human --bots=5 --phase=race --rounds=1 \
	--laps=99 --phase-time=300 --autotest=295 --quit-after=305
fail=0
wait_log match '\[TEST\] CHARIOT 4 ' 320 || fail=1
cleanup_peers; sleep 0.5
for s in 0 1 2 3 4; do
	laps=$(grep -c "^\[Bot\] LAP slot $s " "$OUT/match.log")
	stuck=$(grep -c "^\[Bot\] STUCK slot $s " "$OUT/match.log")
	echo "slot $s: laps=$laps stuck=$stuck"
	[ "$laps" -ge 6 ] || { echo "slot $s: fewer than 6 laps"; fail=1; }
	[ "$stuck" -le 6 ] || { echo "slot $s: too often stuck"; fail=1; }
done
assert_clean_logs || fail=1
if [ $fail -eq 0 ]; then echo "BOT SOAK TEST PASSED"; else echo "BOT SOAK TEST FAILED (see $OUT)"; fi
exit $fail
