#!/usr/bin/env bash
# C01 (N1): headless ENet test, 1 host + 2 clients on localhost in the cube sandbox.
# Each player parks its cube at a known x,z; at the autotest time every process prints what it sees and we
# check all 3 cubes are where expected on all 3 peers (= position sync works both directions).
# Usage: tools/tests/net_test.sh   (env GODOT=/path/to/Godot to override the binary)
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
launch_peer host --host --name=Host --test-target=0,8 --autotest=7 --quit-after=10
wait_log host 'Hosting' 15 || exit 1
launch_peer c1 --join=127.0.0.1 --name=C1 --test-target=6,-9 --autotest=5 --quit-after=9
launch_peer c2 --join=127.0.0.1 --name=C2 --test-target=-6,-9 --autotest=5 --quit-after=9
wait_peers 30 || { echo "NET TEST FAILED (peer exit/timeout, see $OUT)"; exit 1; }

fail=0
check_pos() { # log name x z
	local line
	line=$(grep "^\[TEST\] POS $2 " "$1" | tail -1)
	if [ -z "$line" ]; then echo "  FAIL $(basename "$1"): no position for $2"; fail=1; return; fi
	echo "$line" | awk -v x="$3" -v z="$4" -v f="$(basename "$1")" -v n="$2" '{
		dx=$4-x; dz=$5-z; if (dx<0) dx=-dx; if (dz<0) dz=-dz
		if (dx<0.5 && dz<0.5) { print "  ok   " f ": " n " at " $4 "," $5 }
		else { print "  FAIL " f ": " n " at " $4 "," $5 " expected " x "," z; exit 1 } }' || fail=1
}
for f in host c1 c2; do
	log="$OUT/$f.log"
	check_pos "$log" Host 0 8
	check_pos "$log" C1 6 -9
	check_pos "$log" C2 -6 -9
done
grep -q "^\[TEST\] PEERS 2" "$OUT/host.log" && echo "  ok   host sees 2 peers" || { echo "  FAIL host peer count: $(grep PEERS "$OUT/host.log")"; fail=1; }
grep -q "CONNECTED my_id" "$OUT/c1.log" && grep -q "CONNECTED my_id" "$OUT/c2.log" && echo "  ok   both clients connected" || { echo "  FAIL client connect"; fail=1; }
# WHY: not assert_clean_logs: clients quit first, so the host logs PEER_DISCONNECTED by design.
# WHY: ENet logs "Unable to send packet on channel 0, max channels: 0" when the host sends to a client
# that is already quitting at the end of the test. Harmless shutdown race, so it is ignored.
if grep -En 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load' "${logs[@]}" | grep -v "max channels: 0"; then echo "  FAIL errors in logs"; fail=1; fi

if [ $fail -eq 0 ]; then echo "NET TEST PASSED"; else echo "NET TEST FAILED (see $OUT)"; fi
exit $fail
