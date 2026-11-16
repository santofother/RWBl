class_name MatchTuning
extends Resource
## Match rules and draft numbers (DESIGN §3, §5.5, §6 win). Owner: C09. Default: `match/default_tuning.tres`,
## registered with TuningPanel (F2) as "Match" by MatchMode. The lobby's / CLI's `rules` dict still overrides
## the rule fields for one match (see MatchMode.setup()).
## NET: host only (the host deals and runs the phase loop); clients get everything by RPC.
## Public API: exported fields, `to_rules()`, `rarity_weight(rarity)`.
# CONTRACT: tuning resources use @export_range so TuningPanel can build sliders.

@export_group("Rounds")
@export_range(0, 50) var rounds := 0 # TUNE: 0 = rounds repeat until someone wins; N = test cap
@export_range(1, 5) var laps := 1 # TUNE: laps per race
@export_range(100, 5000, 50) var win_score := 1000 # TUNE: finish 1st with a total >= this to win
@export_group("Phase seconds")
@export_range(3.0, 60.0) var draft_time := 10.0 # TUNE: s, ends early once everyone picked
@export_range(5.0, 90.0) var build_time := 25.0 # TUNE: s, ends early once everyone placed
@export_range(20.0, 240.0) var race_time := 90.0 # TUNE: s, ends early 3 s after the race is over
@export_range(3.0, 30.0) var score_time := 10.0 # TUNE: s
@export_range(0.0, 60.0) var race_end_after_humans := 8.0 # TUNE: s after every human finished, the race ends (bots still out there are placed by progress). 0 = off (C24)
@export_group("Draft")
@export_range(1, 5) var cards_per_hand := 3 # TUNE: cards dealt per player per round
@export_range(0.0, 20.0) var weight_common := 6.0 # TUNE: relative draw weight of COMMON cards
@export_range(0.0, 20.0) var weight_uncommon := 3.0 # TUNE: relative draw weight of UNCOMMON cards
@export_range(0.0, 20.0) var weight_rare := 1.0 # TUNE: relative draw weight of RARE cards
@export_group("Catch-up")
@export_range(1, 12) var catchup_from_round := 2 # TUNE: catch-up dealing starts this round (round 1: nobody has points)
@export_range(0, 3) var last_place_rares := 1 # TUNE: last place gets at least this many cards of the best rarity
@export_range(0, 1) var leader_commons_only := 1 # TUNE: 1 = the leader draws only COMMON cards


## The rule fields as a MatchMode rules dict (keys of the rules CONTRACT).
func to_rules() -> Dictionary:
	return {"rounds": rounds, "laps": laps, "win_score": win_score, "draft_time": draft_time,
		"build_time": build_time, "race_time": race_time, "score_time": score_time}


## Draw weight for an ItemDef.Rarity value.
func rarity_weight(rarity: int) -> float:
	match rarity:
		ItemDef.Rarity.COMMON: return weight_common
		ItemDef.Rarity.UNCOMMON: return weight_uncommon
		_: return weight_rare
