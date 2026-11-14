class_name PlaceResult
extends RefCounted
## Result codes of a placement request (DESIGN §5.5, §8 N5). Owner: C02 (contract).
## NET: the host validates `(item_id, transform, owner)` and answers the requester with one of these.
## Public API: constants, `describe()`.
# CONTRACT: values. Add new codes at the end.

const OK := 0
const WRONG_PHASE := 1 ## not in the build phase
const UNKNOWN_ITEM := 2 ## no ItemDef with that id
const NOT_IN_HAND := 3 ## the player didn't draft this item (or already placed it)
const OVER_BUDGET := 4 ## cost / per-player limit reached
const OFF_TRACK := 5 ## violates ItemDef.placement
const NO_BUILD_ZONE := 6 ## on or near the start/finish line or the start grid
const TOO_CLOSE := 7 ## closer than the minimum gap to another item
const BLOCKS_PATH := 8 ## no drivable path would remain (track validation)
const OUT_OF_BOUNDS := 9 ## outside the track area
const BAD_TRANSFORM := 10 ## NaN, tilted, scaled or not on the ground

const TEXT: Array[String] = ["OK", "Not the build phase", "Unknown item", "Not in your hand", "Over budget",
	"Must be placed on the track", "Too close to the start", "Too close to another item",
	"Would block the track", "Out of bounds", "Bad position"]


## Short player-facing text for a code.
static func describe(code: int) -> String:
	return TEXT[code] if code >= 0 and code < TEXT.size() else "Rejected (%d)" % code
