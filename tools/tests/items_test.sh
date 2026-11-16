#!/usr/bin/env bash
# C10: item gauntlet, headless and offline (rwbl/game/items/tests/items_test.tscn): one chariot driven through
# each of the 8 wave 2 items on real physics frames, trap_hit/report_hit, and the slide_far tag rule.
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
TEST_SCENE=res://game/items/tests/items_test.tscn launch_peer items
wait_peers 120 || { echo "ITEMS TEST FAILED (peer exit/timeout, see $OUT)"; grep '^\[TEST\]' "$OUT/items.log"; exit 1; }

fail=0
grep -E '^\[(TEST|Item)\]' "$OUT/items.log"
assert_log items '^\[TEST\] ITEMS PASSED' || fail=1
for id in oil_slick mud_patch ice_sheet speed_pad ramp column swinging_axe pit bumper lion_dung catapult whirlwind spike_log; do
    assert_log items "^\[Item\] HIT $id 0\$" || fail=1
done
assert_log items '^\[Item\] INTERACT slide_far ' || fail=1
assert_clean_logs || fail=1
if [ $fail -eq 0 ]; then echo "ITEMS TEST PASSED"; else echo "ITEMS TEST FAILED (see $OUT)"; fi
exit $fail
