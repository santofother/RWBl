#!/usr/bin/env bash
# C19: track pieces. (1) unit test game/track/tests/track_piece_test.tscn (illegal splices, closed loop, length,
#     checkpoints, removal restores the road). (2) standalone match, 3 bots, starts in BUILD, --no-bot-build:
#     two muds on the straight, illegal hairpins (start line, into the S-bend, on a corner), a legal hairpin at 60
#     (left) moves the first mud and displaces the second, a chicane overlapping it is rejected, a chicane on the
#     back straight is OK; then the 3 bots race 1 lap on the spliced track and all finish.
# (3) lobby host + client: the host splices a hairpin, the client a chicane over RPC and demolishes the hairpin;
#     both peers print the same track length and pieces after every change.
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
TEST_SCENE=res://game/track/tests/track_piece_test.tscn launch_peer unit
PLACES='mud_patch@62,-4,0,0;mud_patch@69,-4,0,1;piece_hairpin@10,-1,0,0;piece_hairpin@100,1,0,0'
PLACES="$PLACES;piece_hairpin@200,-1,0,0;piece_hairpin@60,-1,0,0;piece_chicane@120,1,0,1;piece_chicane@484,1,0,1"
TEST_SCENE=res://game/match/match.tscn launch_peer solo --no-human --bots=3 --phase=build --rounds=1 --laps=1 \
	--phase-time=110 --no-bot-build "--test-place=$PLACES" --quit-after=130
TEST_SCENE=res://game/lobby/main.tscn launch_peer host --host --name=Host --lobby-autostart=2 --no-fill-bots --free-build \
	--rounds=1 --phase-time=8 "--discovery-port=$((PORT + 1))" '--test-place=piece_hairpin@60,-1,0' --quit-after=170
wait_log host '\[Net\] Hosting' 15 || exit 1
TEST_SCENE=res://game/lobby/main.tscn launch_peer client --join=127.0.0.1 --name=C1 --auto-ready \
	"--discovery-port=$((PORT + 1))" '--test-place=piece_chicane@484,1,0;demolish@1' --quit-after=160
fail=0
wait_log unit '\[TEST\] TRACK PIECE UNIT (PASSED|FAILED)' 40 || fail=1
wait_log client '\[TEST\] PLACE 1 ' 40 || fail=1
wait_log solo '\[Race\] OVER' 140 || fail=1
sleep 1
cleanup_peers; sleep 0.5
grep -E '^\[TEST\]' "$OUT/unit.log" | grep -v '^\[TEST\] ok' || true
grep -E '^\[(TEST|Build|Track|Race)\]' "$OUT/solo.log" | grep -v '^\[Build\] PATH'
echo "--- host";   grep -E '^\[(TEST|Track)\]|DEMOLISH|PIECE' "$OUT/host.log"
echo "--- client"; grep -E '^\[(TEST|Track)\]|DEMOLISH|PIECE' "$OUT/client.log"
assert_log unit '^\[TEST\] TRACK PIECE UNIT PASSED' && echo "  ok   unit test" || fail=1
expect() { assert_log solo "^\[TEST\] PLACE $1 $2 -> $3\$" && echo "  ok   $2 #$1 -> $3" || fail=1; }
expect 0 mud_patch OK
expect 1 mud_patch OK
expect 2 piece_hairpin NO_BUILD_ZONE
expect 3 piece_hairpin BLOCKS_PATH
expect 4 piece_hairpin OFF_TRACK
expect 5 piece_hairpin OK
expect 6 piece_chicane TOO_CLOSE
expect 7 piece_chicane OK
assert_log solo '^\[Build\] PIECE moved 1$' && echo "  ok   mud 1 moved onto the hairpin" || fail=1
assert_log solo '^\[Build\] PIECE displaced 2$' && echo "  ok   mud 2 displaced (would overlap mud 1)" || fail=1
assert_log solo '^\[TEST\] TRACK length=7[5-9][0-9]\.[0-9] pieces=3:piece_hairpin@60\.0,4:piece_chicane@484\.0$' \
	&& echo "  ok   track grew, pieces in order" || fail=1
for place in 1 2 3; do assert_log solo "^\[Race\] FINISH [0-9] $place " || fail=1; done
assert_log solo '^\[Race\] OVER order=\[[0-9], [0-9], [0-9]\] finished=3' && echo "  ok   3 bots finished a lap" || fail=1
# Host + client over RPC: same track after every change.
assert_log host '^\[TEST\] PLACE 0 piece_hairpin -> OK$' || fail=1
assert_log client '^\[TEST\] PLACE 0 piece_chicane -> OK$' && echo "  ok   client chicane over RPC" || fail=1
assert_log client '^\[TEST\] PLACE 1 demolish -> OK$' && echo "  ok   client demolished the hairpin over RPC" || fail=1
h=$(grep '^\[TEST\] TRACK ' "$OUT/host.log"); c=$(grep '^\[TEST\] TRACK ' "$OUT/client.log")
if [ -n "$h" ] && [ "$h" = "$c" ] && [ "$(echo "$h" | wc -l)" -eq 3 ]; then echo "  ok   host and client tracks identical (3 changes)"
else echo "  FAIL host/client tracks differ"; echo "host:"; echo "$h"; echo "client:"; echo "$c"; fail=1; fi
echo "$h" | tail -n 1 | grep -Eq 'pieces=2:piece_chicane@400\.[0-9]$' && echo "  ok   hairpin gone, chicane slid back" || { echo "  FAIL final pieces"; fail=1; }
assert_clean_logs || fail=1
if [ $fail -eq 0 ]; then echo "TRACK PIECE TEST PASSED"; else echo "TRACK PIECE TEST FAILED (see $OUT)"; fi
exit $fail
