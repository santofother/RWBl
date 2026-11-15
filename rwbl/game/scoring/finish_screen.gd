class_name FinishScreen
extends CanvasLayer
## Personal finish card: when the local player crosses the finish line it shows "VICTORY!" / "FINISHED!", the
## place, race time, place points and the bonus earned so far (laps, clean laps, kills, traps), then "waiting for
## the others" with the race time left. Hidden when the Score phase starts (ScoreScreen shows the full table).
## Owner: C11 (added by C12 on the user's request).
## NET: local only. Fed by Scoring.finish_card (host RPC on every peer).
## Public API: match_setup(m, scoring), show_card(place, time, finish_pts, bonus_pts), texts() -> Dictionary.

const THEME_RES := preload("res://game/hud/hud_theme.tres")
const GOLD := Color(1.0, 0.82, 0.25)

var _m: MatchMode
var _root: Control
var _title: Label
var _place: Label
var _points: Label
var _wait: Label


## Called by Scoring.match_setup() on every peer.
func match_setup(m: MatchMode, scoring: Scoring) -> void:
	_m = m
	scoring.finish_card.connect(_on_card)
	GameEvents.phase_changed.connect(func(_p: int, _r: int) -> void: visible = false)


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.theme = THEME_RES
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	panel.add_child(box)
	_title = _label(72, GOLD)
	_place = _label(44, Color.WHITE)
	_points = _label(34, Color.WHITE)
	_wait = _label(26, Color(0.8, 0.8, 0.8))
	for l in [_title, _place, _points, _wait]:
		box.add_child(l)
	visible = false


func _process(_delta: float) -> void:
	if visible and _m:
		_wait.text = "Waiting for the others... %d s" % ceili(maxf(0.0, _m.phase_time_left()))


## Fill and show the card.
func show_card(place: int, time: float, finish_pts: int, bonus_pts: int) -> void:
	_title.text = "VICTORY!" if place == 1 else "FINISHED!"
	_place.text = "%s place  ·  %.1f s" % [Hud.ordinal(place), time]
	_points.text = "+%d place   +%d bonus   = +%d" % [finish_pts, bonus_pts, finish_pts + bonus_pts]
	_wait.text = "Waiting for the others..."
	visible = true
	print("[Score] FINISH_CARD place=%d finish=%d bonus=%d" % [place, finish_pts, bonus_pts])


## What is on screen (tests).
func texts() -> Dictionary:
	return {"visible": visible, "title": _title.text, "place": _place.text, "points": _points.text}


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	return l


func _on_card(slot: int, place: int, time: float, finish_pts: int, bonus_pts: int) -> void:
	if _m and slot == _m.local_slot():
		show_card(place, time, finish_pts, bonus_pts)
