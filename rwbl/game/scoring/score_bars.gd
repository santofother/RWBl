class_name ScoreBars
extends Control
## Animated vertical bar chart for the score screen (C18): one column per player, a win line at `win_score`,
## and the round's points rising chunk by chunk (finish, kills, traps, bonus) with pops, sparks, overtakes,
## MATCH POINT flags and a confetti burst when someone wins. Owner: C18.
## NET: local only (presentation); reads data handed to `setup()`.
## Public API: setup(players, breakdown, totals, win_score, winner_slot, tuning), play(budget_seconds), skip(),
##   bars() -> Array, is_done(), signal animation_done.
## Logs: `[Score] BARS done` once the sequence ends (played out or skipped).
# WHY: everything is drawn in _draw() from per-column state (rank position, chunk fractions); one Tween drives
#   the state so the whole show can be sped up (`set_speed_scale`) to fit inside score_time and skipped by
#   jumping the state to its final values.

## all peers (local) · the sequence ended, played out or skipped.
signal animation_done

const MARGIN_LEFT := 70.0
const MARGIN_RIGHT := 30.0
const MARGIN_TOP := 78.0
const MARGIN_BOTTOM := 92.0
const GOLD := Color(1.0, 0.84, 0.3)

class Col extends RefCounted:
	var slot := 0
	var player_name := ""
	var color := Color.WHITE
	var from := 0
	var to := 0
	var chunks: Dictionary = {} # category -> int
	var fracs: Dictionary = {} # category -> float (0..1, can overshoot with BACK)
	var start_rank := 0
	var rank := 0
	var pos := 0.0 # animated column position (rank units)
	var wob := 0.0 # 0..1 squash and stretch pulse
	var burst := 0.0 # winner's extra bounce
	var is_winner := false
	var name_label: Label
	var total_label: Label
	var flag: Label

var _tun: ScoreAnimTuning
var _cols: Array[Col] = [] # start order
var _final: Array[Col] = [] # final order
var _win := 1000
var _y_max := 1100.0
var _tween: Tween
var _speed := 1.0
var _done := true
var _t := 0.0
var _flash := 0.0
var _pops: Array[Node] = []


## Build the columns. `breakdown` = Scoring.get_breakdown(), `totals` = totals AFTER the round,
## `winner_slot` = who wins the match this round (-1 none). Bars start at last round's totals.
func setup(players: Array[PlayerInfo], breakdown: Dictionary, totals: Dictionary, win_score: int,
		winner_slot: int, tuning: ScoreAnimTuning) -> void:
	_clear()
	_tun = tuning
	_win = win_score
	var top := 0
	for p in players:
		var c := Col.new()
		c.slot = p.slot
		c.player_name = p.name
		c.color = p.color
		var bd: Dictionary = breakdown.get(p.slot, {})
		var sum := 0
		for cat in ScoreAnimTuning.CATEGORIES:
			var v := int(bd.get(cat, 0))
			c.chunks[cat] = v
			c.fracs[cat] = 0.0
			sum += v
		c.to = int(totals.get(p.slot, 0))
		c.from = c.to - sum
		c.is_winner = p.slot == winner_slot
		top = maxi(top, maxi(c.to, c.from))
		_cols.append(c)
	_y_max = maxf(float(_win) / _tun.line_height, float(top) * 1.1)
	_cols.sort_custom(func(a: Col, b: Col) -> bool: return a.from > b.from or (a.from == b.from and a.slot < b.slot))
	_final = _cols.duplicate()
	_final.sort_custom(func(a: Col, b: Col) -> bool: return a.to > b.to or (a.to == b.to and a.slot < b.slot))
	for i in _cols.size():
		_cols[i].start_rank = i
		_cols[i].pos = float(i)
	for i in _final.size():
		_final[i].rank = i
	for c in _cols:
		c.name_label = _make_label(c.player_name, 28, c.color.lightened(0.35))
		c.total_label = _make_label(str(c.from), 38, Color.WHITE)
		c.flag = _make_label("", 28, GOLD)
		c.flag.visible = false
	_done = false
	queue_redraw()


## Final order, one entry per player: {slot, from, to, chunks {finish, kills, traps, bonus}}.
func bars() -> Array:
	var out: Array = []
	for c in _final:
		out.append({"slot": c.slot, "from": c.from, "to": c.to, "chunks": c.chunks.duplicate()})
	return out


## true once the sequence ended (or when nothing was set up).
func is_done() -> bool:
	return _done


## Run the show; the speed is raised so it ends `end_hold` before `budget` seconds are up.
func play(budget: float) -> void:
	if _cols.is_empty():
		return
	var cats := _active_cats()
	var resort := _order_changed()
	var winner := _winner()
	var nominal := _tun.intro_time + cats.size() * (_tun.chunk_time + _tun.chunk_gap) + _tun.finale_time
	if resort:
		nominal += _tun.resort_time + 0.3
	if winner:
		nominal += 0.8
	_speed = maxf(1.0, nominal / maxf(1.0, budget - _tun.end_hold))
	_tween = create_tween()
	_tween.set_speed_scale(_speed)
	_tween.tween_interval(_tun.intro_time)
	for cat in cats:
		_tween.tween_callback(_begin_chunk.bind(cat))
		_tween.tween_method(_set_frac.bind(cat), 0.0, 1.0, _tun.chunk_time) \
			.set_trans(_tun.grow_trans as Tween.TransitionType).set_ease(Tween.EASE_OUT)
		_tween.tween_interval(_tun.chunk_gap)
	if resort:
		_tween.tween_method(_set_pos, 0.0, 1.0, _tun.resort_time) \
			.set_trans(_tun.slide_trans as Tween.TransitionType).set_ease(Tween.EASE_OUT)
		_tween.tween_callback(_overtake_pops)
		_tween.tween_interval(0.3)
	_tween.tween_callback(_finale)
	_tween.tween_interval(_tun.finale_time + (0.8 if winner else 0.0))
	_tween.tween_callback(_finish)


## Jump to the final state (any key / click). Safe to call at any time.
func skip() -> void:
	if _done or _cols.is_empty():
		return
	if _tween:
		_tween.kill()
	for n in _pops:
		if is_instance_valid(n):
			n.queue_free()
	_pops.clear()
	for c in _cols:
		for cat in c.fracs:
			c.fracs[cat] = 1.0
		c.wob = 0.0
		c.pos = float(c.rank)
	_finale()
	_finish()


## Stop without finishing (the phase ended while it was still running). Logs `[Score] BARS aborted`.
func abort() -> void:
	if _done:
		return
	if _tween:
		_tween.kill()
	_done = true
	print("[Score] BARS aborted")


func _process(delta: float) -> void:
	if _cols.is_empty():
		return
	_t += delta
	_flash = maxf(0.0, _flash - delta * 2.0)
	var r := _plot()
	var slot_w := r.size.x / maxf(1.0, _cols.size())
	for c in _cols:
		var x := r.position.x + c.pos * slot_w
		c.name_label.position = Vector2(x, r.end.y + 6.0)
		c.name_label.size = Vector2(slot_w, 34.0)
		c.total_label.position = Vector2(x, r.end.y + 40.0)
		c.total_label.size = Vector2(slot_w, 46.0)
		c.total_label.text = str(int(round(_value(c))))
		var over := _value(c) >= float(_win)
		c.total_label.add_theme_color_override(&"font_color", GOLD if over else Color.WHITE)
		c.flag.position = Vector2(x, r.position.y - 40.0)
		c.flag.size = Vector2(slot_w, 36.0)
		c.flag.pivot_offset = c.flag.size * 0.5
	queue_redraw()


func _draw() -> void:
	if _cols.is_empty() or _tun == null:
		return
	var r := _plot()
	var font := get_theme_default_font()
	var slot_w := r.size.x / maxf(1.0, _cols.size())
	# ghost ticks
	var v := 0
	while float(v) <= _y_max:
		if absi(v - _win) > 20:
			var ty := _y(float(v), r)
			draw_line(Vector2(r.position.x, ty), Vector2(r.end.x, ty), Color(1, 1, 1, 0.10), 1.0)
			draw_string(font, Vector2(6, ty + 7), str(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.38))
		v += _tun.tick_every
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), Color(1, 1, 1, 0.5), 3.0)
	_draw_legend(font, r)
	# bars
	var any_over := false
	for c in _cols:
		any_over = _draw_bar(c, r, slot_w) or any_over
	# win line on top of the bars
	var wy := _y(float(_win), r)
	var pulse := 0.5 + 0.5 * sin(_t * 7.0) if any_over else 0.0
	var line_col := GOLD.lerp(Color.WHITE, pulse * 0.6)
	var x := r.position.x
	while x < r.end.x:
		draw_line(Vector2(x, wy), Vector2(minf(x + 16.0, r.end.x), wy), line_col, 4.0 + pulse * 3.0)
		x += 26.0
	draw_string(font, Vector2(r.end.x - 260.0, wy - 9.0), "WIN LINE  %d" % _win, HORIZONTAL_ALIGNMENT_RIGHT, 260, 24, line_col)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.95, 0.7, _flash * 0.35))


func _draw_legend(font: Font, r: Rect2) -> void:
	var x := r.position.x
	for cat in ScoreAnimTuning.CATEGORIES:
		draw_rect(Rect2(x, 8, 18, 18), _tun.category_color(cat))
		draw_string(font, Vector2(x + 24, 24), String(cat).capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.8))
		x += 140.0


## Draws one column; returns true when its bar is at or above the win line.
func _draw_bar(c: Col, r: Rect2, slot_w: float) -> bool:
	var st := _stack(c)
	var segs: Array = st[0]
	var lost: float = st[1]
	var cx := r.position.x + (c.pos + 0.5) * slot_w
	var bw := minf(slot_w * 0.62, float(_tun.bar_max_width)) * (1.0 - _tun.wobble * c.wob)
	var lift := 1.0 + 0.12 * c.burst
	var running := 0.0
	var seg_col := Color.WHITE
	for s in segs:
		var amt: float = s[0]
		if amt <= 0.0:
			continue
		seg_col = s[1]
		var y_top := _y(running + amt, r) if lift == 1.0 else _y((running + amt) * lift, r)
		var y_bot := _y(running, r) if lift == 1.0 else _y(running * lift, r)
		var rect := Rect2(cx - bw * 0.5, y_top, bw, y_bot - y_top)
		draw_rect(rect, seg_col)
		draw_rect(rect, Color(0, 0, 0, 0.55), false, 2.0)
		running += amt
	var top_y := _y(running * lift, r)
	if lost > 0.0:
		var phase := 0.0
		for cat in ScoreAnimTuning.CATEGORIES:
			if int(c.chunks[cat]) < 0:
				phase = maxf(phase, sin(clampf(float(c.fracs[cat]), 0.0, 1.0) * PI))
		var ly := _y((running + lost) * lift, r)
		draw_rect(Rect2(cx - bw * 0.5, ly, bw, top_y - ly), Color(_tun.color_loss, 0.65 * phase))
	var over := running >= float(_win)
	if running > 0.0:
		draw_line(Vector2(cx - bw * 0.5, top_y), Vector2(cx + bw * 0.5, top_y), Color(1, 1, 1, 0.8), 3.0)
	if over:
		var glow := 0.5 + 0.5 * sin(_t * 7.0 + float(c.slot))
		var bar_top := top_y
		var halo := Rect2(cx - bw * 0.5 - 5.0, bar_top - 5.0, bw + 10.0, _y(0.0, r) - bar_top + 5.0)
		draw_rect(halo, Color(GOLD, 0.12 + 0.18 * glow))
		draw_rect(halo, Color(GOLD, 0.5 + 0.5 * glow), false, 3.0 + 3.0 * glow)
	return over


# [segments [[amount, color], ...], lost]; negative chunks shave the top of the stack.
func _stack(c: Col) -> Array:
	var segs: Array = [[float(c.from), c.color]]
	var neg := 0.0
	for cat in ScoreAnimTuning.CATEGORIES:
		var ch := int(c.chunks[cat])
		if ch == 0:
			continue
		var amt := float(ch) * float(c.fracs[cat])
		if ch > 0:
			segs.append([amt, _tun.category_color(cat).lerp(c.color, 0.3)])
		else:
			neg += -amt
	var removed := neg
	var i := segs.size() - 1
	while removed > 0.0 and i >= 0:
		var take := minf(removed, float(segs[i][0]))
		segs[i][0] = float(segs[i][0]) - take
		removed -= take
		i -= 1
	return [segs, neg]


func _value(c: Col) -> float:
	var total := float(c.from)
	for cat in ScoreAnimTuning.CATEGORIES:
		total += float(c.chunks[cat]) * float(c.fracs[cat])
	return maxf(0.0, total)


func _plot() -> Rect2:
	return Rect2(MARGIN_LEFT, MARGIN_TOP, maxf(10.0, size.x - MARGIN_LEFT - MARGIN_RIGHT),
		maxf(10.0, size.y - MARGIN_TOP - MARGIN_BOTTOM))


func _y(v: float, r: Rect2) -> float:
	return r.end.y - v / _y_max * r.size.y


func _active_cats() -> Array[StringName]:
	var out: Array[StringName] = []
	for cat in ScoreAnimTuning.CATEGORIES:
		for c in _cols:
			if int(c.chunks[cat]) != 0:
				out.append(cat)
				break
	return out


func _order_changed() -> bool:
	for c in _cols:
		if c.start_rank != c.rank:
			return true
	return false


func _winner() -> Col:
	for c in _cols:
		if c.is_winner:
			return c
	return null


func _begin_chunk(cat: StringName) -> void:
	var r := _plot()
	var slot_w := r.size.x / maxf(1.0, _cols.size())
	for c in _cols:
		var ch := int(c.chunks[cat])
		if ch == 0:
			continue
		# running total once this chunk has landed (earlier categories are already in)
		var after := float(c.from)
		for k in ScoreAnimTuning.CATEGORIES:
			after += float(c.chunks[k])
			if k == cat:
				break
		var x := r.position.x + (c.pos + 0.5) * slot_w
		var y := _y(maxf(0.0, after), r)
		var txt := ("+%d" % ch) if ch > 0 else ("−%d" % -ch)
		var col := _tun.category_color(cat) if ch > 0 else _tun.color_loss
		_pop(txt, Vector2(x, y - 26.0), col, 38, 1.0)
		if ch > 0 and _tun.sparkles > 0:
			_sparks(Vector2(x, y), col)


func _set_frac(t: float, cat: StringName) -> void:
	for c in _cols:
		c.fracs[cat] = t
		if int(c.chunks[cat]) != 0:
			c.wob = sin(clampf(t, 0.0, 1.0) * PI)


func _set_pos(t: float) -> void:
	for c in _cols:
		c.pos = lerpf(float(c.start_rank), float(c.rank), t)


func _overtake_pops() -> void:
	var r := _plot()
	var slot_w := r.size.x / maxf(1.0, _cols.size())
	for c in _cols:
		if _overtook(c):
			var x := r.position.x + (c.pos + 0.5) * slot_w
			_pop("▲ OVERTAKE!", Vector2(x, _y(float(c.to), r) - 70.0), Color(0.5, 1.0, 0.6), 34, 1.2)


# true when `c` was strictly behind someone before the round and is strictly ahead now.
func _overtook(c: Col) -> bool:
	for o in _cols:
		if o != c and c.from < o.from and c.to > o.to:
			return true
	return false


func _finale() -> void:
	for c in _cols:
		c.wob = 0.0
		if c.is_winner:
			c.flag.text = "WINS!"
			c.flag.add_theme_font_size_override(&"font_size", 40)
			_show_flag(c)
			_burst(c)
		elif c.to >= _win:
			c.flag.text = "MATCH POINT"
			_show_flag(c)


func _show_flag(c: Col) -> void:
	c.flag.visible = true
	c.flag.scale = Vector2(0.2, 0.2)
	var tw := create_tween()
	tw.set_speed_scale(_speed)
	tw.tween_property(c.flag, "scale", Vector2.ONE * _tun.pop_scale, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c.flag, "scale", Vector2.ONE, 0.2)


func _burst(c: Col) -> void:
	_flash = 1.0
	var r := _plot()
	var slot_w := r.size.x / maxf(1.0, _cols.size())
	var tw := create_tween()
	tw.set_speed_scale(_speed)
	tw.tween_method(func(t: float) -> void: c.burst = t, 0.0, 1.0, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(t: float) -> void: c.burst = t, 1.0, 0.0, 0.6) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	if _tun.confetti <= 0:
		return
	var at := Vector2(r.position.x + (c.rank + 0.5) * slot_w, _y(float(c.to), r))
	for fountain in [true, false]:
		var p := CPUParticles2D.new()
		p.position = at
		p.amount = _tun.confetti / 2
		p.one_shot = true
		p.explosiveness = 0.95
		p.lifetime = 2.4
		p.direction = Vector2.UP
		p.spread = 55.0 if fountain else 180.0
		p.initial_velocity_min = 300.0 if fountain else 120.0
		p.initial_velocity_max = 720.0 if fountain else 380.0
		p.gravity = Vector2(0, 700)
		p.scale_amount_min = 4.0
		p.scale_amount_max = 10.0
		p.angular_velocity_min = -540.0
		p.angular_velocity_max = 540.0
		p.hue_variation_min = 0.0
		p.hue_variation_max = 1.0
		p.color = Color(1.0, 0.5, 0.45)
		add_child(p)
		p.emitting = true
		p.finished.connect(p.queue_free)
		_pops.append(p)


func _sparks(at: Vector2, color: Color) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.amount = _tun.sparkles
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 0.6
	p.direction = Vector2.UP
	p.spread = 70.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 260.0
	p.gravity = Vector2(0, 500)
	p.scale_amount_min = 4.0
	p.scale_amount_max = 8.0
	p.color = color.lightened(0.3)
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	_pops.append(p)


## A label that pops in (overshoot), floats up and fades.
func _pop(text: String, at: Vector2, color: Color, font_size: int, hold: float) -> void:
	var l := _make_label(text, font_size, color)
	l.clip_text = false # WHY: clip_text collapses the minimum width to 0
	var sz := l.get_minimum_size()
	l.size = sz
	l.position = at - Vector2(sz.x * 0.5, sz.y * 0.5)
	l.pivot_offset = sz * 0.5
	l.scale = Vector2(0.3, 0.3)
	_pops.append(l)
	var tw := l.create_tween()
	tw.set_speed_scale(_speed)
	tw.tween_property(l, "scale", Vector2.ONE * _tun.pop_scale, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.12)
	tw.tween_interval(hold * 0.5)
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 46.0, hold * 0.8)
	tw.tween_property(l, "modulate:a", 0.0, hold * 0.8)
	tw.set_parallel(false)
	tw.tween_callback(l.queue_free)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override(&"outline_size", 8)
	add_child(l)
	return l


func _finish() -> void:
	if _done:
		return
	_done = true
	for c in _cols:
		for cat in c.fracs:
			c.fracs[cat] = 1.0
		c.pos = float(c.rank)
		c.wob = 0.0
	print("[Score] BARS done")
	animation_done.emit()


func _clear() -> void:
	if _tween:
		_tween.kill()
	for n in get_children():
		n.queue_free()
		remove_child(n)
	_pops.clear()
	_cols.clear()
	_final.clear()
	_flash = 0.0
	_done = true
