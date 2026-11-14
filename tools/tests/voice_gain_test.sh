#!/usr/bin/env bash
# (from LastMage S08) quiet speech gain, clipping bounds and existing proximity falloff.
set -eu
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://core/tests/voice_gain_test.tscn
launch_peer voice_gain
wait_peers 20
assert_log voice_gain '^\[TEST\] VOICE GAIN PASSED'
assert_clean_logs
echo 'VOICE GAIN TEST PASSED'
