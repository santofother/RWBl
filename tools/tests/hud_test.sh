#!/usr/bin/env bash
# C14: HUD. (1) hud_preview.tscn cycles fake race / draft / build states headless and checks what the labels show.
# (2) a standalone 3-bot match with a human slot (--phase=race) runs the live HUD wiring without errors.
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
TEST_SCENE=res://game/hud/tests/hud_preview.tscn launch_peer preview --quit-after=30
TEST_SCENE=res://game/match/match.tscn launch_peer live --bots=2 --rounds=1 --phase-time=3 --quit-after=12
fail=0
wait_log preview '\[TEST\] HUD (PASSED|FAILED)' 30 || fail=1
wait_peers 40 || fail=1
grep '^\[TEST\]' "$OUT/preview.log"
assert_log preview '^\[TEST\] HUD PASSED' || fail=1
assert_log preview '^\[TEST\] HUD lap=2/3 pos=1st' || fail=1
assert_log preview '^\[TEST\] HUD draft cards=3' || fail=1
assert_log preview '^\[TEST\] HUD picked=1' || fail=1
assert_log live '\[Game\] PHASE race 1' || fail=1
assert_clean_logs || fail=1
if [ $fail -eq 0 ]; then echo "HUD TEST PASSED"; else echo "HUD TEST FAILED (see $OUT)"; fi
exit $fail
