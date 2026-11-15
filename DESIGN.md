# Rome Wasn't Built in a Lap (RWBL): Design Doc (v0.1)

Title: *Rome Wasn't Built in a Lap* (short: RWBL). A chaotic party racer where players take turns building the track, then race chariots across it.

## 1. Pitch

Ultimate Chicken Horse-style track building meets slippery Micro Machines-style driving, with Roman chariots, spears, and barbed wheels. Every round, each player adds items and obstacles to a shared track, then everyone races it. The track gets more dangerous and more ridiculous every round.

- **Players:** 4-5
- **Engine:** Godot 4 (3D)
- **Networking:** local network (LAN) and Steam, built first
- **Tone:** stylized, slapstick violence (Chaos Party-style: loud and cartoonish, not gross)
- **Match length:** 15-20 minutes
- **Part of:** a party game hub. Game #1 is the mage game, and this is intended to be game #2.

## 2. Pillars

1. **Slippery, readable driving.** Drifting should feel heavy and funny, and a bad turn should be your fault.
2. **Traps should be nasty but beatable.** The scoring rewards clever traps, not walls of death.
3. **Chaos you can read.** Every item has a clear silhouette and a clear effect, even at speed.
4. **Short rounds, fast turnover.** Dying never means waiting long.
5. **Networking works first.** Everything else is built on a connection layer that is reliable.

## 3. Match flow

Each round has four phases:

| Phase | Camera | Duration | What happens |
|---|---|---|---|
| Draft | UI | ~10s | Each player is dealt 3 random cards (items and track pieces mixed) and keeps 1 |
| Build | Top-down | ~25s | Each player places their one card (item or track piece) on the track, all at once |
| Race | Third person behind chariot | ~60-90s | 1-2 laps |
| Score | UI | ~10s | Animated vertical bar chart: each player's bar climbs by this round's points toward the win line, overtakes re-sort, next round |

- **No round cap.** Rounds repeat until someone wins.
- **Winning:** the win score is **1000 points**. You only win by **finishing 1st in a race while your total
  (with that round's points) is at or above the win score.** Reaching 1000 isn't enough on its own: e.g. 900 →
  win a race → 1100, and the match goes on until you win another race, or someone else at 1000+ wins one.
  Everyone else can still catch up. Players at 1000+ show a "MATCH POINT" tag.
- No "Grand Circus" finale (dropped 2026-11-14: with no round cap there's no final round).

## 4. Chariot driving model

Do **not** use a stock `RigidBody3D`. Write a custom controller. It is easier to tune and far easier to network.

- **Two bodies:** a horse pair (steering and thrust) and a cart trailing behind on a hitch point.
- The horse pair steers. The cart follows with lateral slip, so it fishtails and can jackknife.
- Lateral friction depends on the surface (normal, oil, mud, ice).
- **Whip boost:** short burst on a tap, with stamina cost and cooldown. Spamming tires the horses.
- **Damage model:** wheels can break. Losing one wheel gives a limp with worse turning. Losing both gives a crawl until respawn.
- **Collisions:** the heavier or faster chariot wins. Cart hits damage wheels. Horse hits stun briefly.
- **Controls:** stick to steer, accelerate/brake, whip, jump, and one action button (throw spear or use pickup).
- **Jump:** a short hop (about 1 m) on a cooldown that costs a little stamina. Use it to hop low traps and
  surface patches, or to twist the chariot in the air before a corner. No jumping while stunned or with no wheels.

Tuning parameters to expose in a debug panel: horse thrust, max speed, steering rate, hitch stiffness, lateral grip per surface, cart mass, whip boost and stamina.

## 5. Items

Every item has tags (`flammable`, `slippery`, `heavy`, `hot`, `living`) so interactions work through a small table instead of special cases. For example: oil plus brazier makes a fire lane, and a boulder on ice slides farther.

### 5.1 Terrain (common)
| Item | Effect |
|---|---|
| Oil slick | Grip near zero, cart fishtails. Flammable |
| Mud patch | Slows horses, cart keeps swinging |
| Ice sheet | No steering authority while on it |
| Rumble gravel | Camera shake, reduced turning |
| Speed pad (laurel) | Short boost |
| Ramp | Launches the chariot |

### 5.2 Obstacles
| Item | Effect |
|---|---|
| Column | Static. Cart hit breaks a wheel, horse hit stuns |
| Swinging axe | Timed pendulum |
| Rolling boulder | Triggered by a tripwire |
| Pit | Fall and respawn with a time penalty |
| Moving gate | Opens and closes on a rhythm |
| Spike wall | Lethal at speed, harmless when braking |

### 5.3 Roman and weapon items
| Item | Effect |
|---|---|
| Ballista turret | Fires bolts down a lane. Placer sets the direction |
| Brazier | Ignites flammable items |
| Net gladiator | Throws a net that tangles horses |
| Lion cage | Lion chases the nearest chariot briefly |
| Spear rack (pickup) | Grants spear ammo |
| Barbed wheels (pickup) | Shredder wheels for ~8s. Slower and harder to steer |
| Crowd bribe | Spectators pelt the leader |

### 5.4 Wildcards (rare)
- **Reverse zone:** inverted steering inside the area.
- **Wine fountain:** drunk-steer camera wobble.
- **Mirror:** spawns a ghost chariot that copies the leader's route.
- **Colosseum gate:** closes behind the first-place chariot.
- **Emperor's thumb:** at the end of a round, the placer boosts or penalizes one chosen player.
- **Demolish (uncommon):** instead of placing something, in the Build phase you click any placed item or track
  piece and it's removed. It can't remove the base track or the start/finish line.

### 5.5 Draft and placement rules
- 3 random cards per player per round, weighted by rarity. Cards are items or track pieces (§5.6), mixed.
- Each player keeps 1 card and places it in that round's Build phase.
- **Catch-up through the draft:** last place gets a rare card, and the leader only draws commons.
- Items cannot be placed on the start or finish line, and items need a minimum gap.
- **Track validation:** the host checks that a drivable path still exists after each placement (flood fill on the track surface or a navigation check) and rejects placements that block it.

### 5.6 Track pieces (planned, wave 4+)
Besides items, the track itself can change shape. A track piece replaces a section of the road. Pieces are
drafted like items (same cards, same rarity weights) and placed in the Build phase, so the track grows and
changes every round. Pieces stay for the rest of the match, like items.
| Piece | Effect |
|---|---|
| Sharp turn / hairpin | Tight corner, punishes speed, the cart swings wide |
| Chicane / S-bend | Quick left-right, tests fishtail control |
| Uphill / downhill | Slows climbing horses, downhill builds speed and makes braking harder |
| Crest / jump | Small hill that launches fast chariots |
| Banked turn | Lets you hold speed through a corner |
| Spiral loop | Drive up and around a loop, upside down at the top. Too slow and you fall off |

- Pieces keep the track a closed loop. The start/finish straight can't be changed.
- Bots, checkpoints, the no-build zone and the blocked-road check follow the new shape.
- Build order: shape and turns first, then hills, then loops. Loops need the chariot to stick to the road
  (gravity along the road surface) and a camera that rolls with it.

## 6. Scoring

### Per-round
| Event | Points |
|---|---|
| Finish 1st / 2nd / 3rd / 4th / 5th | 150 / 100 / 70 / 40 / 0 |
| Your trap hits another player | +30 each (max 90 per round) |
| Each lap completed | +25 |
| Fewest deaths this round (ties all get it) | +50 |
| Each kill (spear, wheel or ram; not your trap) | +60 |
| Die to your own trap | -30 |
| Clean lap (no collisions) | +25 |
| Last to finish | +25 mercy points |
| **Nobody passes your item, or everyone dies to it** | 0 for that item |

Scale (2026-11-14): a round winner earns ~250–300, so someone reaches match point in ~4–5 rounds.

The last row is the anti-grief rule. A trap that is impossible to pass pays nothing, which encourages tricky but fair traps.

### Death and respawn
Dead players return after a short penalty, or become a "crow" spectator who can still drop a minor hazard. Nobody sits out long.

### Stylized gore
Wheels pop off and bounce away, gladiators ragdoll, horses stumble and spin. Impacts use confetti-like blood splashes and big comedic stylization. No lingering gore and no realism.

## 7. Cameras

- **Build phase:** top-down orthographic-style view with a grid or snap guide, an item ghost preview, and a rotate control.
- **Race phase:** third person behind the chariot. Needs a speed-based FOV, a drift sway, and slight pullback on boost.
- **Transition:** a short animated swing between the two views so the player can connect their placed items to what they then drive through.

## 8. Networking (priority one)

This is built and tested first, before any gameplay depth.

### Goals
- Local network play (LAN) and Steam play with the **same game code**.
- 4-5 players, host-authoritative.
- Drop-in lobby: create, join by code or Steam friends, ready up.

### Approach
- Use Godot's high-level `MultiplayerAPI` with swappable peers:
  - **LAN:** `ENetMultiplayerPeer`, with host discovery via UDP broadcast.
  - **Steam:** GodotSteam with its multiplayer peer, using Steam lobbies and relay (so no port forwarding).
- Wrap both behind a small `Transport` interface (`host()`, `join(target)`, `leave()`, signals for peer connect/disconnect) so game code never checks which transport is active.
- **Authority model:**
  - Clients send **inputs** to the host.
  - Host simulates chariots, items, and combat.
  - Clients render snapshots with interpolation, and predict their own chariot lightly.
  - Godot physics is not deterministic, so there is no lockstep or rollback.
- **Build phase** syncs as RPCs of `(item_id, transform, owner)`, validated by the host (cost, placement limit, track validity).
- **Disconnects:** mid-match drop-outs are replaced by an AI chariot or simply removed. Host migration is out of scope for v1, and if the host leaves the match ends cleanly.

### Network milestones
| # | Milestone | Done when |
|---|---|---|
| N1 | Two instances connect over LAN and see each other's cube move | Works on two machines |
| N2 | Same test over Steam (use Spacewar app ID 480 during dev) | Join through Steam lobby/friends |
| N3 | 4-5 players with a lobby, ready-up, scene start | Stable for a full session |
| N4 | Chariot prototype synced with interpolation | Feels fine at 100 ms latency |
| N5 | Build phase RPCs plus host validation | Items sync, bad placements rejected |

## 9. Hub architecture

**Decision:** build each game as its own Godot project sharing a "party core" addon, and merge into the hub later.

### Why not one project from day one
Project settings (physics, input map, autoloads) are global per project. Two games in one project fight over them, and one game's bug can break the other.

### Party core addon (shared via git submodule or a shared repo)
- Transport abstraction (LAN and Steam)
- Lobby, player slots, ready-up, disconnect handling
- Player profile (name, color, avatar, unlocks)
- Input mapping helpers and controller support
- Scene transitions, results screen
- Settings and audio buses

### Game contract
```
GameMode
  setup(players: Array[PlayerInfo], rules: Dictionary)
  start()
  signal finished(results: Array[PlayerResult])
```
The hub passes players in and receives results out. A game runs standalone through a debug lobby that uses the same party core.

### Hub shell (later)
A thin launcher scene that owns the lobby, lets the group pick a game, and loads that game's mode. Loading options, in order of preference:
1. Merge the games into one project once their settings are reconciled.
2. Load each game as a `.pck` resource pack through the `GameMode` contract.

### Steam structure
One Steam app for the whole hub, with each game as a mode, is the simplest. Separate store pages mean separate app IDs and fees, so decide before launch.

## 10. Milestones

| Phase | Goal |
|---|---|
| **0. Networking spike** | N1-N3. LAN and Steam lobbies with cube avatars |
| **1. Feel prototype** | Slippery chariot controller on a flat track, tuning panel, N4 |
| **2. Build phase** | Top-down placement, 6-8 items, host validation (N5) |
| **3. Full loop** | Draft, build, race, score for a whole match |
| **4. Combat and content** | Spears, wheels, damage, the rest of the item list, track pieces (§5.6), gore pass |
| **5. Extract core** | Pull the lobby and net layer out into the shared addon (reuse the mage game's where possible) |
| **6. Hub** | Shell, game selection, shared profile |
| **7. Polish** | Audio, tracks, UI, balance, playtests |

## 11. Open questions

1. **Does "local" mean LAN only, or also couch/split-screen on one machine?** This doc assumes LAN only. Couch play would need split cameras and is a large extra scope.
2. Does the mage game already have lobby and netcode? If so, how reusable is it as the party core?
3. Which Godot version and which GodotSteam build is the mage game using? Both projects should match.
4. One Steam app or several?
5. How many tracks or arenas ship at launch, and is the track a fixed arena or a loop?
6. AI chariots to fill empty slots, or only real players?
7. Cross-game progression (unlocks, currency) in the hub: in scope for v1 or later?
8. ~~Track pieces (§5.6): who places them?~~ **Decided:** drafted with items and placed in the Build phase,
   one card per player per round (§3, §5.5).
9. ~~Grand Circus without a round cap?~~ **Decided:** dropped. Every round scores the same.

## 12. Risks

| Risk | Mitigation |
|---|---|
| Chariot physics doesn't feel fun | Prototype and tune it early, before any content |
| Netcode complexity with physics | Host-authoritative, custom physics, interpolation, test at high latency early |
| Hub scope creep | Ship the chariot game standalone first. Hub stays thin |
| Griefing with unpassable tracks | Track validation plus the "nobody passes means 0 points" rule |
| Steam integration surprises | Start Steam testing in Phase 0, not at the end |
