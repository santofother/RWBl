class_name ScoreScreen
extends CanvasLayer
## Score screen shown during Phase.SCORE: one row per player (name, colour, finish / traps / kills / bonus, round
## total, match total), sorted by match total. Owner: C11.
## NET: local only. Reads Scoring (breakdown + totals) after GameEvents.round_scored.
## Public API: match_setup(m, scoring), show_scores(players, breakdown, totals), rows() -> Array (for tests).

const THEME_RES := preload("res://game/hud/hud_theme.tres")
const HEADERS: Array[String] = ["", "Player", "Finish", "Traps", "Kills", "Bonus", "Round", "Total"]

var _m: MatchMode
var _scoring: Scoring
var _root: Control
var _grid: GridContainer
var _title: Label
var _rows: Array = []


## Called by Scoring.match_setup() on every peer.
func match_setup(m: MatchMode, scoring: Scoring) -> void:
	_m = m
	_scoring = scoring
	GameEvents.phase_changed.connect(_on_phase_changed)
	GameEvents.round_scored.connect(_on_scored)


func _ready() -> void:
	layer = 11
	_root = Control.new()
	_root.theme = THEME_RES
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 44)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_grid = GridContainer.new()
	_grid.columns = HEADERS.size()
	_grid.add_theme_constant_override(&"h_separation", 28)
	box.add_child(_grid)
	visible = false


## Fill and show the table. `breakdown` = Scoring.get_breakdown(), `totals` = Scoring.get_totals().
func show_scores(players: Array[PlayerInfo], breakdown: Dictionary, totals: Dictionary) -> void:
	for c in _grid.get_children():
		c.queue_free()
		_grid.remove_child(c)
	for h in HEADERS:
		_grid.add_child(_cell(h, Color(1, 0.85, 0.4)))
	var order: Array[PlayerInfo] = players.duplicate()
	order.sort_custom(func(a: PlayerInfo, b: PlayerInfo) -> bool:
		var ta := int(totals.get(a.slot, 0))
		var tb := int(totals.get(b.slot, 0))
		return ta > tb or (ta == tb and a.slot < b.slot))
	_rows.clear()
	for p in order:
		var b: Dictionary = breakdown.get(p.slot, {})
		var swatch := ColorRect.new()
		swatch.color = p.color
		swatch.custom_minimum_size = Vector2(22, 22)
		_grid.add_child(swatch)
		var vals: Array[String] = [p.name, _signed(b.get("finish", 0)), _signed(b.get("traps", 0)),
			_signed(b.get("kills", 0)), _signed(b.get("bonus", 0)), _signed(b.get("total", 0)),
			str(int(totals.get(p.slot, 0)))]
		for v in vals:
			_grid.add_child(_cell(v, Color.WHITE))
		_rows.append([p.slot] + vals)
	if _m:
		_title.text = "Round %d scores" % _m.round_index
	visible = true


## Rows as shown: [slot, name, finish, traps, kills, bonus, round, total] strings, sorted.
func rows() -> Array:
	return _rows.duplicate(true)


func _cell(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", 30)
	l.add_theme_color_override(&"font_color", color)
	return l


func _signed(v: Variant) -> String:
	var i := int(v)
	return "+%d" % i if i > 0 else str(i)


func _on_phase_changed(phase: int, _round: int) -> void:
	if phase == Phase.SCORE:
		if _scoring and not _scoring.get_breakdown().is_empty():
			show_scores(_m.players, _scoring.get_breakdown(), _scoring.get_totals())
	else:
		visible = false


func _on_scored(_pts: Dictionary, _tot: Dictionary) -> void:
	if _m and _m.phase == Phase.SCORE:
		show_scores(_m.players, _scoring.get_breakdown(), _scoring.get_totals())
