class_name Phase
extends RefCounted
## Round phase ids (DESIGN §3). Owner: C02 (contract).
## The host's MatchMode drives Draft -> Build -> Race -> Score each round and announces every change on every
## peer with `GameEvents.phase_changed(phase, round)`. Public API: constants, `name_of()`, `from_name()`.
# CONTRACT: values and order.

const NONE := 0
const DRAFT := 1
const BUILD := 2
const RACE := 3
const SCORE := 4
const MATCH_OVER := 5

const NAMES: Array[String] = ["none", "draft", "build", "race", "score", "match_over"]


## Lower-case name for logs (`[Game] PHASE race 2`).
static func name_of(p: int) -> String:
	return NAMES[p] if p >= 0 and p < NAMES.size() else "?"


## Inverse of name_of(); returns NONE if unknown.
static func from_name(n: String) -> int:
	var i := NAMES.find(n.to_lower())
	return i if i >= 0 else NONE
