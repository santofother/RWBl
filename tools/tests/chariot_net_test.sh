#!/usr/bin/env bash
# C07 (N4): host + 2 clients, all with --lag-ms=100 (200 ms round trip), start a lobby match without bots.
# Clients drive scripted inputs in the race (see rwbl/game/net/tests/net_test_driver.gd). Checks:
#  - remote chariots on each client vs the host at the same NetClock times: error < 1.5 m
#  - own chariot (prediction): moves within 1 physics tick of the first throttle input
#  - own chariot ends < 0.5 m from the host's position after stopping
# Usage: tools/tests/chariot_net_test.sh   (env GODOT=/path/to/Godot to override the binary)
set -u
source "$(dirname "$0")/lib.sh"
TEST_SCENE=res://game/lobby/main.tscn
echo "Logs: $OUT"
COMMON=("--discovery-port=$((PORT + 1))" --lag-ms=100 --net-autotest --quit-after=55 ${NET_EXTRA:-})
launch_peer host --host --name=Host --lobby-autostart=3 --no-fill-bots --rounds=1 --phase-time=11 "${COMMON[@]}"
wait_log host '\[Net\] Hosting' 15 || exit 1
launch_peer c1 --join=127.0.0.1 --name=C1 --auto-ready "${COMMON[@]}"
launch_peer c2 --join=127.0.0.1 --name=C2 --auto-ready "${COMMON[@]}"
for p in host c1 c2; do
	wait_log "$p" '\[TEST\] NETSTATS' 75 || { echo "CHARIOT NET TEST FAILED (no result from $p)"; exit 1; }
done
{ cleanup_peers; wait; } 2>/dev/null

fail=0
H="$OUT/host.log"
grep -q '\[Lobby\] START humans=3 players=3' "$H" && echo "  ok   match started with 3 humans, no bots" \
	|| { echo "  FAIL lobby start line"; fail=1; }
for c in c1 c2; do
	L="$OUT/$c.log"
	# Remote chariots vs host at the same NetClock times.
	awk -v name="$c" '
		FNR == NR { if ($2 == "POSAT") host[$3 " " $4] = $5 " " $6; next }
		$2 == "POSAT" { k = $3 " " $4; if (!(k in host)) next
			split(host[k], h, " "); dx = $5 - h[1]; dz = $6 - h[2]; d = sqrt(dx*dx + dz*dz)
			n++; if (d > max) max = d }
		END { if (n < 20) { printf "  FAIL %s: only %d remote samples matched\n", name, n; exit 1 }
			if (max >= 1.5) { printf "  FAIL %s: remote error %.2f m (>= 1.5) over %d samples\n", name, max, n; exit 1 }
			printf "  ok   %s: remote max error %.2f m over %d samples\n", name, max, n }' "$H" "$L" || fail=1
	# Own chariot: response and final position.
	r=$(grep -o 'RESPONSE ticks=[0-9-]*' "$L" | head -1 | cut -d= -f2)
	if [ -n "$r" ] && [ "$r" -le 1 ]; then echo "  ok   $c: own chariot moved $r tick(s) after input"
	else echo "  FAIL $c: response '${r:-none}' ticks"; fail=1; fi
	own=$(grep '\[TEST\] FINAL' "$L" | head -1)
	slot=$(echo "$own" | awk '{print $3}')
	hostf=$(grep "\[TEST\] FINAL $slot " "$H" | head -1)
	echo "$own|$hostf" | awk -F'|' -v name="$c" '{ split($1, a, " "); split($2, b, " ")
		if (b[3] == "") { printf "  FAIL %s: no host FINAL for slot\n", name; exit 1 }
		dx = a[4] - b[4]; dz = a[5] - b[5]; d = sqrt(dx*dx + dz*dz)
		if (d >= 0.5) { printf "  FAIL %s: own final %.2f m from host\n", name, d; exit 1 }
		printf "  ok   %s: own final %.3f m from host\n", name, d }' || fail=1
	# The chariot must really have driven (otherwise the checks above are trivial).
	awk -v s="$slot" -v name="$c" '$2 == "POSAT" && $4 == s { if (!n++) { x0 = $5; z0 = $6 } x = $5; z = $6 }
		END { d = sqrt((x-x0)^2 + (z-z0)^2); if (d < 15) { printf "  FAIL %s: only drove %.1f m\n", name, d; exit 1 }
			printf "  ok   %s: drove %.1f m on the host\n", name, d }' "$H" || fail=1
	grep '\[TEST\] NETSTATS' "$L" | sed "s/^/       $c /"
done
grep '\[TEST\] NETSTATS' "$H" | sed "s/^/       host /"
if grep -En 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load' "${logs[@]}" | grep -v "max channels: 0"; then
	echo "  FAIL errors in logs"; fail=1
fi
if [ $fail -eq 0 ]; then echo "CHARIOT NET TEST PASSED"; else echo "CHARIOT NET TEST FAILED (see $OUT)"; fi
exit $fail
