class_name ScoreScreen
extends CanvasLayer
## Score screen shown during Phase.SCORE. C18: an animated vertical bar chart (`ScoreBars`) climbing toward the
## win line; the C11 table (one row per player: name, colour, finish / traps / kills / bonus, round total, match
## total, sorted by match total) is still built and toggles with Tab. Owner: C11, reworked by C18.
## NET: local only. Reads Scoring (breakdown + totals) after GameEvents.round_scored.
## Public API: match_setup(m, scoring), show_scores(players, breakdown, totals, win_score, winner_slot, budget),
##   rows() -> Array, bars() -> Array (for tests), skip(), toggle_table(). Any key / click skips, Tab = table.

const THEME_RES := preload("res://game/hud/hud_theme.tres")
const ANIM_DEFAULT := preload("res://game/scoring/default_score_anim.tres")
const HEADERS: Array[String] = ["", "Player", "Finish", "Traps", "Kills", "Bonus", "Round", "Total"]

var _m: MatchMode
var _scoring: Scoring
var _root: Control
var _grid: GridContainer
var _title: Label
var _rows: Array = []
var _bars: ScoreBars
var _table_panel: PanelContainer
var _hint: Label
var _tuning: ScoreAnimTuning = ANIM_DEFAULT
var _scored_round := -1
var _shown_key := 0
var _shown_ms := 0


## Called by Scoring.match_setup() on every peer.
func match_setup(m: MatchMode, scoring: Scoring) -> void:
	_m = m
	_scoring = scoring
	GameEvents.phase_changed.connect(_on_phase_changed)
	GameEvents.round_scored.connect(_on_scored)
	var panel := get_node_or_null(^"/root/TuningPanel")
	if panel:
		panel.register(_tuning, "Score anim")


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
	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 44)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 14
	_title.offset_bottom = 70
	_root.add_child(_title)
	_bars = ScoreBars.new()
	_bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bars.offset_top = 74
	_bars.offset_bottom = -44
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bars)
	_hint = Label.new()
	_hint.text = "Any key: skip   ·   Tab: table"
	_hint.add_theme_font_size_override(&"font_size", 20)
	_hint.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.6))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -38
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_hint)
	_table_panel = PanelContainer.new()
	_table_panel.set_anchors_preset(Control.PRESET_CENTER)
	_table_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_table_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_table_panel.visible = false
	_root.add_child(_table_panel)
	_grid = GridContainer.new()
	_grid.columns = HEADERS.size()
	_grid.add_theme_constant_override(&"h_separation", 28)
	_table_panel.add_child(_grid)
	visible = false


## Fill the table and start the bar animation. `breakdown` = Scoring.get_breakdown(), `totals` = totals after
## the round. `win_score` / `winner_slot` / `budget` (seconds the animation must fit in) default to the match's.
func show_scores(players: Array[PlayerInfo], breakdown: Dictionary, totals: Dictionary, win_score := -1,
		winner_slot := -2, budget := -1.0) -> void:
	var key := hash([breakdown, totals])
	if visible and key == _shown_key:
		return # WHY: phase change and round_scored both ask; don't restart a running show
	_shown_key = key
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
	if win_score < 0:
		win_score = int(_m.rules.get("win_score", 1000)) if _m else 1000
	if winner_slot == -2:
		winner_slot = _match_winner(players, breakdown, totals, win_score)
	if budget < 0.0:
		budget = _m.phase_time_left() if _m else 10.0
	_table_panel.visible = false
	_bars.visible = true
	_bars.setup(players, breakdown, totals, win_score, winner_slot, _tuning)
	_bars.play(budget)
	_shown_ms = Time.get_ticks_msec()
	visible = true


## Rows as shown: [slot, name, finish, traps, kills, bonus, round, total] strings, sorted by total.
func rows() -> Array:
	return _rows.duplicate(true)


## The bars: one per player in final order, {slot, from, to, chunks {finish, kills, traps, bonus}} (for tests).
func bars() -> Array:
	return _bars.bars() if _bars else []


## true once the bar animation ended or was skipped.
func bars_done() -> bool:
	return _bars == null or _bars.is_done()


## Jump the bars to their final state.
func skip() -> void:
	if _bars:
		_bars.skip()


## Tab: swap between the bars and the C11 breakdown table.
func toggle_table() -> void:
	_table_panel.visible = not _table_panel.visible
	_bars.visible = not _table_panel.visible


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_TAB:
			toggle_table()
		elif Time.get_ticks_msec() - _shown_ms > 400: # WHY: ignore keys still being mashed at the finish line
			skip()
	elif event is InputEventMouseButton and event.pressed and Time.get_ticks_msec() - _shown_ms > 400:
		skip()


# Slot that wins the match this round, or -1. The win check uses totals BEFORE the race (C16).
func _match_winner(players: Array[PlayerInfo], breakdown: Dictionary, totals: Dictionary, win_score: int) -> int:
	if _m == null or _m.race == null:
		return -1
	var pre: Dictionary = {}
	for p in players:
		pre[p.slot] = int(totals.get(p.slot, 0)) - int((breakdown.get(p.slot, {}) as Dictionary).get("total", 0))
	return MatchMode.winner_slot(_m.race.finish_order(), pre, win_score)


func _cell(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", 30)
	l.add_theme_color_override(&"font_color", color)
	return l


func _signed(v: Variant) -> String:
	var i := int(v)
	return "+%d" % i if i > 0 else str(i)


func _totals_now() -> Dictionary:
	return _m.totals() if _m else _scoring.get_totals() # WHY: m.totals() adds --test-totals


func _on_phase_changed(phase: int, round_no: int) -> void:
	if phase == Phase.SCORE:
		# WHY: only show a breakdown that belongs to this round; otherwise wait for round_scored.
		if _scoring and _scored_round == round_no and not _scoring.get_breakdown().is_empty():
			show_scores(_m.players, _scoring.get_breakdown(), _totals_now())
	else:
		visible = false
		_shown_key = 0
		if _bars:
			_bars.abort()


func _on_scored(_pts: Dictionary, _tot: Dictionary) -> void:
	if _m == null:
		return
	_scored_round = _m.round_index
	if _m.phase == Phase.SCORE:
		show_scores(_m.players, _scoring.get_breakdown(), _totals_now())
