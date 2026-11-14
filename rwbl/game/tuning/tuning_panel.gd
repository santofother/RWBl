extends CanvasLayer
## F2 tuning panel (autoload `TuningPanel`). Owner: C04. Lets the user tune any registered Resource live
## with sliders (one per `@export_range` property) and save it back to its .tres.
## C02 STUB: register() stores the resource; F2 only prints. C04 builds the UI.
## NET: local only. Edits on the host change the simulation; on clients they only change prediction.
## Public API: `register(res, title)`, `registered() -> Array`.
# CONTRACT: every tuning resource (ChariotTuning, MatchTuning, ScoreTable, ...) calls register() once.

var _entries: Array = [] # [{res, title}]


## Add a resource to the panel (ignored if already registered).
func register(res: Resource, title: String) -> void:
	for e: Dictionary in _entries:
		if e["res"] == res:
			return
	_entries.append({"res": res, "title": title})


## Registered entries: [{res, title}].
func registered() -> Array:
	return _entries


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_tuning"):
		print("[Game] TuningPanel: %d resources registered (UI is C04)" % _entries.size()) # TODO(C04)
