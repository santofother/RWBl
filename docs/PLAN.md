# Rome Wasn't Built in a Lap (RWBL): Development Plan

How the game gets built with two AI coders (Claude Code and Codex) while spending as few tokens as possible
and keeping the game true to `DESIGN.md`.

- **Design source of truth:** `DESIGN.md`. Agents read only the sections their card names. Only you change it.
- **How you run sessions day to day:** `docs/workflow/RUN_SESSIONS.md` (copy-paste prompts).
- **Rules every agent follows:** `AGENTS.md` (Claude and Codex both read it automatically).
- **What's done / what's next:** `docs/STATUS.md`.

This is the same system as The Last Fire Mage (cards, handoffs, self-merge), so it should already feel familiar.

---

## 1. The system in 60 seconds

1. Work is split into **cards** (`docs/sessions/Cxx-*.md`). One card = one session = one branch = one worktree.
2. Each card says **which AI**, **which model tier**, **which files it owns**, and **which files it may read**.
   Agents never explore the whole repo, so sessions stay small and cheap.
3. When a card is done, the agent writes a **handoff** (`docs/handoffs/Cxx.md`, max ~25 lines). The next cards
   read the handoff instead of the code.
4. The agent then **merges its own work into `main`** if tests pass and nothing conflicts. If not, it marks the
   card `REVIEW` and you run a short merge session.
5. After each wave you **play a build**. What you notice goes into a fix or triage session.

Why this saves tokens: every message in a chat re-sends the whole conversation. A fresh session that reads a
2-page card is cheap. A session that has built five features re-reads all five on every turn.

---

## 2. Who does what: Claude vs Codex

For most coding the two are equally good, so most cards are **Either** and you pick whichever has usage left.
Your budgets are about equal, so aim for roughly **half the builder cards each**. Claude also carries the
head-engineer and Blender work, so give Codex slightly more of the plain builder cards.

| Work | Who | Why |
|---|---|---|
| Head engineer: architecture, contracts, writing cards, triage, merges with conflicts | **Claude only** | One agent keeps the architecture consistent. A role choice, not a skill gap. If Claude runs out, Codex (Astra) can step in |
| 3D models of chariot, horses, items (Blender MCP) | **Claude only** | Claude Code here has the Blender MCP connected; Codex doesn't |
| Concept art, icons, item card art, UI mockups, textures | **ChatGPT only** | Image generation |
| Visual checks from screenshots (UI layout, "does this read at speed") | **Lean Codex** (GPT-6.1 Terra) | Fast and good with images, cheap |
| Long autonomous builder cards (gameplay systems) | **Either**, lean Codex | Codex's top models run long tasks well; saves Claude for head work |
| Hard netcode (prediction, interpolation) | **Either**, T1 | Both top models are in the same class |
| Merges, docs, small fixes | **Either**, T4 | Cheapest model that can do it |

### Model tiers (pick the tier the card names)

| Tier | Codex (ChatGPT) | Claude Code | Use for |
|---|---|---|---|
| T1 hard | GPT-6 Astra, low–medium | Opus 5.5, high | architecture, netcode, chariot physics feel |
| T2 normal | GPT-6.1 Sol, high | Opus 5.5, medium | most gameplay systems |
| T3 light | GPT-6.1 Sol, medium (or Luna, high) | Sonnet 5.5, medium | well-specified features, UI, bots, single items |
| T4 chores | GPT-6 Luna, low–medium | Sonnet 5.5 low or Haiku 5.5 | merges, docs, small fixes |

Rule of thumb: **start one tier lower than you think.** If the handoff says `PARTIAL` because it was too hard,
rerun the rest one tier higher. Save Fable 5.2 (Claude's top model) for a T1 card that already failed on Opus.
(Model comparison carried over from LastMage's research on 2026-11-07. Re-check when new models ship.)

---

## 3. Token-saving design choices baked into the plan

- **Reuse LastMage's net layer.** `NetworkManager`, `SteamManager`, the debug overlay, the GodotSteam addon,
  the test runner and the net test get copied in C01, not rewritten. Phase 0 of the design shrinks a lot.
- **Everything data-driven.** Each item is one `ItemDef` resource (`.tres`) plus at most one small script. Tags
  (`flammable`, `slippery`, ...) go through one interaction table. Adding an item later is a T3 card that reads
  one template, not the whole item system.
- **In-game tuning panel (F2).** You tune chariot feel yourself with sliders and save to a `.tres`. No tokens
  spent on "make the drift a bit looser".
- **Headless tests and bots.** Agents check their work by running Godot without a window and reading logs,
  not by screenshots. Bot chariots (C06) let one machine test a 5-player race.
- **Cards written just in time.** Only wave 0 cards are written in full now. C02 writes wave 1–3 cards after
  the architecture exists, so cards don't disagree with the code. Waves 4+ are planned after the first playtest.
- **Short question sessions** instead of asking in a long build chat (prompt in `RUN_SESSIONS.md`).

---

## 4. Your steps before the first card

| # | What you do | Time |
|---|---|---|
| U1 | Check Godot 4.7.2 is at `/Users/santofothergill/Downloads/Godot.app` (same as LastMage) | 1 min |
| U2 | Run card **C01** (Claude, no worktree yet: it creates the git repo locally) | one session |
| U3 | Create the GitHub repo and push (commands in `RUN_SESSIONS.md` §Setup). Needed before parallel worktrees, because builders self-merge by pushing to `origin/main` | 5 min |
| U4 | Run **C02**, then read `docs/ARCHITECTURE.md` (≈2 pages). Last cheap moment to change direction | one session + 10 min reading |

---

## 5. Waves and cards

Status lives in `docs/STATUS.md`. Card files are in `docs/sessions/`. Cards in the same wave can run at the same
time (max 3 at once on your Mac: each test run starts several Godot processes).

`Agent`: Either · Lean Claude · Lean Codex · Claude only · ChatGPT only. Suggested pairing is a starting point;
swap freely if one tool hits its limit.

### Wave 0: foundation (one after another)
| Card | Title | Agent / Tier | Design § | Done when |
|---|---|---|---|---|
| C01 | Project + reuse LastMage net core + cube sync (N1) | Claude only · T2 | 8 | Two LAN instances see each other's cube move; `NET TEST PASSED` headless |
| C02 | Architecture, contracts, stubs, write wave 1–3 cards | Claude only · T1 | 3–9 | `ARCHITECTURE.md`, stubs compile, `contract_test` passes, cards C03–C14 written |

### Wave 1: core pieces (all parallel, after C02)
| Card | Title | Suggested | Tier | Design § | Done when |
|---|---|---|---|---|---|
| C03 | Lobby: LAN discovery, Steam lobby, 4–5 slots, ready-up, start (N2, N3) | Codex | T2 | 8 | 5 instances join, ready, load scene; Steam join via Spacewar 480 (you test on 2 machines) |
| C04 | Chariot controller (horses + trailing cart, slip, surfaces, whip/stamina) + F2 tuning panel, offline | Claude | T1 | 2, 4 | Drives on a flat plane; you say it feels fun |
| C05 | Greybox loop track, checkpoints, laps, finish order, race camera v1 | Codex | T3 | 5.5, 7 | Bot or scripted input completes 2 laps; finish order logged |
| C06 | Bot drivers (same input path as players) + headless race harness | Codex | T3 | 11 Q6 | 5 bots finish a race headless |

### Wave 2: networked game (parallel where noted)
| Card | Title | Suggested | Tier | Design § | Needs | Done when |
|---|---|---|---|---|---|---|
| C07 | Host-authoritative chariot netcode: inputs up, snapshots down, interpolation, light own-chariot prediction (N4) | Claude | T1 | 8 | C03, C04 | Feels fine at 100 ms simulated lag (headless lag test + your check) |
| C08 | Build phase: top-down camera, grid/snap, ghost, rotate, placement RPC, host validation incl. path check (N5) | Codex | T2 | 5.5, 7, 8 | C05 | Bad placements rejected in a headless test |
| C09 | Match flow: Draft → Build → Race → Score loop, rounds, Grand Circus, catch-up card dealing | Codex | T2 | 3, 5.5 | C05, C06 | Full 6-round match runs headless with bots |
| C10 | Item framework + tag interaction table + first 8 items (oil, mud, ice, speed pad, ramp, column, swinging axe, pit) | Either | T2 | 5.1, 5.2 | C04, C05 | Each item affects a bot chariot in a test |

### Wave 3: full loop (all parallel)
| Card | Title | Suggested | Tier | Design § | Done when |
|---|---|---|---|---|---|
| C11 | Scoring incl. anti-grief rule + score screen | Codex | T3 | 6 | Score test with scripted events passes |
| C12 | Damage: wheels, collisions, stun, respawn, crow spectator | Claude | T2 | 4, 6 | Wheel loss changes handling; respawn < 3 s |
| C13 | Camera swing Build→Race, race camera polish (FOV, sway, pullback) | Either | T3 | 7 | You check it in a build |
| C14 | HUD: lap, position, stamina, ammo, phase timer, draft cards UI | Codex (Terra for screenshot check) | T3 | 3, 4 | Screenshots readable at 1080p |

**P1 playtest** (you + friends, full loop with greybox art). Then **C15 triage** (Claude only, T1): turns your
notes into fix cards and writes the detailed cards for wave 4+.

### Wave 4: combat and content (detailed in C15)
Spears and pickups, barbed wheels, Roman items (ballista, brazier, net gladiator, lion cage, crowd bribe),
wildcards (reverse zone, wine fountain, mirror, Colosseum gate, emperor's thumb), slapstick gore/confetti VFX.
Each item becomes its own small T3 card from the C10 template, so many run in parallel and split evenly
between Claude and Codex.

### Wave 5: art and audio
| Work | Agent |
|---|---|
| Concept art + style sheet, item card art, icons | ChatGPT only |
| Chariot, horses, cart, wheels, item models (Blender MCP), or CC0 kits (Kenney/Quaternius) | Claude only (Blender) · Either (CC0) |
| Arena/circus track dressing | Either |
| Sound pass (CC0 sounds, crowd, hooves, wheel pops) | Either |

### Wave 6: party core and hub
| Card | Title | Agent / Tier |
|---|---|---|
| C-core | Extract shared `party_core` addon from both games (net, lobby, profile, transitions) | Claude only · T1 |
| C-hub | Hub shell: lobby, pick game, `GameMode` contract | Either · T2 |
| C-rel | Steam app ID, store page, export/signing | Either · T3 + you |

---

## 6. Checkpoints for you

| When | What | Why |
|---|---|---|
| After C02 | Read `docs/ARCHITECTURE.md` | Change direction while it's cheap |
| After C04 | Drive the chariot, tune with F2, save | Pillar 1. If driving isn't fun, nothing else matters |
| After wave 1 | 2-machine LAN + Steam lobby test | Pillar 5: networking works first |
| After wave 2 | Race 2 machines + bots at simulated lag | Netcode feel |
| P1 (after wave 3) | Full-loop playtest with friends | Decides waves 4+ |

---

## 7. Decisions made / still open

Settled for this plan:
- **LAN + Steam only**, no couch/split-screen (design Q1).
- **AI chariots fill empty slots and replace dropouts** (Q6); they also make solo testing possible.
- **Reuse LastMage's net core** (Q2), same Godot 4.7.2 + GodotSteam 4.23.2 + Jolt (Q3).
- **Different from LastMage:** chariots are **host-authoritative** (clients send inputs). LastMage players are
  client-authoritative. C02 writes this into the contracts so nobody copies the wrong pattern.
- Build each game standalone, merge into the hub later (design §9).

Still open (decide when the card that needs it comes up):
- One Steam app or several (Q4): before wave 6.
- Track count and fixed loop vs arenas (Q5): after P1. Plan assumes one greybox loop track to start.
- Cross-game progression (Q7): after wave 6.
- Proximity voice from LastMage in this game too? C01 copies it but leaves it off; turn on if you want it.
