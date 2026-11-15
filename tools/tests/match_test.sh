#!/usr/bin/env bash
# C09: match flow. (1) standalone 5 bots, --rounds=6 test cap -> 6 x draft/build/race/score in order, 3 cards dealt
# and 1 kept per bot per round, MATCH FINISHED with 5 results.
# (2) --test-totals: round 2 deals the last place a best-rarity card and the leader only commons.
# C16 win rule: (3) everyone at 1000 -> the 1st finisher of race 1 wins; slot 0 alone at 1000 -> WIN only if it
# finishes 1st; (5) no --rounds: the match is still running in round 7. Unit: match_rules_test. (4) lobby host + client: same phase sequence; client killed mid-match -> its slot
# becomes a bot and the match still finishes.
set -u
source "$(dirname "$0")/lib.sh"
echo "Logs: $OUT"
M=res://game/match/match.tscn
TEST_SCENE=$M launch_peer full --no-human --bots=5 --rounds=6 --phase-time=2 --quit-after=80
TEST_SCENE=$M launch_peer catchup --no-human --bots=5 --rounds=3 --phase-time=1 \
	--test-totals=0:20,1:0,2:5,3:6,4:7 --quit-after=30
# C16: a real race has to finish for a win, so the race gets 60 s while the other phases stay at 1 s.
TEST_SCENE=$M launch_peer win --no-human --bots=5 --rounds=6 --phase-time=1 --race-time=60 --laps=1 \
	--test-totals=0:1000,1:1000,2:1000,3:1000,4:1000 --quit-after=100
TEST_SCENE=$M launch_peer one --no-human --bots=5 --rounds=2 --phase-time=1 --race-time=60 --laps=1 \
	--test-totals=0:1000 --quit-after=200
TEST_SCENE=$M launch_peer nocap --no-human --bots=5 --phase-time=1 --quit-after=60
TEST_SCENE=res://game/match/tests/match_rules_test.tscn launch_peer rules
L=res://game/lobby/main.tscn
TEST_SCENE=$L launch_peer host --host --name=Host --lobby-autostart=2 --rounds=2 --phase-time=3 \
	"--discovery-port=$((PORT + 1))" --quit-after=90
wait_log host '\[Net\] Hosting' 15 || exit 1
TEST_SCENE=$L launch_peer client --join=127.0.0.1 --name=C1 --auto-ready "--discovery-port=$((PORT + 1))" --quit-after=90
client_pid=${pids[$((${#pids[@]} - 1))]}
fail=0
wait_log host '\[Game\] PHASE draft 2' 60 || fail=1
kill "$client_pid" 2>/dev/null
for p in full catchup win one host; do wait_log "$p" '\[Game\] MATCH FINISHED' 160 || fail=1; done
sleep 0.5; cleanup_peers; sleep 0.5

# (1) full match
seq=$(grep -E '^\[Game\] PHASE ' "$OUT/full.log" | awk '{print $3 $4}' | tr '\n' ' ')
want=""; for r in 1 2 3 4 5 6; do want+="draft$r build$r race$r score$r "; done
[ "$seq" = "$want" ] && echo "  ok   24 phases in order" || { echo "  FAIL phases: $seq"; fail=1; }
n_deal=$(grep -cE '^\[Draft\] DEAL [0-4] [a-z_]+,[a-z_]+,[a-z_]+ ' "$OUT/full.log")
n_keep=$(grep -cE '^\[Draft\] KEEP [0-4] [a-z_]+' "$OUT/full.log")
[ "$n_deal" = 30 ] && [ "$n_keep" = 30 ] && echo "  ok   30 deals of 3, 30 keeps of 1" \
	|| { echo "  FAIL deals=$n_deal keeps=$n_keep (want 30/30)"; fail=1; }
grep -q 'GRAND CIRCUS' "$OUT/full.log" && { echo "  FAIL Grand Circus still exists"; fail=1; }
[ "$(grep -c '^\[Game\] RESULT ' "$OUT/full.log")" = 5 ] && echo "  ok   5 results" || { echo "  FAIL results"; fail=1; }
# Build uses the kept card (free_build off): every bot places exactly its 1 card.
[ "$(grep -c '^\[Build\] BOT [0-4] placed 1$' "$OUT/full.log")" -ge 25 ] && echo "  ok   bots placed their kept card" \
	|| { echo "  FAIL bots did not place their kept card"; grep '^\[Build\] BOT' "$OUT/full.log" | head; fail=1; }

# (2) catch-up from round 2: slot 1 last, slot 0 leader
best=$(sed -n 's/^\[Draft\] CATCHUP .*best_rarity=\([0-9]\).*/\1/p' "$OUT/catchup.log" | head -1)
[ -n "$best" ] || { echo "  FAIL no CATCHUP line"; fail=1; best=9; }
r1=$(awk '/^\[Game\] PHASE draft 1/{f=1} /^\[Game\] PHASE build 1/{f=0} f && /^\[Draft\] DEAL/' "$OUT/catchup.log")
echo "$r1" | grep -qE ' (leader|last)$' && { echo "  FAIL catch-up in round 1"; fail=1; }
for r in 2 3; do
	d=$(awk -v r=$r '$0 ~ "^\\[Game\\] PHASE draft " r {f=1} $0 ~ "^\\[Game\\] PHASE build " r {f=0} f && /^\[Draft\] DEAL/' "$OUT/catchup.log")
	echo "$d" | grep -E '^\[Draft\] DEAL 1 .* last$' | grep -qE "rarity=([0-9],)*$best" \
		&& echo "  ok   round $r: last place got rarity $best" || { echo "  FAIL round $r last: $d"; fail=1; }
	echo "$d" | grep -qE '^\[Draft\] DEAL 0 .* rarity=0,0,0 leader$' \
		&& echo "  ok   round $r: leader only commons" || { echo "  FAIL round $r leader: $d"; fail=1; }
done

# (3) C16: all at 1000, first finisher of race 1 wins and the match ends after round 1.
first=$(sed -n 's/^\[Race\] FINISH \([0-9]\) 1 .*/\1/p' "$OUT/win.log" | head -1)
[ -n "$first" ] && assert_log win "^\[Game\] WIN slot $first score (1[0-9]{3})" || { echo "  FAIL no WIN for first finisher '$first'"; fail=1; }
grep -q '^\[Game\] PHASE draft 2' "$OUT/win.log" && { echo "  FAIL match went on after the win"; fail=1; }
assert_log win '^\[Game\] MATCH POINT slot 0' || fail=1
# slot 0 alone at 1000: WIN iff it was 1st in race 1 (else the match goes on to round 2, capped by --rounds=2).
first1=$(sed -n 's/^\[Race\] FINISH \([0-9]\) 1 .*/\1/p' "$OUT/one.log" | head -1)
if [ "$first1" = 0 ]; then
	assert_log one '^\[Game\] WIN slot 0 ' || fail=1
	grep -q '^\[Game\] PHASE draft 2' "$OUT/one.log" && { echo "  FAIL went on after slot 0 won"; fail=1; }
else
	grep -q '^\[Game\] WIN' "$OUT/one.log" && { echo "  FAIL WIN although slot 0 was not 1st ($first1)"; fail=1; } || echo "  ok   at 1000 but not 1st -> no win"
	assert_log one '^\[Game\] PHASE draft 2' || fail=1
fi
# (5) no round cap
assert_log nocap '^\[Game\] PHASE draft 7' || fail=1
grep -q 'MATCH FINISHED' "$OUT/nocap.log" && { echo "  FAIL uncapped match finished"; fail=1; }
assert_log rules '^\[TEST\] MATCH RULES PASSED' || fail=1

# (4) host + client, client dropout
hseq=$(grep -E '^\[Game\] PHASE ' "$OUT/host.log" | awk '{print $3 $4}' | tr '\n' ' ')
cseq=$(grep -E '^\[Game\] PHASE ' "$OUT/client.log" | awk '{print $3 $4}' | tr '\n' ' ')
[ -n "$cseq" ] && [ "${hseq#"$cseq"}" != "$hseq" ] && echo "  ok   client phases match host: $cseq" \
	|| { echo "  FAIL client '$cseq' vs host '$hseq'"; fail=1; }
assert_log client '^\[Game\] PHASE draft 2' || fail=1
assert_log host '^\[Game\] DROPOUT slot 1 -> bot' || fail=1
assert_log host '^\[Draft\] KEEP 1 ' || fail=1
assert_log host '^\[Game\] PHASE score 2' || fail=1
if grep -En 'SCRIPT ERROR|Parse Error' "$OUT"/*.log; then fail=1; fi
if [ $fail -eq 0 ]; then echo "MATCH TEST PASSED"; else echo "MATCH TEST FAILED (see $OUT)"; fi
exit $fail
