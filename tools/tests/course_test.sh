#!/usr/bin/env bash
# C22: modular course unit test game/track/tests/course_test.tscn (default course, insert at middle joints and at
# the end, rigid move of the road after the joint, rejections inside start/finish and for a self-crossing course,
# removal closes the gap).
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
TEST_SCENE=res://game/track/tests/course_test.tscn launch_peer unit --quit-after=60
fail=0
wait_log unit '\[TEST\] COURSE UNIT (PASSED|FAILED)' 60 || fail=1
sleep 0.5
cleanup_peers
grep -E '^\[TEST\]' "$OUT/unit.log" | grep -v '^\[TEST\] ok' || true
assert_log unit '^\[TEST\] COURSE UNIT PASSED' && echo "  ok   course unit test" || fail=1
assert_clean_logs || fail=1
if [ $fail -eq 0 ]; then echo "COURSE TEST PASSED"; else echo "COURSE TEST FAILED (see $OUT)"; fi
exit $fail
