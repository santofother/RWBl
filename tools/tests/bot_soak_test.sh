#!/usr/bin/env bash
# C06/C23 (long, skipped by --quick): 5 bots play 5 full rounds (race limit 240 s: the course gets long) (they draft and place items and track pieces, so
# the course grows). No errors, every bot reaches the finish in all but at most one race (the win rule
# may end the match before round 5), no more than 6 STUCK each.
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
TEST_SCENE=res://game/match/match.tscn launch_peer match --no-human --bots=5 --rounds=5 \
	--phase-time=5 --race-time=240 --quit-after=1100
fail=0
wait_log match '\[Game\] MATCH FINISHED' 1100 || fail=1
cleanup_peers; sleep 0.5
grep -E '^\[Race\] (Start|OVER)' "$OUT/match.log"
races=$(grep -c '^\[Race\] OVER' "$OUT/match.log")
[ "$races" -ge 3 ] || { echo "only $races races"; fail=1; }
for s in 0 1 2 3 4; do
	fin=$(grep -c "^\[Bot\] FINISH slot $s " "$OUT/match.log")
	stuck=$(grep -c "^\[Bot\] STUCK slot $s " "$OUT/match.log")
	echo "slot $s: finished=$fin stuck=$stuck"
	[ "$fin" -ge $((races - 1)) ] || { echo "slot $s: finished only $fin of $races races"; fail=1; }
	[ "$stuck" -le 6 ] || { echo "slot $s: too often stuck"; fail=1; }
done
assert_clean_logs || fail=1
if [ $fail -eq 0 ]; then echo "BOT SOAK TEST PASSED"; else echo "BOT SOAK TEST FAILED (see $OUT)"; fi
exit $fail
