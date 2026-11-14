#!/usr/bin/env bash
# C02: contract classes/signals exist and stubs behave (contract_test.tscn), then a standalone offline match
# (4 bots, race phase only, 1 round) runs to MATCH FINISHED with every chariot having driven forward.
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
TEST_SCENE=res://game/common/tests/contract_test.tscn launch_peer contract
TEST_SCENE=res://game/match/match.tscn launch_peer match --no-human --bots=4 --phase=race --rounds=1 \
	--phase-time=4 --autotest=3.5 --quit-after=9.5
wait_peers 40 || { echo "CONTRACT TEST FAILED (peer exit/timeout, see $OUT)"; exit 1; }

fail=0
assert_log contract '^\[TEST\] CONTRACT PASSED' || fail=1
assert_log match '^\[Game\] PHASE race 1' || fail=1
assert_log match '^\[Game\] MATCH FINISHED' || fail=1
n=$(grep -c '^\[TEST\] CHARIOT ' "$OUT/match.log")
[ "$n" -eq 4 ] && echo "  ok   4 chariots reported" || { echo "  FAIL expected 4 chariots, got $n"; fail=1; }
# Grid is just behind the line (progress ~300 of ~316 m); after 3.5 s every bot must be well past it.
while read -r line; do
	p=${line##*progress=}
	awk -v p="$p" 'BEGIN { exit !(p > 10 && p < 200) }' && echo "  ok   $line" || { echo "  FAIL $line"; fail=1; }
done < <(grep '^\[TEST\] CHARIOT ' "$OUT/match.log")
assert_clean_logs || fail=1

if [ $fail -eq 0 ]; then echo "CONTRACT TEST PASSED"; else echo "CONTRACT TEST FAILED (see $OUT)"; fi
exit $fail
