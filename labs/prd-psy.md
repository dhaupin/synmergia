# PRD: The Psyche of Synmergia (post-religion worldbuilding)

> **Status:** DRAFT -- worldview fixed, mechanics spiking. Sections
> 1-4 are DESIGN LAW: no system may contradict them. Sections 5+ are
> the buildable slice; the Skyward Concord (section 6) shipped first
> (SignService, batch 7).

## 1. What religion is in Synmergia: none

The species of Synmergia do not have religion -- not lost it, not
rejected it: the CONCEPT does not exist. Nobody prays, because there
is no word for prayer. Nobody builds temples, because nothing is
believed to be listening. This is not a setting where gods died; it is
a setting where gods were never an idea.

To the species, the HABITAT is the source of truth. The world is read
the way we read weather: the Bloom's cycles, the Conduit flows, the
behavior of beasts before a storm. Knowledge is empirical and communal
-- "we watched, we remembered, we adjusted." The closest thing to
reverence is ATTENTION. To study something closely is the highest form
of respect a Synmergian can pay.

Design law: no faith mechanics, no prayer buffs, no gods, no
afterlife promises, no priest classes. NPCs never reference creed.
The system vocabulary for what players DO with meaning is:
observation, memory, lesson, and debt-to-the-past.

## 2. Why this matters (product reasons)

- **The take-a-break promise.** Synmergia offers meaning without
  dogma. Players from every real-world background get the SAME
  world: nothing in it asks what they believe, and nothing in it
  judges. Reason, ethics, and morals exist in the world's systems
  (governance, debts, trust) but no religion is bundled with them.
- **Conflict without holy war.** Species and faction conflict is
  material (territory, Conduit flows, ancient tech), never creedal.
  Nobody can declare a crusade -- there is no god to declare it for.
- **Theme tool for stories.** Acts and chapters (section 5) can teach
  the lessons religions teach -- mortality, obligation, repair,
  gratitude -- as RECORDS OF THE PAST WORLD the players excavate,
  not as living faith. The past is a teacher, not a present power.

## 3. What fills the hole: the Concord tradition

Pre-Convergence peoples left behind practices that LOOK like religion
from outside but are not:

- **The Skyward Concord:** a civil calendar of celestial signs.
  Watching the sky was infrastructure (planting, migration, vault
  schedules), and watching together was civic duty. Signs are READ,
  not worshipped.
- **Debt-to-the-past:** the dead built what you live in. The culture
  treats maintaining and unlocking their works as an INHERITANCE
  OBLIGATION -- paying it forward, never as devotion.
- **Lessons, not commandments:** the past world is treated as a
  corpus of case studies. Acts/chapters unlock recorded outcomes and
  the species discuss them the way we discuss history.

## 4. Voice rules for writers

- NEVER write faith language: prayer, holy, sacred, blessed, curse
  (supernatural sense), worship, divine, miracle.
- DO write observational language: sign, omen is ALLOWED only in its
  pre-religious sense ("a sign of rain"), pattern, record, lesson,
  inheritance, obligation, attention.
- NPC reverence = attention and precision ("The smith watches the
  seam of the morning light the way she watches a forge weld").
- Player-facing UI never says "blessing" -- say "attunement,"
  "reading," or "the Concord marks it."

## 5. Acts & chapters: lessons from the past world

Unlockable narrative blocks that teach, as historical record, the
lessons religions teach anyway:

| Lesson (real-world analog)  | In Synmergia it is...                                       |
|-----------------------------|-------------------------------------------------------------|
| Mortality & memento mori    | Excavating a city that planned 400 years ahead and died anyway |
| Repair over replacement     | The debt-to-the-past quests (maintain ancients, do not loot them) |
| Gratitude to predecessors   | Uncovering WHO built each working Conduit and crediting them |
| Ethics without enforcement  | Vault records showing a society that ran on trust audits, not commandments |
| Community obligation        | The sign windows themselves: the code only completes if many watch |

Chapters unlock world content (doors, vaults, skill academies tiers)
so the "lesson" is always attached to something players DO together.

## 6. The Skyward Concord (shipped, batch 7)

The first Concord system: a communal sky clock that makes players
tribal on purpose.

- **Windows:** the day has four 6-hour windows (00-06, 06-12, 12-18,
  18-24 UTC). Each window shows exactly one Sign (data/signs/*.tres,
  SignProfile).
- **Insights:** during a window, a player who "looks up" records an
  insight ( SignService.record_insight ). One per player per window;
  idempotent.
- **The tribal rule:** a window's glyph becomes PUBLIC only after
  REVEAL_OBSERVERS = 3 distinct players record it. Below threshold it
  is rumor. The day's glyph sequence cannot be assembled by one
  person watching alone (well -- unless they attend all four windows).
- **The Ancient code:** the day's four glyphs, in window order, ARE
  the code to TOMORROW's server-wide Ancient unlock (door/vault).
  Determinism: window -> Sign is a pure hash of (day, window), so
  server and clients agree with zero sync traffic.
- **Rollover:** at the day boundary, rumor state wipes (new hunt) but
  unlock history persists.
- **Implementation:** SignService (autoload, after DataService),
  SignProfile schema, data/signs/*.tres (sign_ prefix, filename ==
  id), NotifKind SIGN_WINDOW_CHANGED / SIGN_INSIGHT_RECORDED /
  ANCIENT_UNLOCKED, admin /sign (status, record, force_reveal,
  unlock_tomorrow), DictStore persistence, clock override for tests.
- **Test:** test_sign_service.gd (7 checks) in the runner DEFAULT_SET.

## 8. The Daily Class Blessing (shipped, batch 9)

The retention beat on top of the Concord loop: the assembled sky code
names TOMORROW'S blessed class, and the whole shard's lucky class
plays a boosted day.

- **The wheel:** each round of n = playable-class-count days shuffles
  the classes ONCE (deterministic Fisher-Yates, seed = round epoch)
  and walks the permutation slot by slot. Every class blesses exactly
  once per round BY CONSTRUCTION -- the reroll-if-too-soon rule the
  design asked for holds mathematically (19 classes -> no repeat
  before a 19-day rotation), on every server, from the same data.
- **IT MUST BE EARNED:** day d's blessing is only ACTIVE when day d
  is Ancient-unlocked (the tribe assembled day d-1's code). No solve,
  no buff. Agents may run the reveal outside game processes -- the
  code IS the lottery ticket.
- **The payout (one day, whole shard):** +20% damage (CombatMath
  calculate_hit/calculate_magic_hit -> calculate_damage via the
  blessing_multiplier in the hit_result), +20% healing
  (Skill.calculate_healing), +20% XP (KillRewards._grant_xp), and
  effective level +5 for stat computation
  (CharacterData.get_stat_total). Announced at code-assembly (plan
  tomorrow's login) and again at dawn when it goes live.
- **Almanac:** shows today's blessed class + live state, and
  tomorrow's preview ("if the tribe turns the key").
- **Voice:** the sky does not "bless" in a religious sense -- UI copy
  says "the wheel names X" / "carries the sky's blessing," matching
  section 4's observational vocabulary.
- **Test:** test_daily_class_blessing.gd (hydration x2 rotations,
  determinism, earn gate, all three consumer hooks); loop probe
  extends to the blessing going live after the tribal solve.

## 9. Next slices (not built)

The three consumer slices are BUILT (batch 8):

- **Ancient doors** (`entities/ancient_door.gd`): the payoff entity.
  Tracks `for_day_offset = 1` (TOMORROW's Ancient): completing
  today's code turns the key on the door standing in the world NOW,
  and it re-seals at the next dawn -- daily urgency, no permanent
  unlocks. E-interact resolves via the "ancient_doors" group (same
  pattern as ankhs, 4m radius); sealed doors refuse with the tribe's
  glyph progress, open doors read back yesterday's code. Glow strip
  states: dim = sealed, amber pulse = unlocked-but-unclaimed, bright
  = open; the slab sinks on unlock.
- **Sky rendering** (`entities/sky_sign_renderer.gd`): the current
  window's Sign as a tinted constellation (emissive billboard quads,
  per-sign deterministic scatter from hash(sign_id)). Sealed windows
  render DIM and PATTERNLESS -- a flat ring; the figure only forms on
  reveal. The sky itself withholds what the tribe has not shared.
- **Sky almanac UI** (`ui/components/sky_almanac_ui.gd`, hotkey V,
  MenuManager "sky_almanac"): today's four windows, revealed glyphs,
  observer counts vs threshold, current Sign lore, door state. The
  almanac honors the tribal rule -- un-revealed windows show
  "glyph unknown (N watching)", never the glyph.

Probe: `probe_ancient_loop.gd` runs the whole loop against the real
world scene (insights -> reveal -> code -> door opens -> prompts ->
almanac honesty).

## 8. The Daily Class Blessing (shipped, batch 9)

The retention beat on top of the Concord loop: the assembled sky code
names TOMORROW'S blessed class, and the whole shard's lucky class
plays a boosted day.

- **The wheel:** each round of n = playable-class-count days shuffles
  the classes ONCE (deterministic Fisher-Yates, seed = round epoch)
  and walks the permutation slot by slot. Every class blesses exactly
  once per round BY CONSTRUCTION -- the reroll-if-too-soon rule the
  design asked for holds mathematically (19 playable classes -> no
  repeat before a 19-day rotation), on every server, from the same
  data.
- **IT MUST BE EARNED:** day d's blessing is only ACTIVE when day d
  is Ancient-unlocked (the tribe assembled day d-1's code). No solve,
  no buff. Agents may run the reveal outside game processes -- the
  code IS the lottery ticket.
- **The payout (one day, whole shard):** +20% damage (CombatMath
  calculate_hit / calculate_magic_hit stamp a blessing_multiplier
  into the hit_result; calculate_damage applies it), +20% healing
  (Skill.calculate_healing), +20% XP (KillRewards._grant_xp), and
  effective level +5 for stat computation
  (CharacterData.get_stat_total). Announced at code-assembly (plan
  tomorrow's login) and again at dawn when it goes live.
- **Almanac:** shows today's blessed class + live state, and
  tomorrow's preview ("if the tribe turns the key").
- **Voice:** the sky does not "bless" in a religious sense -- UI copy
  says "the wheel names X" / "carries the sky's blessing," matching
  section 4's observational vocabulary.
- **Test:** test_daily_class_blessing.gd (hydration x2 rotations,
  determinism, earn gate, all three consumer hooks); probe_ancient_loop
  extends to the blessing going live after the tribal solve.

## 9. Next slices (not built)

- **Server-wide broadcast polish:** region chat lines when a window
  reveals, and the door-open moment as a world event (sound, light
  pillar) so the shard FEELS the payoff.
- **Blessing visualization:** a subtle shard-wide tint or particle
  motif on blessed-class characters while their day lasts.
- **Chronicle presentation:** a dedicated lore panel (the almanac
  block is the readable minimum), and act-gated world content --
  doors, vaults, skill academy tiers per section 5, so each chapter
  attaches to something players DO.
- **Daily quest reset + insight objective** (see section 10).

## 10. Acts & chapters shipped (batch 11), and the daily-quest gap

**The Concord Chronicle is live.** ActsService (autoload after
SignService) consumes AncientDoor.door_opened: every door open
records the next eligible chapter of every act. Two gates, both
tribal: a chapter with a concrete `gate_day` records only when that
day's Ancient is unlocked (the tribe must have earned it); a fill-in
chapter (`gate_day = -1`) advances one per door open inside the
act's `advance_from_day` range. The door re-seals at every dawn, so
the Chronicle fills one step per solved day, forever. Data:
`data/acts/act_*.tres` (act_ prefix, filename == id; the naming lint
enforces it). The almanac shows the Chronicle block -- act summaries
plus recorded lines; unrecorded chapters read "[not yet recorded]"
and never leak the lesson. Voice: act copy is historical record,
checked against section 4's banned-words list by test.

**The look-up slice is player-facing:** the Concord Stone (E) and
the almanac's Watch-the-sky button both record insights -- the stone
for players who walk there, the button for players too far from one.
Same truth, same one-gaze-per-window price.

**The daily-quest gap (deliberately NOT forced).** The sky solve
could surface as a daily quest, and it would fit the retention
loop -- but today's QuestService cannot express it: no objective
type means "record an insight" (TALK/EXPLORE/KILL/COLLECT only),
and `check_quest_availability` permanently blocks REWARDED quests --
there is no daily reset, so a REWARDED daily could never be
re-accepted. QuestData already carries `DAILY`, `is_repeatable`, and
`cooldown` fields; when a daily-reset + insight-objective slice
lands, `quest_watch_the_sky` is the natural first data file. Design
note: the Chronicle is a SHARD milestone (the door opened for
everyone), while a daily quest is per-player progress -- keep those
separate in the UI copy.
