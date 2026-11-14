#!/usr/bin/env bash
# C04: chariot controller + tuning panel, headless and offline (rwbl/game/chariot/tests/chariot_test.tscn):
# top speed, turning, oil slip, whip/stamina, broken wheels, snapshot round trip, collisions, jump, effects, F2.
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
TEST_SCENE=res://game/chariot/tests/chariot_test.tscn launch_peer chariot
wait_peers 60 || { echo "CHARIOT TEST FAILED (peer exit/timeout, see $OUT)"; grep '^\[TEST\]' "$OUT/chariot.log"; exit 1; }

fail=0
grep '^\[TEST\]' "$OUT/chariot.log"
assert_log chariot '^\[TEST\] CHARIOT PASSED' || fail=1
assert_clean_logs || fail=1
if [ $fail -eq 0 ]; then echo "CHARIOT TEST PASSED"; else echo "CHARIOT TEST FAILED (see $OUT)"; fi
exit $fail
