#!/usr/bin/env bash
# C19/C22: track pieces in a match. (1) standalone match, 3 bots, starts in BUILD, --no-bot-build: two muds on
#     straights, illegal pieces (joint 0 = inside the start piece, joint 14 = after the finish, a left corner at
#     the end that runs the finish into the course), a legal hairpin at joint 2 (left) moves both muds along with
#     the course, a chicane at joint 5; then the 3 bots race start -> finish on the grown course and all finish.
# (2) lobby host + client: the host inserts a hairpin, the client a chicane over RPC and demolishes the hairpin;
#     both peers print the same course after every change.
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
PLACES='mud_patch@60,-4,0,0;mud_patch@250,3,0,1;piece_hairpin@0,1,0,0;piece_hairpin@14,1,0,0'
PLACES="$PLACES;piece_corner_left@13,1,0,0;piece_hairpin@2,-1,0,0;piece_chicane@5,1,0,1"
TEST_SCENE=res://game/match/match.tscn launch_peer solo --no-human --bots=3 --phase=build --rounds=1 \
	--phase-time=110 --no-bot-build "--test-place=$PLACES" --quit-after=130
TEST_SCENE=res://game/lobby/main.tscn launch_peer host --host --name=Host --lobby-autostart=2 --no-fill-bots --free-build \
	--rounds=1 --phase-time=8 "--discovery-port=$((PORT + 1))" '--test-place=piece_hairpin@2,-1,0' --quit-after=170
wait_log host '\[Net\] Hosting' 15 || exit 1
TEST_SCENE=res://game/lobby/main.tscn launch_peer client --join=127.0.0.1 --name=C1 --auto-ready \
	"--discovery-port=$((PORT + 1))" '--test-place=piece_chicane@5,1,0;demolish@1' --quit-after=160
fail=0
wait_log client '\[TEST\] PLACE 1 ' 40 || fail=1
wait_log solo '\[Race\] OVER' 140 || fail=1
sleep 1
cleanup_peers; sleep 0.5
grep -E '^\[(TEST|Build|Track|Race)\]' "$OUT/solo.log" | grep -v '^\[Build\] PATH'
echo "--- host";   grep -E '^\[(TEST|Track)\]|DEMOLISH|PIECE' "$OUT/host.log"
echo "--- client"; grep -E '^\[(TEST|Track)\]|DEMOLISH|PIECE' "$OUT/client.log"
expect() { assert_log solo "^\[TEST\] PLACE $1 $2 -> $3\$" && echo "  ok   $2 #$1 -> $3" || fail=1; }
expect 0 mud_patch OK
expect 1 mud_patch OK
expect 2 piece_hairpin NO_BUILD_ZONE
expect 3 piece_hairpin NO_BUILD_ZONE
expect 4 piece_corner_left BLOCKS_PATH
expect 5 piece_hairpin OK
expect 6 piece_chicane OK
assert_log solo '^\[Build\] PIECE moved 1$' && echo "  ok   mud 1 moved with the course" || fail=1
assert_log solo '^\[Build\] PIECE moved 2$' && echo "  ok   mud 2 moved with the course" || fail=1
if grep -q '^\[Build\] PIECE displaced' "$OUT/solo.log"; then echo "  FAIL a mud was displaced"; fail=1; fi
assert_log solo '^\[TEST\] TRACK length=60[0-9]\.[0-9] pieces=3:piece_hairpin@2,4:piece_chicane@5$' \
	&& echo "  ok   course grew, pieces at their joints" || fail=1
for place in 1 2 3; do assert_log solo "^\[Race\] FINISH [0-9] $place " || fail=1; done
assert_log solo '^\[Race\] OVER order=\[[0-9], [0-9], [0-9]\] finished=3' && echo "  ok   3 bots reached the finish" || fail=1
# Host + client over RPC: same course after every change.
assert_log host '^\[TEST\] PLACE 0 piece_hairpin -> OK$' || fail=1
assert_log client '^\[TEST\] PLACE 0 piece_chicane -> OK$' && echo "  ok   client chicane over RPC" || fail=1
assert_log client '^\[TEST\] PLACE 1 demolish -> OK$' && echo "  ok   client demolished the hairpin over RPC" || fail=1
h=$(grep '^\[TEST\] TRACK ' "$OUT/host.log"); c=$(grep '^\[TEST\] TRACK ' "$OUT/client.log")
if [ -n "$h" ] && [ "$h" = "$c" ] && [ "$(echo "$h" | wc -l)" -eq 3 ]; then echo "  ok   host and client courses identical (3 changes)"
else echo "  FAIL host/client courses differ"; echo "host:"; echo "$h"; echo "client:"; echo "$c"; fail=1; fi
echo "$h" | tail -n 1 | grep -Eq 'length=4(79|80)\.[0-9] pieces=2:piece_chicane@4$' && echo "  ok   hairpin gone, gap closed" || { echo "  FAIL final pieces"; fail=1; }
assert_clean_logs || fail=1
if [ $fail -eq 0 ]; then echo "TRACK PIECE TEST PASSED"; else echo "TRACK PIECE TEST FAILED (see $OUT)"; fi
exit $fail
