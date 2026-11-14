class_name Layers
extends RefCounted
## 3D physics layer bits (names also set in project.godot [layer_names]). Owner: C02 (contract).
## Use these constants for collision_layer / collision_mask, never raw numbers.
## Public API: constants.
# CONTRACT: values.

const WORLD := 1 ## layer 1: track ground (static). Build-phase raycasts hit this.
const WALL := 2 ## layer 2: track walls / barriers (static)
const HORSES := 4 ## layer 3: horse pair body of every chariot
const CART := 8 ## layer 4: cart body of every chariot
const ITEM_SOLID := 16 ## layer 5: solid item bodies (column, gate, boulder, axe blade)
const ITEM_TRIGGER := 32 ## layer 6: item Area3D triggers (oil, mud, pad, tripwire). Mask HORSES | CART
const PROJECTILE := 64 ## layer 7: spears, ballista bolts, nets (wave 4)
const PICKUP := 128 ## layer 8: pickups (spear rack, barbed wheels)

const CHARIOT := HORSES | CART
