extends Node
## C14 preview: feeds the HUD fake data and cycles race, countdown, tired/broken, draft and build states.
## Headless: prints `[TEST] HUD ...` lines read back from what the labels show. With `--screenshot=PATH` (needs a
## window, not --headless) it also saves PATH_race.png, PATH_draft.png, PATH_build.png at 1920x1080.
## Owner: C14. NET: none.

@onready var hud: Hud = $Hud
var _fail := false


func _ready() -> void:
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot="):
			shot = a.trim_prefix("--screenshot=")
	await _run(shot)
	print("[TEST] HUD %s" % ("FAILED" if _fail else "PASSED"))
	get_tree().quit(1 if _fail else 0)


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fail = true
		print("[TEST] FAIL HUD %s" % what)


func _frame(n: int = 3) -> void:
	for i in n:
		await get_tree().process_frame


func _save(shot: String, name: String) -> void:
	if shot == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [shot, name])


func _run(shot: String) -> void:
	get_window().size = Vector2i(1920, 1080)
	var col := PlayerInfo.color_for_slot(1)
	# race, countdown
	hud.show_phase("Round 2/6 · Race", 84.0)
	hud.show_race({"lap": 1, "laps": 3, "place": 3, "stamina": 1.0, "color": col, "countdown": 2.4})
	await _frame()
	var t := hud.texts()
	print("[TEST] HUD countdown=%s" % t.count)
	_expect(t.count == "3", "countdown shows 3")
	# race, lap 2 of 3, leading, one wheel broken, spent horses
	hud.show_race({"lap": 2, "laps": 3, "place": 1, "stamina": 0.0, "wheels": ChariotSnapshot.WHEEL_LEFT,
		"color": col, "ammo": 0, "go": true})
	await _frame()
	t = hud.texts()
	print("[TEST] HUD lap=%s pos=%s" % [t.lap, t.place])
	_expect(t.lap == "2/3" and t.place == "1st", "race lap/place text")
	_expect(t.stamina == "TOO TIRED!" and t.count == "GO!", "tired + GO text")
	await _save(shot, "race")
	# ordinals
	_expect(Hud.ordinal(2) == "2nd" and Hud.ordinal(5) == "5th" and Hud.ordinal(3) == "3rd", "ordinals")
	# draft
	hud.show_phase("Round 2/6 · Draft", 7.0)
	var ids: Array = []
	for d in ItemDB.all_defs():
		ids.append(d.id)
		if ids.size() == 3:
			break
	hud.pick_confirmed.connect(func(i: int) -> void: print("[TEST] HUD picked=%d" % i))
	hud.show_draft(ids, false, 0.7)
	await _frame()
	t = hud.texts()
	print("[TEST] HUD draft cards=%d" % t.draft_cards)
	_expect(t.draft_cards == 3 and t.draft_visible and not t.race_visible, "draft shows 3 cards")
	hud._on_card_input(_click(), 1)
	await _frame()
	hud.show_draft(ids, false, 0.6)
	await _save(shot, "draft")
	hud._on_confirm()
	hud.show_draft(ids, true, 0.5)
	await _frame()
	t = hud.texts()
	_expect(t.status == "Waiting for others...", "waiting text after confirm")
	# build restyle: a stand-in for C08's BuildUI (panel + buttons + toast)
	hud.hide_all()
	hud.show_phase("Round 2/6 · Build", 20.0)
	var fake := CanvasLayer.new()
	add_child(fake)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 120)
	fake.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	for text in ["Your items · budget 3/4", "Oil Slick (1)", "Column (2)", "Done placing"]:
		var b: Control = Button.new() if text.ends_with(")") or text.begins_with("Done") else Label.new()
		b.set("text", text)
		box.add_child(b)
	var toast := Label.new()
	toast.text = "Oil Slick: placed"
	toast.position = Vector2(800, 120)
	fake.add_child(toast)
	hud.style_build_ui(fake)
	await _frame()
	_expect(panel.theme == Hud.THEME_RES, "build panel themed")
	print("[TEST] HUD build styled")
	await _save(shot, "build")


func _click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.pressed = true
	e.button_index = MOUSE_BUTTON_LEFT
	return e
