# Weather & Event Lore — Synmergia

> **Scope rule (from the board):** everything here is `labs/` lore. `game/` is
> read-only context. Do not edit GDScript, `.tres`, or any schema file from this
> pass. A person or agent lands the good parts later. Grounded in the actual
> data this session read: 5 weather-event `.tres`, 7 horde `.tres`, the
> weather law in `weather.gd`, and the sky-sign lore in `sign_profile.gd`.

---

## The law first (so the lore has something to stand on)

The weather already has a rule the world is honest about: **two providers, one answer**.

- **Cosmic (primary):** real NOAA solar-wind (Kp) drives the sky’s mood. When the feed is fresh, the
  whole planet shares the sky’s temper. The frame reads it through `CosmicEntropy`.
- **Trad (fallback):** latitude band + season + cell noise when the cosmic feed is stale or absent.
- **One rule, not a coexistence:** `weather.gd` does not mix the two for the same tick. The returned
  `source` field is the truth for that moment (`cosmic` or `trad`).

That matters for lore: the world is not “weather ’cause magic.” It is “weather ’cause the sky
keeps score.” The noir-lore fan is the same sky-watchers who read the Concord signs — the aurora is
not decoration, it’s the sky writing.

The band vocabulary the world already uses (from `weather.gd`):
- `clear`, `cloudy`, `rain`, `storm`, `aurora`

The five authored weather events in `game/data/weather_events/` —
`weather_aurora_window.tres`, `weather_fog_mystery.tres`, `weather_kp_gate.tres`,
`weather_storm_pack.tres`, `weather_bloom_stir.tres` — are not separate weather systems. They are
the *named moments* the law lets the world hand the traveler. Storms stir hordes (the `storm_wolves`
horde is the pack that answers a storm); the Bloom Stirs wakes the Bloom cull in the gloam; the
aurora opens a window the sky “writes”; fog is the treeline watching; and the tempest gate is the sky
answered back.

---

## What the player is told — separate from what actually happens

The world’s honesty law splits these. Every event below has (a) what the sky announces, (b) what the
law does, and (c) one in-world rumination a keeper would recite. The announcement is a `notify_message`
line from the event’s `.tres`; the law is what `weather.gd` + `weather_event_service` actually do;
the rumination is lore if you want a campfire voice for it.

### 1. Aurora Window — `aurora_window`

**What the sky announces (from the .tres):**
> “An aurora unfolds — the sky is writing. Something may be answered.”

**What the weather law actually does:**
- A `trigger_kind = 2` window (Aurora) with `aurora_min = 0.5`, a 10-minute cooldown, and an
  `open_window_sec = 1800.0` — so the sky opens an answerable door and leaves it open for half an hour.
- No horde is stirred. No pack answers. The aurora itself is the event. If the traveler does nothing,
  the sky writes anyway.
- The aurora is the *band* the weather-service law paints over the pole — it is not the same as a
  storm. A storm is wind; an aurora is the sky answering.

**One rumination (campfire, keeper voice):**
> “The sky does not warn you with aurora. It waits until someone bothered to look up, and then it
> tells them what it saw. If you ignore it, you’re the one who stopped the conversation.”

---

### 2. Storm Pack — `storm_pack`

**What the sky announces (from the .tres):**
> “The storm stirs the wilds — something is coming.”

**What the weather law actually does:**
- A `trigger_kind = 0, 1` window (storm/rain/tempest) with `storm_wolves` as the stirred horde,
  `stir_waves = 2`, cooldown 240 seconds, `aurora_min = 0.5`, and `band_names =
  ["storm", "tempest", "rain"]`.
- The law doesn’t “send the storm.” It stains the sky and lets the wilds answer. If the sky is loud
  enough, the wolves rise. If the traveler’s not there, the horde still forms — the sky does not
  negotiate with the player.

**One rumination (campfire, keeper voice):**
> “A storm doesn’t bring wolves. The wolves were already waiting for the storm. The weather just gave
> them permission to show up without asking who was watching.”

---

### 3. Fog Watchers — `fog_mystery`

**What the sky announces (from the .tres):**
> “Fog settles low — shapes watch from the treeline. The sky listens tonight.”

**What the weather law actually does:**
- A `trigger_kind = 1` (cloudy) window with `band_names = ["cloudy"]`, cooldown 900 seconds,
  `open_window_sec = 600.0`, and **no stirred horde**. The fog is the event; no pack answers. The
  “shapes watching” is the sky posture, not a summoned fight.
- This is the event that makes the treeline the witness. It is quiet by design.

**One rumination (campfire, keeper voice):**
> “Fog doesn’t come to hide things. It comes so the things in the treeline don’t have to bother hiding.
> The difference is the whole damn difference.”

---

### 4. Tempest Gate — `kp_gate`

**What the sky announces (from the .tres):**
> “The tempest burns green — the gate is open. Answer it.”

**What the weather law actually does:**
- A `trigger_kind = 2` (Aurora) window with the hardest gate of the five: `aurora_min = 1.0`,
  cooldown 3600 seconds, `open_window_sec = 900.0`, no stirred horde, and the sky answers *green*
  before it’s answerable. This is the event that says “the sky wrote something worth risking for.”
- The law is still the aurora band — just the most demanding version of it. The traveler has to arrive
  under a stricter sky and still have the patience to answer.

**One rumination (campfire, keeper voice):**
> “The gate is open for half an hour and you have the whole day to get there. That’s the trap. The sky
> isn’t late. You are.”

---

### 5. The Bloom Stirs — `bloom_stir`

**What the sky announces (from the .tres):**
> “The sky turns active over the gloam — something the Bloom took is walking out of the trees.”

**What the weather law actually does:**
- A `trigger_kind = 0` window (storm/rain/tempest — the same trigger kind as `storm_pack`) with
  `band_names = ["active"]`, `aurora_min = 0.5`, cooldown 480 seconds, `stir_waves = 2`, and
  **`bloom_cull`** as the stirred horde.
- Unlike `storm_pack`, it is **zone-scoped**: `zone_ids = ["zone_forest_meadow",
  "zone_dungeon_forest_depths"]`. The cull only walks out where the Bloom sleeps deepest — the same
  two zones `prd-story.md` names as the Bloom’s strongest ground. A storm stirs the wolves anywhere;
  the Bloom stirs the cull only in the gloam.
- No `open_window_sec` (0.0): this event has no answerable door to arrive at. Its whole output is the
  stirred horde — the sky is not writing a key here, it is *rattling the trees*.
- Because the trigger kind overlaps `storm_pack`’s, an “active” band in the gloam is the one weather
  moment where the wilds’ answer is **Bloom-touched**, not lupine.

**One rumination (campfire, keeper voice):**
> “A storm calls the wolves and you hear them coming. This one you don’t hear at all — you just notice
> the treeline has grown eyes, and the eyes are the wrong colour. That’s not weather. That’s the
> garden remembering it used to have a keeper.”

---

## The seven hordes (as authored) — what they are, not what the lore invents

The hordes already exist in `game/data/hordes/`. Their *data* shape is the truth; the lore below is
the campfire read of them.

| id | display_name | shape in the data | one-line campfire read |
|---|---|---|---|
| `storm_wolves` | Storm Wolves | 2 waves; first 4 wolves, second 5 wolves + 3 slimes; rewards 200 gold / 120 XP; scales by level | the pack the storm stirs — the one the weather event already names |
| `trollmoot` | Trollmoot | 3 waves escalating from slimes → slimes + wolves → wolves + 2 troll_elite; boss = troll_elite chieftain; rewards 1500 gold / 800 XP | the hearth fire’s day off — three waves, one chieftain, every traveler gets to see it |
| `haven_siege` | Siege of Haven | 3 bandit campaigns escalating toward a troll_elite boss-optional wave; rewards grow 300/400/500 gold, 150/200/250 XP | the village’s weather day — the HordeEventService can drag it in when the sun does what the Concord signs read |
| `boss_gauntlet` | Gauntlet of the Void | 3 pure boss waves (void_lord x3) with boss names Vault Warden / Void Ascendant / The Unmaker; each wave rewards per boss; no boss = finish after the last wave | the vault’s door practice — three doors, three names, one unpacking a traveler earns |
| `vault_seal` | Vault Seal | 2 waves (slimes → bandits + slimes); dungeon instance scope; boss = void_lord “Vault Warden”; rewards 3000 gold / 1500 XP | the dungeon’s own answer to the sky — ever warded, never cute, the real test of whether a traveler’s ready for the vault |
| `bloom_cull` | The Bloom Cull | 3 waves (5 feral_spore_spider → 4 blight_lizard + 2 rust_root_crab → 4 feral_spore_spider + 2 shrike_owl); boss = bloomwrought_warden; open-world (`instance_scope = ""`); rewards 1800 gold / 900 XP | the Bloom Stirs’ answer — the cull the active sky walks out of the gloam, bossed by the warden still on duty |
| `bloom_descent` | Descent into the Bloom | 3 waves (6 feral_spore_spider → 5 blight_lizard + 3 rust_root_crab → 3 shrike_owl); boss = bloomwrought_warden, then final boss = sporebound_matriarch; `instance_scope = "dungeon"`; rewards 3600 gold / 1900 XP | the dungeon’s descent — the same cull, but it ends where the Bloom’s oldest node keeps making tenders |

**Honest read on the horde file:** the horde data is *wave-by-wave* and *mixed-template*. The
`storm_wolves` file is 2 waves of 4 wolves → 5 wolves + 3 slimes. The `trollmoot` file is slimes →
slimes + wolves → wolves + 2 troll_elite with its boss. The `haven_siege` file is three bandit waves
with an optional final boss wave. The `vault_seal` file is two waves + void_lord boss, dock-scoped.
The `boss_gauntlet` file is three pure boss waves with no trash. The `bloom_cull` and `bloom_descent`
files are the two Bloom hordes: both are three Bloom-touched waves bossed by the Bloomwrought Warden,
and only `bloom_descent` carries the Sporebound Matriarch as its final boss. Those are data facts,
not lore inventions — a campfire voice can say *“three waves of wolves and slime”* only if the data
says so, and the lore should resist making it prettier than the data allows.

---

## The three Concord signs (lore against the sign data)

The sky’s *code* is a day’s glyph order, assembled from who saw what when. There are **three signs**,
but the law draws **four windows per day** (`sign_service.gd`, `WINDOWS_PER_DAY = 4`), so a day’s code
is **four glyphs** in window order — not “the three signs’ order.” The traveler’s winner is the
traveler’s winner, and the vault door answers to *that* order — the law is the order, the lore is what
the signs feel like. (This is why `mystery_the_first_vault` says “speak the **four words** in the order
the sky said them.”) From `game/data/signs/`:

- **`sign_the_awakening`** — “The horizon splits along a seam of pale light. The oldest of the Concord’s
  signs: what slept is waking, and the sky remembers it first.” Glyph: `WAKE`. Seen at first light in
  the eastern sky.
- **`sign_the_wandering_grove`** — “A cluster of green-white lights that drifts across the sky over the
  hours, rooted in nothing. The Concord read it as proof that home is a thing you carry.” Glyph: `GROVE`.
  Tracked by caravan folk; leans toward wherever most people gathered that day.
- **`sign_the_sunken_choir`** — “Faint points of light arrange below the horizon line, as if a
  constellation had drowned and kept singing. Not an omen of loss: an anthem that outlived the singer.”
  Glyph: `SUNKEN`. Only visible when the moon is dark.

**One rumination (keeper voice) on the signs:**
> “The Concord doesn’t read signs to know the future. It reads them so the future has witnesses. If a
> sign goes unread, the sky didn’t forget. The Concord did.”

---

## The honest split for the almanac/chronicle task (placeholder — Task 3 can inherit this)

The signs are the Concord’s *sky-code*. The weather events are the sky’s *answerable posture*. The
hordes are the *wilds’ answer* (when the storm stirs them). The aurora window is the *sky’s own
answer*. If a future chronicle wants to rhyme these, it should rhyme them honestly:

- The sky writes (aurora gate / sky-code signs).
- The wilds answer when tugged (storm pack → storm wolves; the Bloom Stirs → the Bloom cull in the
  gloam; siege horde when the sun does what the signs read).
- The Concord keeps score so a traveler can answer the sky back (the daily “Watch the Sky” quest, the
  Daily sky-crate reward — real data, real quest).

**Do not invent** an aurora–horde relationship that the data doesn’t show: the aurora window today
stirs *nothing*. Two weather events stir a horde — the storm pack (`storm_wolves`) and the Bloom Stirs
(`bloom_cull`, gloam-scoped). If lore wants an “aurora summons the vault seal,” it’s inventing a law
the data doesn’t have. Flag it instead.

---

## The honesty rule (one sentence for the board)

**Announcement ≠ event, event ≠ horde, horde ≠ weather.** Each is a real, separate part of the world’s
law. A campfire voice may cozy them together, but the next sentence in the same voice should still
leave the boundaries honest — because the sky doesn’t lie, and neither does this world.
