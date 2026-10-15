# NPC Voice Profiles + Extended Dialogue Drafts — Synmergia

> **Scope rule (from the board):** everything here is `labs/` lore. `game/`
> is read-only context. Do not edit GDScript, `.tres`, or any schema file
> from this pass. A person or agent lands the good parts later.
>
> **Grounded in the actual data this session read:** 9 NPCs under
> `game/data/npc/`, 5 real `DialogueData` nodes under `game/data/dialogues/`.
> Every dialogue line below is tagged with a real existing dialogue node id,
> and every trigger condition is named against weather bands/weather-event
> kinds that already exist (`storm`, `rain`, `cloudy`, aurora window).
> Where the data rules I would invent a schema field, I flag it instead.

---

## The cast (as authored)

| id | display_name | zone | role in the world | greeting flavor |
|---|---|---|---|---|
| `npc_village_elder` | Village Elder | `zone_village_center` | keeper of ancient lore; first conversation the player has | “Welcome, traveler. The village has been troubled by wolves...” |
| `npc_blacksmith_village` | Village Smithy | `zone_village_center` | repair/forge stall; the village’s practical fixer | “Good to see ye, traveler. Bring me yer worn gear.” |
| `npc_herbalist_village` | Herbalist | `zone_village_center` | potions & supplies stall; the village’s healer voice | “Welcome! I have remedies for what ails you.” |
| `npc_merchant_general` | General Merchant | `zone_village_center` | general store + vendor craft shelf; the village’s passing-trade voice | “Take a look at my wares!” |
| `npc_armory_capital` | Royal Armorer | `zone_nexus_central` | capital’s premium weapons/armor stall | “Fine arms and armor, straight from the forge.” |
| `npc_skill_academy_capital` | Master Trainer | `zone_nexus_central` | skill books / respec / signature ability at level 60 | “Greetings, warrior. Would you like to expand your combat knowledge or choose your signature ability?” |
| `npc_deep_warden` | Deep Warden | `zone_deep_root_camp` | keeper of the Root Camp, counts the glow tides, tends the first hearth ever lit down there | “You came down the sky way, or up from nothing? Either way: the glow tide is rising. Sit.” |
| `npc_salvor_wreck` | Mag the Salvor | `zone_sundered_sea` | wreck shoal salvor; charts the tide, marks crates, files what it keeps | “You’ll be wanting rope, boots, and nerve. The shoal takes all three.” |
| `npc_ferryman_sundered` | Old Brack, the Ferryman | `zone_sundered_sea` | keeper of the crossing since the strait closed; now sails twice a tide | “Tide’s turning. You crossing, or just gawking at the wreck?” |

**Honest count note:** the world has 9 authored NPC data files and 5 authored dialogue nodes on disk right now
(`village_elder_greeting`, `merchant_greeting`, `deep_warden_greeting`, `sundered_salvor_talk`,
`sundered_ferry_talk`). The village NPCs currently reach the elder *through* the elder’s single
greeting node (wolf hunt / herb gathering are quest offers, not separate chat nodes). That gap is real
and visible in the data; the “existing dialogue node id” tags below use what is actually there.

---

## Idiom for the village (the elder as chorus)

The Village Elder already speaks as the village’s memory. Every extra line from her should keep that
register: patient, slightly distant, fond of the place more than of people, willing to tell the
traveler the ugly part and then let them walk away from it.

**Existing voice sample (village_elder_greeting, node 0):**
> “Greetings, young one. You stand in the Village of Haven, a sanctuary at the edge of the Gloomwood.
> Few travelers find their way here.”

**Voice rules:**
- She does not sell. She explains.
- She names the weather like a person who has kept a roof through it. Rain is ordinary; storms are
  the ones she remembers.
- She never promises safety. She promises witness.

**Five signature phrases (elder):**
1. “The Gloomwood keeps its own counsel. So do we.”
2. “Storms pass. The fields do not forgive a late planting.”
3. “You hear that wind? That is the strait clearing its throat again.”
4. “We do not 설명하기 the old roads. We keep them.”
5. “Come back when you have something worth telling me.”

**Voice-note on existing script law:** the elder’s current greeting already uses “Greetings, young one”
and “The village has been troubled by wolves.” Future lore adds to her idiolect, never overwrites the
existing greeting/data — that’s the same honesty law that keeps the capitol road real.

---

## Existing dialogue coverage, as-is

These are the five dialogue nodes that exist today. Notes below are what each already does, then what
the world would plausibly add (not commit-ready data, just the shape of it).

### `village_elder_greeting` — Village Elder (zone_village_center)

**Exists:** three nodes — a greeting, “what is this place,” and “work for me” that leads to the
wolf-hunt pitch. The elder already names the Darkwood and Shattered Mountains and the weekly trade
caravans.

**What the world would plausibly add (shape only):**
- a “farewell” branch that gives the player the elder’s name only if they’ve done a favor first
- a rain-branch line that remembers a past storm differently than a storm branch
- a daylight-only “the sun’s over the western fields” version that becomes “the sky’s doing that again”
  under aurora

**Flags (missing schema / behavior, do not invent pure-dialogue fields without data):**
- the elder’s current dialogue text is a static `text` field in the node dict; a “weather-aware variant”
  would want either a weather-condition tag on a choice/node or a separate variant list per condition —
  not present in `DialogueData` today. Flag as a schema/behavior decision, not a lore item.
- the elder has no explicit “time of day” or “sky tint” input into the greeting today; aurora/fog/rain
  awareness would need a hook in `DialogueService` or the NPC interaction path, not just richer text.

### `merchant_greeting` — General Merchant (zone_village_center)

**Exists:** two nodes — wares pitch + “just passing through.” The merchant already says they buy
unwanted items.

**What the world would plausibly add (shape only):**
- a “what’s the weather doing to your prices” line — shoal prices exist in lore, so a village merchant
  who complains about mud season or cloudy travel is consistent
- a repeatable r familiarity line after first purchase

**Flags:**
- pricing story exists in `NPCData` (`buy_multiplier`, `sell_multiplier`, `buy_categories`,
  `sell_categories`), but there is no weather/passenger/rush markup in data today. If you want “storm
  season raises rope prices,” that’s a data shape, not a dialogue editing task.

### `deep_warden_greeting` — Deep Warden (zone_deep_root_camp)

**Exists:** five nodes — where are we, why is the rock glowing, work, farewell. Best existing voice
in the file: “under everything,” “the hollow has a floor — you are standing on it,” “that is not stars,
that is the INSIDE of the world over your head.”

**What the world would plausibly add (shape only):**
- a glow-tide variant that changes with the strata’s breathing rhythm (existing lore: “Strata glow. It
  breathes once a day — high tide when dawn hits the surface, low tide when their sun lets the wall
  rest.”)
- a “someone’s been counting wrong” dry line when the traveler asks about the tides a second time
- a clearer sense that the Warden is alone but not lonely — counts tides because somebody has to

**Flags:**
- the Warden’s dialogue today is already the richest in the set, and the glow-tide lore is strong; the
  main missing piece is whether the weather system ever plays the strata’s “high tide / low tide” state
  back to the traveler — that is a service/telemetry question, not a dialogue line.

### `sundered_salvor_talk` — Mag the Salvor (zone_sundered_sea)

**Exists:** four nodes — opening pitch, the barque’s hold rumor + diving fee honesty, stock pitch,
freight quest pitch. Best voice in the file: “Salvage isn’t fashion, it’s patience: I sell what drifts,
I buy what you haul.”

**What the world would plausibly add (shape only):**
- a “tide’s up / tide’s down” branching line in her shop talk — her whole pitch is tide memory
- a storm-warning line when the sky’s storm band is active: “you’re here on a bad sign, traveler”
- a fare-thee-well that remembers the number of times the traveler has returned

**Flags:**
- the salvor already references `shoal_freight_quests`; that quest line is the natural replay hook
- the diving-fee honesty is excellent and should stay canon. Any new line must preserve the explicit
  anti-lying voice — she is the one NPC who will say “I do NOT lie about the fee.”

### `sundered_ferry_talk` — Old Brack, the Ferryman (zone_sundered_sea)

**Exists:** four nodes — opening, the wreck-shoal story, what happened when the strait closed, freight
quest pitch. Best voice in the file: “The shoal took the barque once — HER, the first one. Now she’s
the ford itself.”

**What the world would plausibly add (shape only):**
- a passage-cost line that changes when the sky’s cloudy/storm band is up: “the crossing doesn’t care
  about your schedule, but it cares about the wind”
- a “I kept a dinghy alive through what the wall scattered” follow-up the player can ask twice
- a farewell that warns about the shoal in tide terms, not abstract danger

**Flags:**
- Brack already owns the “twice a tide” line in his NPC description. Keep that canon; it’s the ferry’s
  whole identity.
- The ferry’s practical crossing rules (timing, cost, weather sensitivity) are likely service/data work,
  not dialogue-only. Flag the seam.

---

## New line bank (draft, tagged to existing nodes — not committed data)

Each line is offered as a *possible* addition; the “condition” column is what would gate it if this
were data. None of this changes the existing `.tres` texts — it is the shape of a richer conversation,
not a replacement.

### Village Elder — `village_elder_greeting`

| new line | condition | voice |
|---|---|---|
| “The sky’s been loud today. You felt it before you found the gate, didn’t you?” | first meeting + sky band != clear | elder as witness |
| “We’ve had wolves before the rain came. The rain ends, the wolves remember.” | after fight nearby / storm band | elder as memory |
| “The road bends for the plaza, not the cart. People like you are why.” | farewell / after quest offers | elder as place-keeping |
| “Come back when the cloud breaks. I’ll have more to tell you then.” | farewell, cloudy band | elder as patience |
| “You’re the first traveler I’ve seen since the tide turned sour.” | first meeting only, aurora window / fog | elder as rare-meeting |

### General Merchant — `merchant_greeting`

| new line | condition | voice |
|---|---|---|
| “Mud’s up past the gate. Boots cost more when the road remembers the rain.” | cloudy band / rain band | merchant as practical |
| “I buy what the storm throws up, but I don’t pretend it’s cheap.” | storm band, first meeting | merchant as honest |
| “Somebody wandered in last week with a map that didn’t match the ground. Took me three days to stop laughing.” | repeatable, 2+ visits | merchant as village texture |
| “If you’re carrying ore, keep it under your cloak — mine’s seen pickpockets with better manners.” | sell categories present | merchant as cautions |

### Deep Warden — `deep_warden_greeting`

| new line | condition | voice |
|---|---|---|
| “The strata breathed high tide at dawn and low tide at dusk — unless the sky did something rude. Did it?” | cloudy band / aurora window | Warden as strata-reader |
| “You asked twice about the tides. I’ll answer once the same way, then stop.” | second visit to node 2 | Warden as dry |
| “The wall hums louder when the weather does. You felt that, right? Good. You’re listening.” | storm band / after fight nearby | Warden as tuning |
| “Stand still at the shelf’s edge. If the hum does not answer you, you’ve done it wrong.” | “work” node, first time | Warden as task-setter |

### Mag the Salvor — `sundered_salvor_talk`

| new line | condition | voice |
|---|---|---|
| “The tide’s up today. That means the barque’s hold is still breathing. That means my fee is still honest.” | tide up / cloudy band | Mag as tide-truth |
| “You want a fair price? Come back when the sky isn’t trying to keep the wreck for itself.” | storm band | Mag as weather-aware |
| “Three crates. The tide lifts them three times a day if the sea feels generous. I do not feel generous.” | freight quest branch, repeat | Mag as dry |
| “You came back. Either you got what you came for, or the sea lost it. I charge the same either way.” | repeatable return | Mag as even-handed |

### Old Brack, the Ferryman — `sundered_ferry_talk`

| new line | condition | voice |
|---|---|---|
| “Wind’s in the strait’s teeth. The barque runs, but she doesn’t like it. You ride my nerves and my coin.” | storm band / cloudy band | Brack as crossing-truth |
| “The shoal doesn’t care about your timetable. It cares about the moon. So do I.” | first meeting, fog | Brack as tide-truth |
| “The first barque is still down there. If you hear her groan in a storm, don’t answer.” | storm band, first meeting | Brack as warning |
| “Mind the shoal. She took the barque; she’ll take slower ships.” | farewell, windy weather | Brack as recurring warning |

---

## The Sundered Sea pair through the tide lens

Mag and Brack are the only non-village NPCs with real weather-shaped talk today, and they’re both on
the same coast. The best version of them keeps them separate:

- Mag reads **what the water keeps** (the barque, the wreck, the hold, the fee).
- Brack reads **what the water lets you cross** (the shoal, tide, the barque’s channel, the first barque).

They already reference each other economically (Mag’s freight quest turns into Brack’s crew). Future
lines should preserve that: Mag is the hold’s memory; Brack is the crossing’s patience. Never make them
agree about anything interesting.

---

## Honest flags — what this lore would need from data/services, not from this doc

1. **Weather-aware dialogue variants** — `DialogueData` nodes today have one `text` per node. To gate a
   line on “cloudy band,” “storm band,” or “aurora window,” the design needs a decision: per-node
   condition tags, per-node variant lists, or a service-side injection. The service seam is probably
   `DialogueService` or the NPC interaction path (`NPCEntity.on_interact`). This doc does not choose;
   it just says the seam exists and must be chosen before lines become data.

2. **Sky-band input to NPC talk** — `weather.gd` already returns band names (`clear`, `cloudy`, `rain`,
   `storm`, `aurora`) and the weather-event system already has kinds (`aurora_window`, `storm_pack`,
   `fog_mystery`, `kp_gate`). The dialogue system today likely has no sky-band hook. Flag: if you want
   the elder to say something only under aurora, that’s a service-hook decision, not a text decision.

3. **Time-of-day / sky tint input** — the sky already has day-phase and sky-tint data on the signs
   (`sign_the_wandering_grove` etc.), and the globe even paints a sky-shade gradient. Whether NPC talk
   can key off “dawn / noon / dusk” is a seam decision. Flag it.

4. **NPC voice memory / repeat state** — the world’s NPC data has no per-player “times met” field
   visible in `NPCData`. Repeatable “you’ve been here before” lines would need either a persistent
   counter on the interaction or a quest/favor state. Flag it as a data seam.

5. **The elder currently has no separate farewell node** — her single greeting node leads to a farewell
   choice that ends the talk. If you want a real farewell branch with elder voice, that’s a dialogue-node
   addition (valid in data), not a code change. Feasible in `.tres`; just say so.

6. **Mag + Brack reference the same quest hook (`shoal_freight_quests`)** — if you want a line that
   compares the two, that’s already supported by existing offering refs. No flag; just don’t invent a
   third quest to make them talk to each other.

---

## Consistency rules for any future addition

- The elder speaks for the village’s memory; the merchant speaks for the village’s trade; the Warden
  speaks for the strata’s breath; Mag speaks for the wreck’s fee; Brack speaks for the crossing’s tide.
- No NPC contradicts the existing world facts: the strait closed and opened; the barque exists; the
  shoal is real; the strata glows; the village has wolves; the capital has a forge; the deep is under
  everything.
- No NPC promises safety. The world is honest about risk; NPCs are no exception.
- If it’s weather-aware, it names the weather like a person who has kept a roof through it — not like a
  broadcast. Storms are remembered; rain is ordinary.
