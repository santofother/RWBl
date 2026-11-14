#!/usr/bin/env bash
# C06: a bot drives around an oil patch placed in the middle of the road.
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
TEST_SCENE=res://game/bots/tests/bot_patch_test.tscn launch_peer patch --quit-after=60
fail=0
wait_log patch '\[TEST\] BOT PATCH (PASSED|FAILED)' 50 || fail=1
cleanup_peers; sleep 0.5
grep '^\[TEST\]' "$OUT/patch.log"
assert_log patch '^\[TEST\] BOT PATCH PASSED' || fail=1
assert_clean_logs || fail=1
if [ $fail -eq 0 ]; then echo "BOT PATCH TEST PASSED"; else echo "BOT PATCH TEST FAILED (see $OUT)"; fi
exit $fail
