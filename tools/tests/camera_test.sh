#!/usr/bin/env bash
# C13: camera unit check (speed FOV) + headless standalone match starting in Build (--phase=build, no human, 2 bots):
# the director must log CAMERA build, swing, race in that order.
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
TEST_SCENE=res://game/camera/tests/camera_test.tscn launch_peer unit
TEST_SCENE=res://game/match/match.tscn launch_peer match --no-human --bots=2 --rounds=1 --laps=1 --phase=build --phase-time=3 --quit-after=14
wait_peers 60 || { echo "CAMERA TEST FAILED (peer exit/timeout, see $OUT)"; exit 1; }
fail=0
assert_log unit '^\[TEST\] CAMERA PASSED' || fail=1
order=$(grep -E '^\[Game\] CAMERA (build|swing|race)$' "$OUT/match.log" | head -3 | tr '\n' ' ')
[ "$order" = "[Game] CAMERA build [Game] CAMERA swing [Game] CAMERA race " ] || { echo "Bad camera order: $order"; fail=1; }
assert_clean_logs || fail=1
if [ $fail -eq 0 ]; then echo "CAMERA TEST PASSED"; else echo "CAMERA TEST FAILED (see $OUT)"; fi
exit $fail
