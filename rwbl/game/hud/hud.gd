class_name Hud
extends CanvasLayer
## In-race HUD (lap, position, stamina, wheels, ammo, phase timer, countdown), the draft card screen, and the
## Build-phase restyle (DESIGN §3, §4, §5.5). Owner: C14.
## Look: `hud_theme.tres` (one theme resource, big outlined text), player colours from `PlayerInfo.color`.
## NET: local only. Reads MatchMode, RaceController, the local Chariot (ChariotSync) and Draft; the only thing it
##   sends is Draft.submit_pick() when the local player confirms a card.
## Public API: match_setup(m); view setters used by the match and by `tests/hud_preview.tscn` with fake data:
##   show_race(d), show_draft(cards, picked, frac_left, status), show_phase(text, secs), hide_all(),
##   style_build_ui(ui), texts() -> Dictionary (what is on screen, for tests); signal pick_confirmed(index).
## Logs: `[HUD] DRAFT show slot ids`, `[HUD] PICK index id`.

## Local player pressed Confirm on card `index` (0..2). Fires before Draft.submit_pick() is called.
signal pick_confirmed(index: int)

const THEME_RES := preload("res://game/hud/hud_theme.tres")
const RARITY_COLORS: Array[Color] = [Color(0.85, 0.85, 0.85), Color(0.35, 0.65, 1.0), Color(1.0, 0.78, 0.2)]
const RARITY_NAMES: Array[String] = ["Common", "Uncommon", "Rare"]
# FIX(C19, Claude): ItemDef.Category gained PIECE (track pieces); without it the draft card indexes out of range.
const CATEGORY_NAMES: Array[String] = ["Terrain", "Obstacle", "Roman", "Pickup", "Wildcard", "Track piece"]
const CATEGORY_COLORS: Array[Color] = [Color(0.8, 0.6, 0.35), Color(0.75, 0.75, 0.8), Color(0.9, 0.35, 0.3),
	Color(0.4, 0.85, 0.5), Color(0.75, 0.45, 0.9), Color(0.95, 0.85, 0.55)]
const WHEEL_OK := Color(0.35, 0.85, 0.4)
const WHEEL_BROKEN := Color(0.95, 0.15, 0.12)
const GO_SHOW := 1.0 # TUNE: s the "GO!" stays up

var _m: MatchMode
var _root: Control
# race
var _race_box: Control
var _lap_label: Label
var _place_label: Label
var _stam_bar: ProgressBar
var _stam_label: Label
var _wheel_l: ColorRect
var _wheel_r: ColorRect
var _ammo_label: Label
var _count_label: Label
# phase strip (every phase)
var _phase_label: Label
var _timer_label: Label
# draft
var _draft_box: Control
var _draft_title: Label
var _card_row: HBoxContainer
var _confirm: Button
var _draft_status: Label
var _draft_timer: ProgressBar
var _cards: Array[StringName] = []
var _card_panels: Array[PanelContainer] = []
var _cards_key := ""
var _sel := -1
var _picked := false
var _phase_total := 0.0
var _phase_seen := -1
var _go_left := 0.0
var _was_racing := false
var _styled_build := false


## Called by MatchMode.setup() on every peer.
func match_setup(m: MatchMode) -> void:
	_m = m
	if _root == null:
		layer = 10
		_build_widgets()
	GameEvents.phase_changed.connect(_on_phase_changed)


func _ready() -> void:
	if _root == null: # standalone use (preview scene) builds on demand
		layer = 10
		_build_widgets()


func _build_widgets() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.theme = THEME_RES
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_race()
	_build_draft()
	_build_phase_strip() # last = drawn above the draft dimmer
	hide_all()


func _label(text: String, size: int, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align as HorizontalAlignment
	l.add_theme_font_size_override(&"font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_phase_strip() -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.offset_top = 10
	_root.add_child(box)
	_phase_label = _label("", 34, HORIZONTAL_ALIGNMENT_CENTER)
	_timer_label = _label("", 56, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_phase_label)
	box.add_child(_timer_label)


func _build_race() -> void:
	_race_box = Control.new()
	_race_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_race_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_race_box)
	var tl := VBoxContainer.new()
	tl.position = Vector2(28, 20)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_race_box.add_child(tl)
	_place_label = _label("1st", 120)
	_lap_label = _label("LAP 1/1", 48)
	tl.add_child(_place_label)
	tl.add_child(_lap_label)
	# bottom centre: stamina bar, wheels, ammo
	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -24
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_race_box.add_child(bottom)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 24)
	bottom.add_child(row)
	var sbox := VBoxContainer.new()
	row.add_child(sbox)
	_stam_label = _label("WHIP", 24)
	sbox.add_child(_stam_label)
	_stam_bar = ProgressBar.new()
	_stam_bar.custom_minimum_size = Vector2(420, 30)
	_stam_bar.max_value = 1.0
	_stam_bar.step = 0.001
	_stam_bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.25, 0.22, 0.2)
	bg.set_corner_radius_all(6)
	_stam_bar.add_theme_stylebox_override(&"background", bg)
	sbox.add_child(_stam_bar)
	var wbox := VBoxContainer.new()
	row.add_child(wbox)
	wbox.add_child(_label("WHEELS", 24))
	var wrow := HBoxContainer.new()
	wbox.add_child(wrow)
	_wheel_l = _wheel_icon(wrow)
	_wheel_r = _wheel_icon(wrow)
	_ammo_label = _label("SPEARS 0", 32)
	_ammo_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_ammo_label)
	_count_label = _label("", 220, HORIZONTAL_ALIGNMENT_CENTER)
	_count_label.set_anchors_preset(Control.PRESET_CENTER)
	_count_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_count_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_count_label.add_theme_constant_override(&"outline_size", 20)
	_race_box.add_child(_count_label)


func _wheel_icon(parent: Control) -> ColorRect:
	var c := ColorRect.new()
	c.custom_minimum_size = Vector2(44, 44)
	c.color = WHEEL_OK
	parent.add_child(c)
	return c


func _build_draft() -> void:
	_draft_box = Control.new()
	_draft_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_draft_box)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.02, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draft_box.add_child(dim)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_top = 140 # below the phase strip
	col.offset_bottom = -40
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override(&"separation", 18)
	_draft_box.add_child(col)
	_draft_title = _label("Pick 1 card to keep", 44, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_draft_title)
	_card_row = HBoxContainer.new()
	_card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_row.add_theme_constant_override(&"separation", 28)
	col.add_child(_card_row)
	_confirm = Button.new()
	_confirm.text = "Confirm"
	_confirm.custom_minimum_size = Vector2(260, 64)
	_confirm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_confirm.add_theme_font_size_override(&"font_size", 34)
	_confirm.pressed.connect(_on_confirm)
	col.add_child(_confirm)
	_draft_status = _label("", 30, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_draft_status)
	_draft_timer = ProgressBar.new()
	_draft_timer.custom_minimum_size = Vector2(700, 22)
	_draft_timer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_draft_timer.max_value = 1.0
	_draft_timer.step = 0.001
	_draft_timer.show_percentage = false
	col.add_child(_draft_timer)


# ---- view setters (also used by the preview with fake data) --------------------------------------------------

## Hide every screen (phase strip stays managed by show_phase).
func hide_all() -> void:
	_race_box.visible = false
	_draft_box.visible = false


## Race HUD. Keys: to_go (m to the finish; C23, shown instead of lap/laps when present), lap, laps, place, stamina (0..1), wheels (ChariotSnapshot bits), ammo, color, countdown
## (seconds left, <= 0 hides), go (bool, show "GO!"), whip_cost (flash below it, default 0.01).
func show_race(d: Dictionary) -> void:
	_draft_box.visible = false
	_race_box.visible = true
	var col: Color = d.get("color", Color.WHITE)
	if d.has("to_go"): # C23: one run to the finish line, no laps
		_lap_label.text = "%d m TO GO" % int(ceilf(float(d["to_go"]))) if float(d["to_go"]) > 0.0 else "FINISHED"
	else:
		_lap_label.text = "LAP %d/%d" % [int(d.get("lap", 1)), int(d.get("laps", 1))]
	_place_label.text = ordinal(int(d.get("place", 1)))
	_place_label.add_theme_color_override(&"font_color", col.lightened(0.25))
	var st := float(d.get("stamina", 1.0))
	_stam_bar.value = st
	var cost := float(d.get("whip_cost", 0.01))
	var tired := st <= cost
	var flash := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.018)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1, 0.2 + 0.2 * flash, 0.15) if tired else (Color(1, 0.65, 0.2) if st < 0.35 else Color(0.95, 0.85, 0.3))
	_stam_bar.add_theme_stylebox_override(&"fill", fill)
	_stam_label.text = "TOO TIRED!" if tired else "WHIP"
	var wheels := int(d.get("wheels", 0))
	_wheel_l.color = WHEEL_BROKEN if wheels & ChariotSnapshot.WHEEL_LEFT else WHEEL_OK
	_wheel_r.color = WHEEL_BROKEN if wheels & ChariotSnapshot.WHEEL_RIGHT else WHEEL_OK
	_ammo_label.text = "SPEARS %d" % int(d.get("ammo", 0))
	var cd := float(d.get("countdown", 0.0))
	if cd > 0.0:
		_count_label.text = str(int(ceilf(cd)))
	elif bool(d.get("go", false)):
		_count_label.text = "GO!"
	else:
		_count_label.text = ""


## Draft screen for the local player. `cards` = ItemDef ids; `picked` locks the choice; frac_left 0..1.
func show_draft(cards: Array, picked: bool, frac_left: float, status: String = "") -> void:
	_race_box.visible = false
	_draft_box.visible = true
	var key := str(cards)
	if key != _cards_key:
		_cards_key = key
		_cards.assign(cards)
		_sel = -1
		_picked = false
		_rebuild_cards()
	if picked:
		_picked = true
	_draft_timer.value = clampf(frac_left, 0.0, 1.0)
	_confirm.visible = not _picked
	_confirm.disabled = _sel < 0
	_draft_title.text = "Card kept!" if _picked else "Pick 1 card to keep"
	_draft_status.text = status if status != "" else ("Waiting for others..." if _picked else "")
	_refresh_card_styles()


## Phase name + time left strip at the top ("" hides it).
func show_phase(text: String, secs: float) -> void:
	_phase_label.text = text
	_timer_label.text = "" if text == "" else str(int(ceilf(secs)))


## Restyle C08's BuildUI (hand panel, buttons, toast) with the HUD theme. Safe to call repeatedly.
func style_build_ui(ui: CanvasLayer) -> void:
	for c in ui.get_children():
		if c is Control:
			(c as Control).theme = THEME_RES


## What is on screen right now (tests grep it).
func texts() -> Dictionary:
	return {"lap": _lap_label.text.trim_prefix("LAP "), "place": _place_label.text, "ammo": _ammo_label.text,
		"count": _count_label.text, "phase": _phase_label.text, "timer": _timer_label.text,
		"stamina": _stam_label.text, "draft_cards": _card_panels.size(), "draft_visible": _draft_box.visible,
		"race_visible": _race_box.visible, "status": _draft_status.text}


## 1 -> "1st", 2 -> "2nd", 3 -> "3rd", 4 -> "4th"...
static func ordinal(n: int) -> String:
	if n % 100 >= 11 and n % 100 <= 13:
		return "%dth" % n
	match n % 10:
		1: return "%dst" % n
		2: return "%dnd" % n
		3: return "%drd" % n
	return "%dth" % n


# ---- draft cards ---------------------------------------------------------------------------------------------

func _rebuild_cards() -> void:
	for c in _card_row.get_children():
		c.queue_free()
	_card_panels.clear()
	for i in _cards.size():
		var d := ItemDB.get_def(_cards[i])
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(330, 300)
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		p.gui_input.connect(_on_card_input.bind(i))
		var v := VBoxContainer.new()
		v.add_theme_constant_override(&"separation", 10)
		p.add_child(v)
		var cat := _label("", 24, HORIZONTAL_ALIGNMENT_CENTER)
		var nm := _label(String(_cards[i]), 40, HORIZONTAL_ALIGNMENT_CENTER)
		var rar := _label("", 26, HORIZONTAL_ALIGNMENT_CENTER)
		var desc := _label("", 26, HORIZONTAL_ALIGNMENT_CENTER)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if d:
			cat.text = CATEGORY_NAMES[d.category].to_upper()
			cat.add_theme_color_override(&"font_color", CATEGORY_COLORS[d.category])
			nm.text = d.display_name if d.display_name != "" else String(d.id)
			rar.text = RARITY_NAMES[d.rarity]
			rar.add_theme_color_override(&"font_color", RARITY_COLORS[d.rarity])
			desc.text = d.description
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(cat)
		v.add_child(nm)
		if d and d.icon:
			var tr := TextureRect.new()
			tr.texture = d.icon
			tr.custom_minimum_size = Vector2(0, 120)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(tr)
		v.add_child(rar)
		v.add_child(desc)
		_card_row.add_child(p)
		_card_panels.append(p)
	_refresh_card_styles()


func _refresh_card_styles() -> void:
	for i in _card_panels.size():
		var d := ItemDB.get_def(_cards[i])
		var col := RARITY_COLORS[d.rarity] if d else Color.WHITE
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(12)
		sb.set_content_margin_all(16)
		var chosen := i == _sel
		sb.bg_color = Color(0.2, 0.15, 0.08, 0.96) if chosen else Color(0.1, 0.08, 0.06, 0.92)
		sb.set_border_width_all(8 if chosen else 3)
		sb.border_color = col if chosen else col.darkened(0.35)
		_card_panels[i].add_theme_stylebox_override(&"panel", sb)
		_card_panels[i].modulate = Color(1, 1, 1, 0.55) if _picked and not chosen else Color.WHITE


func _on_card_input(event: InputEvent, index: int) -> void:
	if _picked:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_sel = index
		_confirm.disabled = false
		_refresh_card_styles()


func _on_confirm() -> void:
	if _sel < 0 or _picked:
		return
	_picked = true
	print("[HUD] PICK %d %s" % [_sel, _cards[_sel]])
	pick_confirmed.emit(_sel)
	if _m:
		var idx: Array[int] = [_sel]
		_m.draft.submit_pick(idx)
	_confirm.visible = false
	_refresh_card_styles()


# ---- live wiring ---------------------------------------------------------------------------------------------

func _on_phase_changed(phase: int, _round: int) -> void:
	_phase_seen = phase
	_phase_total = maxf(_m.phase_time_left(), 0.01)
	_go_left = 0.0
	_was_racing = false
	_cards_key = ""
	_picked = false
	_sel = -1


func _process(delta: float) -> void:
	if _m == null:
		return
	var phase := _m.phase
	if phase == Phase.NONE or phase == Phase.MATCH_OVER:
		show_phase("", 0.0)
		hide_all()
		return
	var left := _m.phase_time_left()
	var title := "Round %d · %s" % [_m.round_index, Phase.name_of(phase).capitalize()]
	var mp := _m.match_point_slots()
	if not mp.is_empty():
		var names: Array[String] = []
		for s in mp:
			var pl := _m.get_player(s)
			names.append(pl.name if pl else str(s))
		title += " · MATCH POINT: " + ", ".join(names)
	show_phase(title, left)
	var slot := _m.local_slot()
	match phase:
		Phase.DRAFT:
			_update_draft(slot, left)
		Phase.RACE:
			_update_race(slot, delta)
		Phase.BUILD:
			hide_all()
			_restyle_build()
		_:
			hide_all()


func _update_draft(slot: int, left: float) -> void:
	var cards := _m.draft.cards_of(slot) if slot >= 0 else ([] as Array[StringName])
	if cards.is_empty():
		hide_all()
		return
	var picked := _picked or _m.draft.has_picked(slot)
	var status := ""
	if picked and multiplayer.is_server():
		var n := 0
		for p in _m.players:
			if _m.draft.has_picked(p.slot):
				n += 1
		status = "Waiting for others... %d/%d kept" % [n, _m.players.size()]
	if str(cards) != _cards_key:
		print("[HUD] DRAFT show slot %d %s" % [slot, cards])
	show_draft(cards, picked, left / _phase_total, status)


func _update_race(slot: int, delta: float) -> void:
	var race := _m.race
	var d := {"laps": int(_m.rules.get("laps", 1)), "countdown": race.countdown_left()}
	if slot < 0:
		hide_all()
		return
	var info := _m.get_player(slot)
	d["color"] = info.color if info else Color.WHITE
	d["lap"] = race.lap_of(slot)
	d["to_go"] = race.to_go(slot) # C23: replaces the lap counter
	d["place"] = race.place_of(slot)
	d["ammo"] = 0 # TODO(C15): spear ammo once the ballista/spear items exist (wave 4)
	var ch := _m.chariot_sync.get_chariot(slot) as Chariot
	if ch:
		d["stamina"] = ch.stamina
		d["wheels"] = ch.wheel_state
		d["whip_cost"] = 0.01
	var racing := race.is_racing()
	if racing and not _was_racing:
		_go_left = GO_SHOW
	_was_racing = racing
	_go_left = maxf(0.0, _go_left - delta)
	d["go"] = _go_left > 0.0
	show_race(d)


func _restyle_build() -> void:
	if _styled_build:
		return
	for c in _m.build.get_children():
		if c is BuildUI:
			style_build_ui(c)
			_styled_build = true
