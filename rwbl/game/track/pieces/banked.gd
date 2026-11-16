class_name BankedPiece
extends TrackPiece
## Banked turn (DESIGN §5.6, C20): a wide turn whose road tilts towards the inside (outside edge high), so it can be
## taken near full speed: the chariot gets extra sideways grip on a tilted road (`ChariotTuning.bank_grip`).
## A tilt-in straight, the arc, a tilt-out straight. Turns right; flip = left. Owner: C20. NET: shape data only. Level at both ends.

@export_range(15.0, 60.0) var radius := 32.0 # TUNE: m
@export_range(30.0, 180.0) var degrees := 90.0 # TUNE
@export_range(0.0, 40.0) var bank := 20.0 # TUNE: degrees of tilt through the arc
@export_range(5.0, 40.0) var ease_len := 20.0 # TUNE: m of straight to tilt in / out (shorter = the outside lane kicks fast chariots up)
## Centre-line rise per unit sin(tilt), m (0 = rolls about the centre line, the inside edge dips below the joints).
@export var lift := 0.0


func _shape() -> void:
	_banked_arc(radius, degrees, true, bank, ease_len, lift)
