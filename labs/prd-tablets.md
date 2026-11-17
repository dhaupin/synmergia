# PRD: Tablets and the Interaction Layer

> **Status:** DESIGN (equipment slice SHIPPED) · **Owner:** World / Interaction
> **Last updated:** 2026-11-17

> The tablet is not a menu. It is the hand the dormant world answers.

## 1. One-line

Every player carries a soulbound Convergence tablet that reads, wakes,
attunes, and records the dormant things in the world. It is the physical
form of the game's one verb: **find the dormant thing, wake it.**

## 2. Canon

Synmergia is a world of patients, not monsters (story sec. 5). The
Convergence left machines, roads, wards, and waypoints asleep. Most people
walk past them. A **tablet-bearer** hears the answer.

A tablet is a palm-sized fragment of Convergence machinery:

- It is old, repairable, and personal; it is not a phone or a quest log.
- Its teal light is the player's diegetic interface. The HUD is a
  projection of the tablet, not a separate layer of glass.
- Waking is permanent and shared. A waypoint one player wakes stays awake
  for everyone on the shard (story sec. 7).
- The tablet does not make the bearer special by rank. It makes the world
  legible. The player's progression is what they have woken, not what the
  tablet has killed.

The starter tablet is **the Wayfarer's Tablet**: common, cracked, and
indestructible. It is the first thing a new character owns and the last
thing they can lose.

## 3. Player promise

1. **Never tabletless.** A character always has a tablet. It cannot be
   sold, traded, dropped, destroyed by durability, or stripped by full
   loot. If a save or migration loses it, the next world entry restores a
   soulbound Wayfarer's Tablet.
2. **Always readable.** The tablet's baseline world ward works without a
   charge, a consumable, or a vendor visit. It mitigates authored world
   hazards, not combat schools.
3. **One verb, many surfaces.** The same four interactions (`READ`, `WAKE`,
   `ATTUNE`, `RECORD`) work on waypoints, doors, movers, caches, wards, and
   inscriptions. New content should reuse the grammar, not invent a new
   key.
4. **The world changes.** A wake is an event with a permanent record and a
   visible consequence. It is not a daily reset button.
5. **No twitch tax.** Reading is deliberate. The tablet rewards attention,
   pattern recognition, and return visits; it never requires frame-perfect
   input.

### Non-goals

- A second combat weapon or a stat-stick. Tablets do not add attack,
  spell, healing, crit, or armor power.
- A shop UI, auction house, or remote mailbox.
- A replacement for quests, waypoints, or mounts. It is the shared verb
  those systems expose.
- A pay-to-wake surface. See sec. 12.
- A reason to stand still in a menu for minutes. Tablet actions are
  short, contextual, and return the player to the world.

## 4. Equipment model (shipped now)

A tablet is real equipment, not a consumable or a quest token.

| Field | Value |
|---|---|
| `item_category` | `ItemCategory.TABLET` (10) |
| `accessory_type` | `AccessoryType.TABLET` (8) |
| `equip_slot` | `EquipSlot.TABLET` (15) |
| baseline ward | `tablet_world_ward` > 0 on every tablet |
| focus | `tablet_domain` (`WORLD`, `HEAT`, `COLD`, `STORM`, `MIASMA`, `DEEP`, `VOID`) |
| focus ward | `tablet_domain_ward`, added only for the focused hazard |
| durability | slow decay; a broken tablet stops guarding but remains equipped |

`WorldHazard` is the hazard-key authority. The sea's `drowning` tag
normalizes to `deep`; future weather, traps, and zone effects use the same
keys. `Item.get_world_ward()` is the item read;
`InventoryComponent.get_world_ward()` and the shared `Entity` /
`PlayerBase` surface expose it to damage.

**One socket.** A character equips exactly one tablet. Tablets do not stack,
do not dual-wield, and do not contribute to the combat `damage_resists`
lane. A better tablet replaces the old one; the old tablet is not consumed
by the swap.

### Starter tablet

`acc_tablet_wayfarer` is the common, world-focus starter:

- `soulbound = true`, `unique = true`, `bind_on_pickup = true`
- `max_durability = 0` and `durability_loss_rate = 0` (cannot break)
- baseline `tablet_world_ward = 0.03`, `tablet_domain_ward = 0.02`
- granted by `StarterKitData.guaranteed_items`, not by a role row, so
  every role receives it
- granted directly into the tablet socket by `StarterKitService` when the
  bag is full
- restored on world entry by `StarterKitService.ensure_tablet()` if the
  character has no tablet in equipment or bag

The starter is deliberately weak. It is the floor of the interaction
layer, not a reward that makes early tablets pointless.

### Head and breather are different layers

The head slot is a helm. The breather is its own layer.

- `EquipSlot.HEAD` carries helmets, including sealed diving helms. Helmet
  armor, stats, and resists remain active underwater.
- `EquipSlot.BREATHER` carries air gear (`acc_breather_*`). Only this layer
  feeds `OceanService.breather_for()`.
- A sealed diving helm is `arm_diving_helm` (HEAD armor). It has no
  `breath_multiplier`; it is a helm, not a tank.
- A load-time slot sanitizer accepts only a breather in `BREATHER` and
  only a helm in `HEAD`. Any cross-slotted item is moved to the bag, never
  auto-swapped; there is no necklace fallback and no second air lane.

## 5. Interaction grammar

The tablet exposes four verbs. Every interactive object authors which verbs
it accepts, its range, its failure copy, and its consequence.

| Verb | Input | What it does | Typical use |
|---|---|---|---|
| `READ` | tap / `E` / gamepad face button | Reveals the object's dormant signature, owner, and needed key. No state change. | inscriptions, sealed doors, memory motes, unknown machines |
| `WAKE` | hold / confirm | Spends the authored key and fires the wake event. Permanent, shared, logged. | waypoints, gates, movers, stations, dwellings |
| `ATTUNE` | hold + focus | Points the tablet's focus at a hazard or machine for a bounded window. | heat vents, storm anchors, deep currents, bloom seals |
| `RECORD` | tap | Writes the discovery into the bearer's journal and the shard ledger. No world mutation. | first sight of a site, a solved pattern, a safe route |

### Readability rules

- A dormant object has a **signature**: a shape, a pulse rhythm, and a
  short authored phrase. The tablet shows the signature before it shows a
  verb.
- `READ` is always safe. It cannot trigger a trap, consume a key, or pull
  a mob. It can be repeated.
- `WAKE` is confirmed, never a single accidental tap. The confirmation
  names the object and the consequence in plain language.
- An object that cannot be woken yet still `READ`s. The tablet says what
  is missing; it does not show a grey mystery box.
- Failure copy is diegetic: "The seal wants a tide-word," not
  "Requires item 418."

### Range and timing

- Default read range: **6 m**; default wake range: **3 m**.
- Line of sight is required for `READ` and `WAKE`. A wall, a closed door, or
  deep murk blocks the signature.
- Reads are instant. Wakes take **1.5-4 s** by object tier, with a visible
  channel and a cancellable hold. Taking damage cancels a wake and leaves
  the key unspent.
- `ATTUNE` lasts **10-30 s** and has a per-object cooldown. It is not a
  permanent buff.
- No global cooldown on `READ`. It is the exploration verb.

## 6. World objects

Every object below is a data record, not a bespoke script. The first
implementation can use a shared `tablet_site` resource with a type enum;
new content adds records, not code paths.

| Object | Dormant state | Verbs | Wake result | Counterplay / limit |
|---|---|---|---|---|
| Waypoint stone | dim ring, no hum | READ, WAKE | Fast-travel node joins the network | One wake per shard; no combat teleport |
| Gate / door | sealed seam, cold rune | READ, WAKE | Passage opens for everyone | Key is authored; cannot be bought |
| Ancient mover | folded chassis, sleeping statute | READ, WAKE, ATTUNE | Route/vehicle wakes; schedule becomes live | Wake key is a puzzle, effort, observation, or ritual (movers PRD) |
| Memory mote | floating dust, repeating glyph | READ, RECORD | Journal entry / map annotation | No stat reward; first record earns credit |
| Hazard ward | hot/cold/storm seam | READ, ATTUNE | Bounded mitigation in a small volume | Timer; does not replace gear or tablets |
| Cache / reliquary | sealed lid, no handle | READ, WAKE | Loot or schematic appears | One-time per shard; server-authoritative |
| Inscription | dead glyph line | READ, RECORD | Translation / lore / quest clue | No world mutation |
| Dormant station | cold forge/anvil/loom | READ, WAKE | Crafting station becomes usable | Station ownership/economy rules still apply |
| Dwellings / doorpost | dark clasp | READ, WAKE | House becomes claimable/enterable | Housing rules own ownership |
| Bloom seal | breathing membrane | READ, ATTUNE, WAKE | Contains or opens a bloom route | Faction consequences; never a free cleanse |

### Object data contract (future resource)

A `TabletSiteData` record should own:

```
id, display_name, site_type
read_range, wake_range, channel_seconds
required_key_id / required_flag
wake_event_id
failed_read_copy, failed_wake_copy
focus_domain (optional)
one_shot (bool), shared (bool)
```

The server owns the wake. The client sends `site_id`, `verb`, and its
observed position; the server validates range, line of sight, key, and
cooldown before emitting `ancient_wake_*` or the site's own event. The
client never sends "wake succeeded."

## 7. Progression

Tablet progression is **legibility and access**, never combat power.

| Tier | Example | Ward (baseline + focus) | Focus | Read range | Wake channel | Extra |
|---|---|---|---|---|---|---|
| 0 | Wayfarer's Tablet | 3% + 2% | WORLD | 6 m | 1.5 s | starter, soulbound, cannot break |
| 1 | Clay Tablet | 3% + 2% | WORLD | 7 m | 2 s | first craft/quest tablet; repairable |
| 2 | Ember / Rime / Tide | 4% + 10-12% | one hazard | 8 m | 2.5 s | stronger focus ward |
| 3 | Mycel / Storm | 5% + 15-16% | one hazard | 9 m | 3 s | deeper focus |
| 4 | Void Tablet | 7% + 25% | VOID | 9 m | 3 s | endgame focus; still no combat stats |

> Values in the table are the current seed intentionally; balance may move
> them, but the no-combat-stat rule does not.

Rules:

- Higher tiers buy **mitigation, range, or a faster channel**, not damage.
- A focused tablet is better in its hazard and worse as a generalist than
  a same-tier WORLD tablet. Choice is horizontal.
- Tablets do not have sockets, gems, or random rolls in this PRD. If
  sockets arrive later, they must follow the same no-combat-stat rule.
- Tablet wear is slow and repairable. The starter is exempt from wear.
- The **first wake** of a unique site is a permanent service record. It
  names the first waker forever; it does not grant a combat stat or a
  purchasable rank (movers PRD sec. 31).
- Group wakes are allowed. The record names the first waker; participants
  receive the shared consequence and their own journal entry.

## 8. Starter tablet and never-tabletless safety

The guarantee is a **system invariant**, not copy.

1. `StarterKitData.guaranteed_items` includes
   `acc_tablet_wayfarer` for every role.
2. `StarterKitService` merges guaranteed items into every role's grant.
   Role rows can be empty; the tablet still arrives.
3. The tablet is equipped directly into `EquipSlot.TABLET`. A full bag
   cannot block it.
4. `soulbound`, `bind_on_pickup`, and `unique` stop transfer, trade, sale,
   and ground drops.
5. `DeathFeatures` skips soulbound/bound items in full-loot stripping, in
   both equipment and bag passes.
6. `VendorService.sell_item()` rejects soulbound/bound items with a clear
   message. The inventory Drop action rejects them too.
7. `ensure_tablet()` runs on every world entry. If no tablet is equipped
   or bagged, the character receives a fresh starter tablet. If a tablet
   is bagged and the socket is empty, it is equipped.
8. The starter has no durability loss and zero max durability, so it
   cannot become a broken non-tablet.
9. A save migration that removes an old tablet must leave the character
   with a replacement on next entry; migrations never delete the last
   tablet.

**Hard rule:** no UI flow, quest, trade, death, vendor, or admin action may
end with a character having zero tablets. If a future container (vault,
mail, guild bank) can hold a tablet, the ensure check must include that
container or the tablet must be forbidden there.

## 9. Controls and UX

### Input

| Platform | READ | WAKE | ATTUNE | RECORD |
|---|---|---|---|---|
| Keyboard/mouse | `E` / left click | hold `E` / hold click | `R` + hold | `Tab` in tablet view |
| Gamepad | face button | hold face button | shoulder + hold | d-pad in tablet view |
| Touch | tap | long-press + confirm | two-finger hold | tap journal icon |

No action is bound to a movement key. The tablet never takes camera control.

### HUD

- A small teal ring near the reticle shows a readable signature. It grows
  as the player faces the object; it never covers the object.
- The verb prompt is one line: `[E] Read`, `[Hold E] Wake`, `[R] Attune`.
- The channel bar is anchored to the object, not the screen center.
- The journal records a site once and shows a simple discovered count.
- No minimap wall of icons. A discovered site appears on the map only
  after `RECORD`; a woken site gets a distinct, static glyph.

### Accessibility

- Every prompt has text and an icon; no color-only state.
- Reads are not timed. Wake channels can be extended by an accessibility
  setting (up to 2x) without changing the world result.
- Screen-reader labels name the object, verb, and requirement.
- Reduced-motion mode replaces pulses with a static outline.
- Failure copy is plain language and says what to try next.

### Anti-spam

- `READ` is rate-limited per object (0.5 s), not globally.
- `WAKE` rejects a second channel while one is active.
- Repeating a completed `WAKE` returns the already-woken state; it does not
  re-fire the event or duplicate loot.
- The client cannot farm `RECORD`; the journal accepts one entry per site
  per character.

## 10. Data and authority

- Tablet inventory is the existing `InventoryComponent` equipment map.
- The starter grant is data (`starter_kits.tres` +
  `acc_tablet_wayfarer.tres`), not a hardcoded class check.
- Capacity and loadout rules live in data records; tablets remain one
  fixed slot.
- World sites are server-authoritative. The server validates:
  - the player has a tablet equipped;
  - distance and line of sight;
  - the required key/flag;
  - the site is dormant (not already woken, or is repeatable);
  - the player is not in a duel/instance where waking is disabled.
- Wake events use the existing event/ledger rails and are idempotent by
  `site_id`. A reconnect cannot double-fire.
- The server never trusts a client "read result" for progression. Reads
  are presentation; wakes are mutations.
- Privacy: the journal is per-character; the world ledger is shard-public.
  Do not expose a player's exact position through wake records.

## 11. Integration

| System | Contract |
|---|---|
| Waypoints | A waypoint is a tablet site. `WAKE` adds it to the network; `READ` names its region and cost. |
| Quests | Quest objectives can require `READ`, `WAKE`, `ATTUNE`, or `RECORD` on a site id. The tablet does not replace quest state. |
| Ancient movers | The mover's wake-key is authored per movers PRD. The tablet is the hand, not the key; no purchase opens a wake. |
| Ocean | The diving helm is HEAD armor; the breather is its own layer. Tablet world wards use `deep`; water never disables helm stats. |
| Mounts / gliders | Waking a mount station is a site action. The tablet does not summon or store mounts. |
| Housing | Doorpost wakes are site actions; ownership remains the housing system's law. |
| Factions / territory | A wake can change access or spawns, but never silently transfers territory. Consequence copy is mandatory. |
| Weather | Hazard wards and `ATTUNE` read the same `WorldHazard` keys as tablet mitigation. |
| Death / loot | Soulbound tablets skip full loot. The ensure backstop runs on the next entry if anything else goes wrong. |

## 12. Economy and monetization

- Tablets are earned through quests, crafting, exploration, and faction
  work. The starter is free and permanent.
- No SKU sells a wake, a site key, a tablet tier, or a "wake speed" boost.
- A cosmetic tablet shell may be sold; it changes light color/engraving,
  never range, ward, or channel.
- Repair is a normal service cost. The starter never needs repair.
- Trading a non-soulbound tablet is allowed only if it has never been
  bound; the starter and any `bind_on_pickup` tablet are excluded.
- The first-waker record is a service record, not a paid title.

## 13. Failure states

| Situation | Required behavior |
|---|---|
| No tablet equipped | Tablet verbs are unavailable; `ensure_tablet()` restores on entry. Existing characters get a message, not a soft lock. |
| Broken tablet | Ward is 0; repair prompt; tablet stays equipped. Starter cannot break. |
| Bag full at starter grant | Direct-equip into the tablet socket. |
| Death in full-loot zone | Soulbound tablet is skipped; other gear follows the zone law. |
| Vendor tries to buy tablet | Refuse with "soulbound" copy; no gold changes. |
| Trade tries to include tablet | Refuse before the trade window locks. |
| Disconnect during wake | Server keeps the channel only if it can validate; otherwise the wake is not consumed. On reconnect the site reads dormant or woken truthfully. |
| Two players wake at once | Server serializes by site id; one event fires; both receive the shared result. |
| Save migration loses tablet | Next entry grants the starter. Log the migration, not a silent deletion. |
| Instance/duel disables waking | `READ` still works; `WAKE` returns "not here" copy. |

## 14. Acceptance criteria

The equipment slice is accepted when:

- `EquipSlot.TABLET`, `AccessoryType.TABLET`, and
  `ItemCategory.TABLET` keep their values.
- The starter tablet is in every role's guaranteed grant, is soulbound and
  unique, has zero durability loss, and never enters full loot or vendor
  sale.
- A full bag still receives and equips the starter tablet.
- A returning character with no tablet receives one on world entry.
- A cross-slotted breather or helm is bagged on load; a HEAD diving helm
  remains armor and supplies no air.
- `equipment_capacity.tres` authors 2 rings / 1 amulet / 1 belt / 1 cloak;
  a data override can open 10 rings and 3 amulets without code.
- `HEAD` and `BREATHER` reject each other's items on live equip and on
  save load; `OceanService` reads no other slot.
- A lowered capacity spills overflow to the bag rather than deleting it.
- `test_equipment_capacity`, `test_equipment_vocabulary`,
  `test_character_fresh_kit`, and `test_sundered_deep_economy` pass.

The interaction layer is accepted when future work adds:

- `TabletSiteData` records and a server-validated `READ`/`WAKE` channel.
- Idempotent `ancient_wake_*` events and a per-character journal.
- The first-waypoint tutorial: read, wake, record.
- Two-client tests for shared wakes, duplicate wake races, and reconnect.
- Accessibility checks for text prompts, reduced motion, and extended
  channels.

## 15. Open questions

1. Should a focused tablet's domain ward apply to the whole party in a
   small radius, or only the bearer? (Default: bearer only.)
2. Can a player voluntarily abandon a tablet for a higher tier, or must
   the old tablet be stored? (Default: swap, old tablet returns to bag.)
3. Does `RECORD` earn a small discovery currency, or is it pure journal?
   (Default: journal + first-wake credit only.)
4. Should group wakes require a party, or can nearby strangers contribute?
   (Default: nearby contributors can assist; the first valid waker owns
   the record.)
5. How many tablet shells are cosmetic before the light stops reading as
   "the player's tablet"? (Art review.)
