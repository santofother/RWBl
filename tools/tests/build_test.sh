#!/usr/bin/env bash
# C08 (N5): build phase placement + host validation.
# (1) standalone match, 3 bots, starts in BUILD, --test-place hook (item@progress,lateral,deg,slot):
#     oil on the straight -> OK + SPAWN; oil on the start line -> NO_BUILD_ZONE; mud on top of the oil -> TOO_CLOSE;
#     3 columns across the road (one per slot) -> OK, OK, BLOCKS_PATH; path check < 50 ms; bots placed; phase ends early.
#     C17 Demolish (entry demolish@uid,slot): slot 1 removes slot 0's oil -> OK; again -> UNKNOWN_ITEM; uid 999 ->
#     UNKNOWN_ITEM; slot 1 a second time -> NOT_IN_HAND; mud where the oil was -> OK; in RACE -> WRONG_PHASE.
# (2) lobby host + client: the client's requests go over RPC, both peers spawn the same items; the client
#     demolishes the host's oil -> removed on both peers, item_removed once each.
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
PLACES='oil_slick@60,0,0,0;oil_slick@0,0,0,1;mud_patch@60,1,0,2;column@100,-4,0,0;column@100,0,0,1;column@100,4,0,2'
PLACES="$PLACES;demolish@1,1;demolish@1,2;demolish@999,2;demolish@2,1;mud_patch@60,1,0,2"
TEST_SCENE=res://game/match/match.tscn launch_peer solo --no-human --bots=3 --phase=build --rounds=1 \
	--phase-time=30 "--test-place=$PLACES" --test-race-demolish=3,0 --quit-after=12
# FIX(C09, claude): Draft now deals real hands (rules.free_build = false); the host validates, so it needs --free-build.
TEST_SCENE=res://game/lobby/main.tscn launch_peer host --host --name=Host --lobby-autostart=2 --no-fill-bots --free-build \
	--rounds=1 --phase-time=6 "--discovery-port=$((PORT + 1))" '--test-place=oil_slick@60,0,0' --quit-after=25
wait_log host '\[Net\] Hosting' 15 || exit 1
TEST_SCENE=res://game/lobby/main.tscn launch_peer client --join=127.0.0.1 --name=C1 --auto-ready \
	"--discovery-port=$((PORT + 1))" '--test-place=column@100,0,0;ramp@0,0,0;demolish@1;demolish@2' --quit-after=25
fail=0
wait_log solo '\[Game\] PHASE race' 30 || fail=1
wait_log client '\[TEST\] PLACE 3 ' 30 || fail=1
sleep 1
cleanup_peers; sleep 0.5
grep -E '^\[(TEST|Build)\]' "$OUT/solo.log"
echo "--- client"; grep -E '^\[(TEST|Build)\]' "$OUT/client.log"
expect() { assert_log solo "^\[TEST\] PLACE $1 $2 -> $3\$" && echo "  ok   $2 #$1 -> $3" || fail=1; }
expect 0 oil_slick OK
expect 1 oil_slick NO_BUILD_ZONE
expect 2 mud_patch TOO_CLOSE
expect 3 column OK
expect 4 column OK
expect 5 column BLOCKS_PATH
expect 6 demolish OK
expect 7 demolish UNKNOWN_ITEM
expect 8 demolish UNKNOWN_ITEM
expect 9 demolish NOT_IN_HAND
expect 10 mud_patch OK
assert_log solo '^\[Build\] DEMOLISH 1 by 1$' || fail=1
n=$(grep -c '^\[TEST\] ITEM_REMOVED 1$' "$OUT/solo.log"); [ "$n" = 1 ] && echo "  ok   item_removed 1 once" || { echo "  FAIL item_removed 1 x$n"; fail=1; }
assert_log solo '^\[TEST\] RACE DEMOLISH 3 -> WRONG_PHASE$' && echo "  ok   demolish in RACE -> WRONG_PHASE" || fail=1
assert_log solo '^\[Build\] SPAWN 1 oil_slick slot=0' || fail=1
for b in 0 1 2; do assert_log solo "^\[Build\] BOT $b placed [1-9]" || fail=1; done
assert_log solo '^\[Build\] ALL PLACED' || fail=1
# Path check speed (each check, not the one-off base grid).
awk '/^\[Build\] PATH (ok|BLOCKED)/ { n++; if ($6 + 0 > max) max = $6 + 0 }
	END { if (n < 3) { print "  FAIL only " n " path checks"; exit 1 }
		if (max >= 50) { printf "  FAIL path check %.1f ms (>= 50)\n", max; exit 1 }
		printf "  ok   %d path checks, slowest %.1f ms\n", n, max }' "$OUT/solo.log" || fail=1
# Host + client over RPC.
assert_log host '^\[TEST\] PLACE 0 oil_slick -> OK$' || fail=1
for c in "0 column OK" "1 ramp NO_BUILD_ZONE" "2 demolish OK" "3 demolish NOT_IN_HAND"; do
	set -- $c
	assert_log client "^\[TEST\] PLACE $1 $2 -> $3\$" && echo "  ok   client $2 -> $3 (over RPC)" || fail=1
done
for p in host client; do
	assert_log "$p" '^\[Build\] SPAWN 1 oil_slick slot=0 at 60\.0 0\.0' || fail=1
	assert_log "$p" '^\[Build\] SPAWN 2 column slot=1 at 100\.0 0\.0' || fail=1
	assert_log "$p" '^\[Build\] DEMOLISH 1 by 1$' || fail=1
	n=$(grep -c '^\[TEST\] ITEM_REMOVED 1$' "$OUT/$p.log"); [ "$n" = 1 ] && echo "  ok   $p item_removed 1 once" || { echo "  FAIL $p item_removed 1 x$n"; fail=1; }
	if grep -q '^\[Build\] DEMOLISH 2 ' "$OUT/$p.log"; then echo "  FAIL $p rejected demolish removed uid 2"; fail=1; fi
done
assert_log client '^\[TEST\] ITEM 1 gone=true$' || fail=1
if grep -q '^\[Build\] SPAWN 3' "$OUT/host.log" "$OUT/client.log"; then echo "  FAIL rejected item spawned"; fail=1; fi
assert_clean_logs || fail=1
if [ $fail -eq 0 ]; then echo "BUILD TEST PASSED"; else echo "BUILD TEST FAILED (see $OUT)"; fi
exit $fail
