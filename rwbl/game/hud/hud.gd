class_name Hud
extends CanvasLayer
## In-race HUD (lap, position, stamina, ammo, phase timer) + draft cards UI (DESIGN §3, §4). Owner: C14.
## C02 STUB: one label with phase, round and time left.
## NET: local only; reads MatchMode, RaceController, the local Chariot and Draft.
## Public API: match_setup(m).

var _m: MatchMode
var _label: Label


## Called by MatchMode.setup() on every peer.
func match_setup(m: MatchMode) -> void:
	_m = m
	_label = Label.new()
	_label.position = Vector2(16, 12)
	add_child(_label)


func _process(_delta: float) -> void:
	if _m == null:
		return
	_label.text = "Round %d/%d · %s · %ds" % [_m.round_index, int(_m.rules.get("rounds", 0)),
		Phase.name_of(_m.phase), int(ceilf(_m.phase_time_left()))]
