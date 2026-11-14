class_name Surface
extends RefCounted
## Ground surface types (DESIGN §4: lateral friction depends on the surface). Owner: C02 (contract).
## `Track.surface_at(pos)` returns one of these; ChariotTuning maps each to grip / speed numbers.
## Public API: constants, `ALL`.
# CONTRACT: names. Add new surfaces here (and a grip value in ChariotTuning).

const NORMAL := &"normal"
const OIL := &"oil"
const MUD := &"mud"
const ICE := &"ice"
const GRAVEL := &"gravel"
const OFFTRACK := &"offtrack" ## sand outside the track edge

const ALL: Array[StringName] = [NORMAL, OIL, MUD, ICE, GRAVEL, OFFTRACK]
