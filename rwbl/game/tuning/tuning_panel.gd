extends CanvasLayer
## F2 / ` tuning panel (autoload `TuningPanel`). Owner: C04. Lets the user tune any registered Resource live
## with sliders (one per `@export_range` property, grouped by `@export_group`) and save it.
## Save: run from the editor binary -> writes the .tres at its res:// path (commit it to keep the numbers).
## Exported build -> writes `user://tuning/<file>.tres`, which register() loads over the default next start.
## NET: local only. Edits on the host change the simulation; on clients they only change prediction.
## Public API: `register(res, title)`, `registered() -> Array`, `set_open(open)`, `is_open()`, `toggle()`,
##   `slider_count()`, `save_all()`, `save_resource(res)`, `save_path_for(res)`, `load_override(res)`,
##   `use_user_dir`.
# CONTRACT: every tuning resource (ChariotTuning, MatchTuning, ScoreTable, ...) calls register() once.

const USER_DIR := "user://tuning/"
const PANEL_WIDTH := 440.0

## Save to / load from `user://tuning/` instead of res://. Default: true in exported builds (no editor).
var use_user_dir := not OS.has_feature("editor")

var _entries: Array = [] # [{res, title}]
var _root: PanelContainer
var _list: VBoxContainer
var _status: Label
var _sliders := 0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS


## Add a resource to the panel (ignored if already registered). Loads the user:// override if there is one.
func register(res: Resource, title: String) -> void:
	for e: Dictionary in _entries:
		if e["res"] == res:
			return
	if use_user_dir:
		load_override(res)
	_entries.append({"res": res, "title": title})
	if is_open():
		_rebuild()


## Registered entries: [{res, title}].
func registered() -> Array:
	return _entries


## Show or hide the panel. Opening rebuilds the sliders from the current values.
func set_open(open: bool) -> void:
	if open:
		if _root == null:
			_build_ui()
		_rebuild()
	if _root:
		_root.visible = open


## True while the panel is shown.
func is_open() -> bool:
	return _root != null and _root.visible


## Open if closed, close if open (F2).
func toggle() -> void:
	set_open(not is_open())


## Sliders in the panel right now (tests).
func slider_count() -> int:
	return _sliders


## Save every registered resource. Returns the paths written.
func save_all() -> PackedStringArray:
	var out := PackedStringArray()
	for e: Dictionary in _entries:
		var p := save_resource(e["res"])
		if p != "":
			out.append(p)
	if _status:
		_status.text = "Saved: " + ", ".join(out) if not out.is_empty() else "Nothing saved (see log)"
	return out


## Save one resource where save_path_for() says. Returns the path, or "" on error.
func save_resource(res: Resource) -> String:
	var path := save_path_for(res)
	if path == "":
		push_warning("TuningPanel: %s has no resource path, can't save" % res)
		return ""
	if path.begins_with(USER_DIR):
		DirAccess.make_dir_recursive_absolute(USER_DIR)
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_warning("TuningPanel: saving %s failed (%d)" % [path, err])
		return ""
	print("[Game] Tuning saved %s" % path)
	return path


## Where save_resource() writes `res`: its res:// path, or user://tuning/<file> when use_user_dir.
func save_path_for(res: Resource) -> String:
	var file := res.resource_path.get_file()
	if file == "":
		return ""
	return USER_DIR + file if use_user_dir else res.resource_path


## Copy the values of user://tuning/<file> (if it exists) into `res`. Returns true if it did.
func load_override(res: Resource) -> bool:
	var file := res.resource_path.get_file()
	if file == "" or not FileAccess.file_exists(USER_DIR + file):
		return false
	var saved := ResourceLoader.load(USER_DIR + file, "", ResourceLoader.CACHE_MODE_IGNORE)
	if saved == null or saved.get_script() != res.get_script():
		return false
	for p: Dictionary in res.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and p["usage"] & PROPERTY_USAGE_STORAGE:
			res.set(p["name"], saved.get(p["name"]))
	print("[Game] Tuning loaded %s" % (USER_DIR + file))
	return true


func _unhandled_input(event: InputEvent) -> void:
	# WHY: on Mac laptops F2 is a brightness key unless Fn is held, so ` (backquote) opens it too.
	var k := event as InputEventKey
	var backquote := k != null and k.pressed and not k.echo and k.physical_keycode == KEY_QUOTELEFT
	if event.is_action_pressed(&"toggle_tuning") or backquote:
		toggle()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_root = PanelContainer.new()
	_root.name = "Panel"
	_root.anchor_left = 1.0
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.offset_left = -PANEL_WIDTH
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.07, 0.06, 0.88)
	bg.content_margin_left = 12
	bg.content_margin_right = 12
	bg.content_margin_top = 10
	bg.content_margin_bottom = 10
	_root.add_theme_stylebox_override(&"panel", bg)
	var v := VBoxContainer.new()
	_root.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := Label.new()
	title.text = "Tuning   (F2 or ` closes)"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var save := Button.new()
	save.text = "Save"
	save.focus_mode = Control.FOCUS_NONE # WHY: driving keys (Space) must not press a focused button
	save.pressed.connect(save_all)
	head.add_child(save)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_status.add_theme_font_size_override(&"font_size", 12)
	_status.text = "Saves to " + ("user://tuning/" if use_user_dir else "the res:// .tres files")
	v.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_root.visible = false
	add_child(_root)


func _rebuild() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_sliders = 0
	for e: Dictionary in _entries:
		var res: Resource = e["res"]
		var head := Label.new()
		head.text = e["title"]
		head.add_theme_font_size_override(&"font_size", 20)
		head.add_theme_color_override(&"font_color", Color(1.0, 0.8, 0.3))
		_list.add_child(head)
		for p: Dictionary in res.get_property_list():
			if p["usage"] & PROPERTY_USAGE_GROUP:
				var g := Label.new()
				g.text = "— %s —" % p["name"]
				g.add_theme_color_override(&"font_color", Color(0.7, 0.85, 1.0))
				_list.add_child(g)
			elif p["hint"] == PROPERTY_HINT_RANGE and p["type"] in [TYPE_FLOAT, TYPE_INT] \
					and p["usage"] & PROPERTY_USAGE_EDITOR:
				_add_row(res, p)


func _add_row(res: Resource, p: Dictionary) -> void:
	var prop: StringName = p["name"]
	var is_int: bool = p["type"] == TYPE_INT
	var parts: PackedStringArray = (p["hint_string"] as String).split(",")
	var lo := float(parts[0]) if parts.size() > 0 else 0.0
	var hi := float(parts[1]) if parts.size() > 1 else 1.0
	var step := 1.0 if is_int else (hi - lo) / 400.0
	if parts.size() > 2 and parts[2].strip_edges().is_valid_float():
		step = float(parts[2])
	var row := HBoxContainer.new()
	var name_l := Label.new()
	name_l.text = String(prop)
	name_l.custom_minimum_size.x = 170
	name_l.add_theme_font_size_override(&"font_size", 13)
	row.add_child(name_l)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.allow_greater = true
	slider.allow_lesser = true
	slider.value = float(res.get(prop))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE # WHY: arrow keys steer; a focused slider would eat them
	row.add_child(slider)
	var val := Label.new()
	val.custom_minimum_size.x = 56
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_font_size_override(&"font_size", 13)
	val.text = _fmt(slider.value, is_int)
	row.add_child(val)
	slider.value_changed.connect(func(v: float) -> void:
		res.set(prop, int(v) if is_int else v)
		val.text = _fmt(v, is_int))
	_list.add_child(row)
	_sliders += 1


static func _fmt(v: float, is_int: bool) -> String:
	return str(int(v)) if is_int else "%.2f" % v
