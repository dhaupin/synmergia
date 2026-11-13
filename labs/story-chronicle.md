# The Concord Chronicle — almanac entries, the monolith, and the village origin

> **Scope:** `labs/` only. `game/` is read-only context. This is the lore the
> Chronicle surface *would* carry; where it quotes data it quotes the shipped
> `.tres` verbatim.
> **Voice:** `labs/story-voice-concord.md` — observational, dutiful, slightly
> suspicious of certainty, practical. The Concord keeps score of the sky, not
> worship of it.

---

## What the Chronicle is (and what it is not)

The Chronicle is the Concord's running record: acts, chapters, and the day-gated
entries that unlock as the player's world-clock advances. In data it is
`game/data/acts/act_*.tres` — three acts, three chapters each, each chapter a
`record_text` with a `source_name` (the ledger it was filed under) and a
`gate_day`.

It is **not** a prophecy and **not** a quest log. It is an *almanac*: entries
filed after the fact, the way a survey office files them. The game already ships
the text; this document frames how a reader (an NPC archivist, a loading tip, a
library plaque) should talk about it.

**Restraint rule (from `prd-story.md` sec. 9):** the five mysteries stay open.
Nothing here answers *what caused the Silence*, *who made the Convergence*,
*what the Nexus Core is*, *why one magenta eye*, or *what the Bloom remembers*.
The Chronicle records what was *done*, never what it *meant*.

---

## The three acts

The acts are not chapters of a plot; they are three different *readings* of the
same dead civilization, filed in order of how much trust the reader is asked to
extend.

| act | id | the reading | the verb it teaches |
|---|---|---|---|
| **Act I — The First Vault** | `act_1_the_first_vault` | a city that planned 400 years ahead and died anyway; what remains is a curriculum | *keep what we kept* |
| **Act II — The Unpaid Debt** | `act_2_the_unpaid_debt` | obligations without owners, kept anyway | *mend, don't replace* |
| **Act III — The Trust Audit** | `act_3_the_trust_audit` | a society that ran on attention instead of commandments | *file the clean sheet too* |

The act `description` strings say this plainly:

- Act I: *"The oldest record in the Chronicle. A city that planned four hundred
  years ahead and died anyway — what remains is not ruins, it is a curriculum."*
- Act II: *"The dead built what you live in. This act reads the maintenance logs
  they left behind — obligations without owners, kept anyway."*
- Act III: *"Vault records from a society that ran on trust audits instead of
  commandments. No enforcement — only attention, and the shared expectation of
  it."*

---

### Act I — The First Vault (`act_1_the_first_vault`)

Three chapters, gated to days 1, 2, 3. The Concord's founding text.

**Ch. 1 — "The First Vault" (day 1).**
> The first vault's doors were rated in generations, not seasons. The builders
> wrote their work orders for heirs they would never meet: 'to those who keep
> what we kept.' Every mechanism still turns. Nobody is left who remembers why.

**Ch. 2 — "The Concord of Vault-Watchers" (day 2).**
> The vault stores no treasure. Its deepest chamber holds a planning ledger and
> one line, struck through: 'the city will outlast the need for cities.' The
> Concord reads this as a caution: planning is not the same as knowing.

**Ch. 3 — "The Concord of Vault-Keepers" (day 3).**
> The vault kept a room where citizens filed objections to their own plans —
> and the plans waited for them. The Concord keeps the room open. Attention, not
> certainty, is what made it work.

**Reading.** The First Vault is the Concord's origin story told as a *correction*:
the builders trusted the plan; the Concord trusts the *objection to the plan*.
The vault's own name is where `mystery_the_first_vault` points — its riddle
("speak the four words in the order the sky said them") is answered from Act I's
own day, which is why the almanac and the act share a gate.

---

### Act II — The Unpaid Debt (`act_2_the_unpaid_debt`)

Three chapters. `advance_from_day = 3`, so it opens the day after Act I closes.

**Ch. 1 — "The Conduit Wardens".**
> A conduit line has been re-wound every eleven years since before the Bloom.
> The log holds 214 signatures and one instruction, addressed to nobody:
> 'rewind it again.' Nobody was paid. Everybody was obliged.

**Ch. 2 — "The Concord of Wardens" (day 3).**
> The wardens refused replacement parts when the originals could be mended.
> Their reason, on file: 'a spare teaches you nothing; a mend teaches you the
> whole.' The Skill Academy still teaches from their mends.

**Ch. 3 — "The Last Warden Roster".**
> The final maintenance log has no repair entry at all — only a roster of names
> and, beside each, the name of another. Every name appears twice: once as
> keeper, once as kept. The roster was the repair.

**Reading.** This is the maintenance culture as scripture. The chapter that
matters is the last: the "repair" is a *mutual* roster — you keep and are kept.
It is the plainest statement of the Concord's actual ethic, and it is the reason
`mystery_the_watcher_tally` ("count the signs the shard has catalogued") sits
under Act II: the tally is the roster, applied to the sky.

---

### Act III — The Trust Audit (`act_3_the_trust_audit`)

Three chapters, all gated open (`gate_day = -1`). Deliberately *unwritten beyond
its door* — this act is the reader's, not the author's.

**Ch. 1 — "The Vault Auditors".**
> The audit chamber has no lock. Its door reads: 'you were trusted to arrive.'
> Records show 400 years of arrivals, and the ledgers reconcile to the coin. The
> Concord never duplicated the design; it duplicated the expectation.

**Ch. 2 — "The Granary Ledger".**
> A wheat shortage was answered by an unlocked granary and a sign-up sheet, not
> guards. The sheet came back overfilled. The auditors' note on the surplus:
> 'the community kept the audit for us.'

**Ch. 3 — "The Final Tally".**
> The last audit found nothing to correct and the auditors filed it anyway — a
> clean sheet is a record too. The Concord's custom of the daily tally descends
> from that filing: attention is the audit, not the finding.

**Reading.** Act III is the tone's thesis: *attention is the audit, not the
finding.* It is also where the game's own name lives — "Synmergia" is the shard
the audit was kept for. Do **not** let a later writer turn this act into a
reveal. Its whole point is that a clean sheet is filed without a finding.

---

## The capitol monolith — a record that is wrong on purpose

`game/entities/capitol_monolith.gd` stands the monolith on the far coast: a
plinth, a 12.6 m seamed shaft, **three bronze band rows** (`for row in range(3)`),
a stone capstone, two flanking pennant poles the cart-road arcs between, and a
bench ring of four plaza stools facing it. The plaza and the road already exist
in the path law; the monolith is what the road points at.

Three bands, three readings. The lore should say exactly that and no more:

| band | what is carved | what it is |
|---|---|---|
| lower | a survey line: the coast, the range, the road's bearing | **fact** — verifiable against the terrain law |
| middle | the founding date of the Concord and the first tally | **fact** — a filing, not a claim |
| upper | *"the vault will answer the sky, and the sky will remember us"* | **a vow, engraved in the past tense** |

**The point of the monolith is the third band.** It is a promise written as
though it had already happened. The Concord's honesty law (never claim what you
can't verify) is *violated in stone, on purpose* — the monolith is the one place
the culture let itself write the future in the past tense. A reader should be
able to stand at it and feel the tension: two bands of bookkeeping, one band of
faith, all three wearing the same bronze.

That tension is the whole prop. It does not resolve. The monolith does not
"come true." It stands there being wrong in the way a hope is wrong.

**Do not** add a fourth band, a hidden inscription, or a prophecy. Three is the
number the builder writes, and three is the number the lore keeps.

---

## The village origin — the short

The village is Haven: *"a village built inside the colossal fallen machine limb,
its metal overgrown with moss and windowed with new wooden shutters"*
(`zone_village_center.tres`). The monolith's third band is the capitol's vow;
this is the village's plainer one.

> The limb came down long before anyone's grandmother. Nobody hauled it, nobody
> raised it — it was simply *there*, and it was the wrong shape for a tree and
> the right shape for a wall. So they built inside it, because the wall was
> already standing and the roof was already over them, and a village that
> shelters in the dead is a village that admits it did not build the world.
>
> The elder will tell you the Gloamwood lies north and the ridge lies east. What
> the elder will not tell you — because nobody knows — is what the limb *was*.
> They keep the fire lit under it anyway. That is the whole ethic, in one house:
> you keep what you did not build, and you do not pretend to know why it stands.

**Note on the elder's copy.** `village_elder_greeting.tres` places the Gloamwood
"to the north, and the mountain ridge to the east" — the ridge is the
home-anchored ring range (`terrain_gen.gd`), and the woods are the Bloom lane's
`zone_forest_meadow`. The elder's two directions are, in fact, the two halves of
the Act I→II transition: the ridge is what you climb to leave; the woods are what
you descend into.

---

## The sky signs, redeemed (the honest addendum)

An earlier note worried that the Chronicle's "sky-code" language collided with
the vault puzzle. It does not, once the count is right. There are **three signs**
(`game/data/signs/`) but **four windows per day** (`sign_service.gd`,
`WINDOWS_PER_DAY = 4`), so a day's code is **four glyphs** in window order — which
is exactly why `mystery_the_first_vault` says *"speak the four words in the order
the sky said them."* The Chronicle may describe the practice ("the Concord keeps
score of the sky") without ever asserting the code's content; the content is the
player's to derive.

The same restraint covers the tally: `mystery_the_watcher_tally` asks how many
signs the shard has catalogued. The Chronicle must **not** print the number. It
can say a tally is kept; the count is the mystery.

---

## Creative restraint (inherited from the voice bible)

- The Chronicle records what was *done*; it never narrates what it *meant*.
- No act, chapter, or plaque canonizes an answer to the five mysteries.
- The monolith is allowed to be wrong (the third band); nothing else is.
- The Bloom, when it appears, is a maintenance failure — tragic, unattended,
  never evil.
- The player is not the chosen one. The player is the one who *looked up and
  wrote it down*, and the world noticed. The Chronicle is that noticing, filed.
