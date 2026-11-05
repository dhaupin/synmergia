# PRD — Monetization & The Server-Cost Ladder

> **Added 2026-11-05 (the funding pitstop round).** Purpose: a complete, honest model of
> what monetization *exists* in Synmergia today, what it *costs to run the world at scale*,
> and what the gap requires — so the project can fund its own servers and answer the
> "investors approach" question with a finished model instead of a whiteboard sketch.
> Companion notes: `TASKS.md` (what shipped, with dates). Server prices verified against
> 2026 publisher pages (sources at the bottom); treat the ranges as budgeting anchors,
> not quotes.

---

## 1. Why this document

- Synmergia is OSS-bound by intent, but servers, bandwidth, backups and payment
  processing are never free. The channel must exist either way.
- The monetization code that exists today was built **rails-first**: a wallet, an audited
  sink catalog, a payment provider seam. That means new SKUs are *data*, not code — which
  is also what an investor/model reviewer wants to see.
- Every future design decision (seasonal packs, cosmetics, events) should be able to point
  at a row in this document and ask: *does it pay for its own server time?*

## 2. The currency & the real-$ channel (SHIPPED)

**Concord Sigils** (`currency_concord_sigil`) — premium token riding the one-purse law
(InventoryComponent; a failed grant refunds; the books never hold a sigil without the
prize leaving the door).

Real-$ entry is the **webhook payment provider** (`webhook_payment_provider.gd`) — the
provider seams are swappable per the plugin law. Current processor SKUs:

| SKU | Contents | Price | Effective rate |
|---|---|---|---|
| `sigil_100` | 100 Concord Sigils | $4.99 | ~20.0 sig/$ — the floor |
| `sigil_280` | 280 Concord Sigils | $12.99 | ~21.6 sig/$ |
| `sigil_600` | 600 + 50 bonus | $24.99 | ~26.0 sig/$ — best bulk |

"1 ticket = 25 sigils" deliberately prices against the floor pack: **~$1.25 gross per
resurrection, roughly ~$1.00 net** after processor take (~3.5–5% + fixed fee), as measured
against the $4.99 pack. That is the reference unit for per-use premium convenience.

## 3. The sink catalog (SHIPPED — everything sigils can buy today)

All rows audited by `test_sigil_sink_catalog` (9 rows + refund legs) and priced on the
$4.99-floor / $24.99-bulk ladder:

| Kind | Row | Sigils | ~$ | Notes |
|---|---|---|---|---|
| RESPAWN | `respawn_soulbind_ticket` (x1) | 25 | $1.25 | per-use resurrection |
| RESPAWN | `respawn_soulbind_eight` (x8) | 150 | $7.50 | bulk pack (x1 test: $6.55) |
| MOUNT | `mount_meadow_pacer` | 150 | $7.50 | honest entry ride — mount ladder floor |
| MOUNT | `mount_plains_runner` | 250 | $12.50 | |
| MOUNT | `mount_reef_glider` | 400 | $20.00 | |
| MOUNT | `mount_trench_wyrm` | 650 | $32.50 | |
| MOUNT | `mount_storm_lancer` | 900 | $45.00 | catalog ceiling |
| TITLE | `title_pillarsworn` | 200 | $10.00 | cosmetic |
| TITLE | `title_deepseabaron` | 500 | $25.00 | cosmetic |

Also sigil-priced **in-game** (spend rails, not real-$ rails):
- **Black-market rolls** (`black_market_service.gd`): tiered pulls (3 / 12 sigils) over real
  loot tables — the "soul gem / deep steel" vein. Diaper-refund law holds on failed grants.
- **In-world earn path**: the Trench Sentinel's tide-dream table drops sigils (~10%),
  so premium currency is *both* purchasable and *earnable* — intentional softening.

**Design laws already enforced (carry forward as policy):**
1. No fake sinks — every sink row ships with a working grant leg.
2. Refund-on-refused-grant for every kind (including the full-bag + vault-wallet legs).
3. Convenience & cosmetics only — never combat-stat-by-purchase. (Resurrection tickets are
   *time/where* convenience; they buy no armor, no damage. PvP loot-handling interaction is
   flagged as a risk in §7.)

## 4. Content economics that already pay the curve (SHIPPED)

These are money-*shaped* content rails (they create the demand-side pressure that makes
the above catalog valuable), all landed in prior rounds:

- **Income round**: the Tide's-Tithe demand chain (Fenwick salvage → Sentinel's Toll →
  Gloamwood Ledger), a deep daily, and the `loot_sunken_salvage` signature economy.
- **Seasonal-pack cadence**: periodic cap lifts + band packs authored by the 3%-at-parity
  law — the future *season-pass-shaped* publishing rhythm already has its content law.
- **Jewelry/pearl industry, ore ladder, item-use door**: crafting-grade sinks that keep
  earned gold meaningful (gold must stay valuable for the $-sigil contrast to work).
- **Enemy ladder** (this round's neighbor): a populated world with honest kill costs —
  the ticket's value case is exhaustion, and exhaustion now exists at every band 5–60.

## 5. Goals (what the funnel must do)

Model targets for the "complete model" — honest F2P-MMO norms, to be re-calibrated by real
data the first live season:

| Stage | Target | Basis |
|---|---|---|
| D1 retention (new chars) | 35–45% | genre median |
| D30 retention | 12–18% | mid-tier MMO |
| Payer conversion (MAU → payer) | 4–8% | F2P genre norm |
| ARPPU | $5–9/mo | ticket/anchor pricing |
| Whale ARPPU (top 2%) | $40–120/mo | mount ceiling + bulk packs headroom |
| Implied ARPU | ~$0.30–0.70/mo of MAU | conversion × ARPPU mix |

Break-even headline (computed against §6's scale tier): **≈ 2,000–3,000 paying-active
players per month covers the entire at-scale infrastructure budget with margin.** Actual
player-date economics are below in §7.

## 6. The server-cost ladder (what it costs to run Synmergia)

Architecture reminder (what we are paying for): N headless Godot shard processes
(enet-websocket edge, nginx L7 sticky), a shared state plane (Postgres + Redis via
bridges), a coordinator for the cross-shard mesh, and content/patch distribution for the
~7 MB web client — all currently proven in docker compose on a single box.

*Assumptions needing a benchmark before commitments: per-shard player cap (env-configured;
budgeted at 100 CCU/shard), per-shard RAM/CPU (terrain derive is CPU-hungry — the 2-core
VM saturation we hit locally is a warning, measured headless-shard numbers come with the
first real fleet). Counts below err high.*

### Tier 0 — Pilot / closed beta (≈ 50–150 peak CCU)

| Item | Choice | €/mo |
|---|---|---|
| 2–4 game shards | 1× CX43 (8 vCPU/16 GB) or 2× CX33 | €16–24 |
| Postgres + Redis + nginx + coordinator | 1× CX23 | €5.5 |
| Backups/snapshots, IPv4s | | ~€3 |
| **Total** | | **≈ €25–35** |

Covered by: essentially any paying activity at all — or one bulk pack sale every ~3 weeks.

### Tier 1 — Early launch (≈ 500–2,000 peak CCU)

| Item | Choice | €/mo |
|---|---|---|
| ~10–20 shards | 6× CX53 (16 vCPU/32 GB each) or 1× dedicated AX-class box + 1 CX53 | €175–210 |
| Postgres (managed, small, daily backups) | Supabase Small / Neuro–LOD Managed PG 2 GB class | €15–30 |
| Redis + coordinator + L7 proxy | rides shard boxes or 1× CX23 | €6–16 |
| Observability/backups/parity env | | €15–25 |
| **Total** | | **≈ €210–290** (~$250–320) |

Covered by: ~120–200 monthly payers at target ARPPU. This is the tier where the model stops
depending on anyone's pocket.

### Tier 2 — At scale (≈ 10,000 peak CCU, region-split)

| Item | Choice | €/mo |
|---|---|---|
| ~100–200 shards | 10–12 dedicated dedicated-AX-class boxes (unlimited traffic) — or auction fleet ≈ €700 if price-hunting | €1,600–1,900 (auction ≈ €700–900) |
| Postgres HA (region-failover) | self-hosted 2× CCX33 + replica, or Neon Scale | €270–740 |
| Redis cluster + coordinator + anycast L7 | | €150–300 |
| CDN (client patches, web shell) | | €50–150 |
| Observability, alerting, staging parity | | €200–400 |
| **Total** | | **≈ €2,300–3,500** (~$2.8–4.2k; auction route €1,600–1,900) |

Per-unit truth at Tier 2: ≈ **$0.28–0.42 per peak-CCU-month**, ≈ **$0.03–0.05 per DAU-month**
(a peak-CCU ≈ 6–10× DAU).

### Provider anchors (2026, sources in footer)

- Hetzner cloud: CX43 8 vCPU/16 GB €15.99, CX53 €29.49, CCX13 (dedicated vCPU) €42.99;
  20 TB transfer included EU, overage €1/TB — bandwidth is a rounding error at these tiers.
- Hetzner dedicated: new AX41 €59 (64 GB, 1 Gbit, unlimited traffic); auction-equivalent
  hardware typically €30–45/mo used.
- Managed Postgres: Supabase Pro $25 (incl. Small compute $15 add-on), DO MG $15–30,
  Neon ~$15–70 typical small; Hetzner self-host = own backups/failover.
- Comparables if we outgrow self-managed: DO CPU-Optimized (gaming-marketed) $42/4 GiB-2vCPU;
  AWS GameLift Anywhere $0.0012/session + $0.000011/connection-min with free gen-6 egress —
  the "managed elasticity" future, ~10× the raw cost.

### Honest cost gaps this document does NOT fund

Salaries/contracts, art (icon placeholders stand today), moderation, payment-provider
compliance overhead (the real take-rate is ~3.5–5.5% incl. VAT handling), and the
scaling cliff if per-shard CCU lands near 30 with derive-heavy zones (Tier-2 shard count
roughly triples). The first two gaps are the reason this document exists.

## 7. Risks & open questions

1. **PvP × Soulbind tickets**: ticket resurrection is pure convenience in PvE; in PvP it
   can become a meta purchase (instant stand-up in contested bodies, live loot-bag
   pressure). Options already supported by code: res-veto by authority, separate PvP
   pricing, or context-priced sinks (the sink rows support conditions/legs). Decide when
   the open-world PvP rules round lands. *This is the single largest design risk in the
   current catalog.*
2. **Shard throughput is unmeasured**: every count above assumes 100 CCU/shard; the real
   number is whatever headless Godot + terrain derive + player tick allows. Benchmark on
   the first dedicated box before Tier-1 spend.
3. **Sigil earn-rate drift**: the in-world earn path (boss drops) must stay scarce enough
   that paying is meaningful but not so scarce that F2P feels bricked. The future
   seasonal economy review should lock a target (e.g. earned sigil income ≤ 25% of expected
   sink demand).
4. **Provider seam is unduplicated**: today's webhook provider is the seam; Stripe/Paddle
   adapters are *planned, not built* — the real-$ leg of the model is still release-gated.
5. **Pricing sensitivity of the $1.00 ticket**: anchor validated vs processor net
   (~$1.00 net at floor-pack rates). Sweet spot math was done by one human + one AI; needs
   play-data once the channel opens (price A/B on the death screen row is a trivial
   data-driven change thanks to the sink-row shape).

## 8. Futures (the roadmap, in priority order)

1. **Real-$ provider adapters** (Stripe or Paddle for EU VAT handling) — the only missing
   leg of the audited loop; everything downstream is data.
2. **Season pass (seasonal-pack cadence)**: the publishing rhythm exists; a track of
   cosmetics + the seasonal core pack at ~$8–10/season is the single highest-leverage
   future SKU and it resells the ladder rounds we already build. **Designed in §9** —
   contents, hard laws, and the earned-sigils-only F2P door are specified.
3. **Cosmetic breadth** (dyes, tabards, pet/mount skins): sink rows are data; the model
   ceiling rises without touching laws.
4. **Storage/convenience tiers**: extra bank tabs, extra vendor stall rows — classic
   retention monetization, rides existing inventory laws.
5. **Character-slot packs**: natural at the multi-spec future; pure permit rows.
6. **Open question for discussion**: subscription ("the Concord Ledger Charter"?) —
   monthly all-you-need sigils + small daily conveniences; strongest for recurring revenue,
   weakest vs the "no subs for content already earned" sentiment; bring numbers, not vibes.

## 9. The Season Charter — the pass, with its F2P door

> **Added 2026-11-05 (the pass design round)**, answering two questions: what does the
> pass include, and can F2P earn it? The seasonal-pack cadence already exists as content
> law (cap lifts + band packs, 3%-at-parity income); the Charter is its front door.

**What it is.** One purchase per season — never a subscription. A season-long
**two-track book of seasonal deeds** (quest-chain clears, boss kills, dive/salvage hauls,
event seeds) fed by the packs' own content. The deed meter is time-synced to the season,
not to spend.

**Premium track (what money buys; cosmetics & convenience only):**
- The season's cosmetic suite: exclusive title, dye kit, pet, and the seasonal mount
  **skin** — a skin applies only to a ride already owned; no ride advantage is minted.
- Season convenience, non-combat: an extra bank tab for the season, and **early entry**
  (the pack's zones open a few days early — time, not power).
- A pursuing deed faucet so the premium track climbs on season deeds as well (a Charter
  holder still plays the season to unlock it — the pass is a key, not a dump).

**Hard laws — what the Charter never gives:** no combat stats; no XP or cap-pace boosts
(the don't-level-too-fast law); no debuff on anyone else; no content the free game will
not eventually get. Premium is *earlier + prettier*, never *only*.

**The F2P door (the pass itself is earnable):**
1. **The free track** rides every Charter for everyone: a dye kit, a season trophy
   cosmetic, the convenience tab — deeds only, no money, including for non-buyers.
2. **The Charter itself is purchasable with earned sigils**: the unlock is priced both
   ways — $8.99 **or** 300 **earned-only** sigils, any time during the season, payable
   ONLY from the deed (earned) pool. Bought sigils cannot buy the pass. A grinder earns
   their premium track through play; a buyer walks in day one. Either way the premium
   track is cosmetic-only, so neither route is P2W — it is identity, not power.
- Honest sizing note (a build round, not a wish): the earned faucet today is
  boss-table drops only. Making 300 deed-sigils reachable in 2–4 weeks of active play
  means the pass design round adds the deed-ledger grants to dailies/chains/hauls; that
  is data on existing rails.

## 10. The Mythos Toll — paid exclusives carry an honest tradeoff

**The idea in one line.** Top-rung exclusives ("Mythos" grade) can be bought outright —
but every Mythos item ships with its **Toll**: authored, item-card-visible negative
modifiers drawn from the **coverable-hook set** (movement speed, all-resist, regen,
cooldown/haste — NEVER damage, health, or defense). Example: a Mythos halberd at
-10% all-resist / -10% move speed. The toll makes the item demand a skilled party or a
build built to cover its hooks — ownership is participation, not a win button.

**The provenance law — earned sigils are worth more in modifier rate, not exchange rate.**
The wallet ledger stamps provenance at grant time:
- **Coin sigils** — credited by the processor webhook (bought).
- **Deed sigils** — credited by in-world rails (boss tables, quest chains, salvage and
  dive income, event seeds). Same displayed balance, same 25-per-ticket spend value, one
  purse, one UI. The two sigils differ only in what they are *credited by*.
- A Mythos sink purchase **debits deed sigils first**, and the toll grades by the earned
  fraction of that debit:

| Grade | Deed fraction of the debit | Toll |
|---|---|---|
| **Proven** | 100% | none — the clean mythic exclusive |
| **Tempered** | ≥ 75% | halved (e.g. -5%/-5%) |
| **Bought** | < 75% | full, as authored (e.g. -10%/-10%) |

The grade stamps on the grant and reads forever on the item card; a trade or a dye never
launders it. Consequence, stated plainly: the F2P grinder's Mythos exclusive is
**strictly better** than the buyer's — same look, same stat column, minus the toll. The
buyer's advantage is the clock ("I have it now"), never the ceiling. Buyers who also
play can temper their way to Proven with deeds — money buys the fast lane, not a
separate road.

**The anti-smell laws (the investor-facing tenets):**
1. Every Mythos exclusive has a fully non-money path to a **better** version; money buys
   now-sooner, never better-or-only.
2. The toll taxes only its owner — no enemy-facing aura debuffs, no social engineering.
3. Toll hooks are coverable by play (movement, resists, regen, haste): the design leans
   on team and build craft — skilled-party reliance, not wallet reliance.
4. The Charter (§9) and Mythos exclusives are different products; cosmetics carry no
   toll because they carry no stats.
5. XP pace and level caps can never be bought (the seasonal cap law stays free-for-all).

**Implementation seat (a later design round; receipts must gain legs for it):**
provenance is a wallet-ledger law (the honest first shape: an earned sub-ledger — two
currency ids under a unified purse, debits striking the earned id first); Mythos rows
are sink rows with authored toll fields; grades stamp at grant; the sink-catalog receipt
gains the provenance-fraction → grade → toll legs. Open questions flagged honestly: if
player-to-player trading ever opens, deed sigils must **bind-on-earn** (provenance must
never become rentable via RMT); the 75/100 tier thresholds are a tuning dial, not a
law; whether cosmetics ever ride the same provenance grade (a burned-in
"deeds-imprinted" finish at Proven) is an open aesthetic call, not a decided one.

## 11. The dye economy — the first agreed spitball (2026-11-05)

> **Status: AGREED.** Pure-visual by construction — zero stat hooks — so it is the
> safest premium category the catalog can carry, and it bolts premium money onto systems
> that already exist (craft, mounts, accessories, housing) instead of inventing new ones.

**The carrier law:** one dye slot, many carriers. Every dyeable carrier — weapons,
armors, wearables, accessories, mount tack, gliders, housing furniture — takes the same
dye treatment. A dye applies a **look**, never a number.

**The two-lane color law (free lane first):**
- **Field dyes (craftable, free).** Crafted at the bench from harvests — moonpetal reds,
  kelp greens, pan-salt whites, ironblacks, the faint pearl shimmer. Honest coverage of
  the mundane palette; dyes become a real trade good on vendor shelves (the resource
  category already exists). A crafter can run a dye *industry*.
- **Concord dyes (sigils, premium breadth + motion).** The wild palette: iridescence,
  animated gradients, seasonal glitters, and camo/fielding patterns for weapons, armors
  and wearables. Premium buys spectacle and selection — never exclusivity of a look the
  field lane can reach.

**The colorist's license (the custom-chooser SKU).** The full-spectrum custom color
chooser (choose-your-own hue/saturation, pattern seat) for weps/armors/wearables is
priced as a **reusable permit**, not per-item nickels-and-dimes — the permit shape is
already proven by the Soulbinder's ticket and the stackable sink rows. Seasonal pattern
packs restock like vendor shelves do.

**Laws (§10's anti-smell tenets, restated for color):**
1. A dye is a look, never a stat — ever. No "dyed for +hit", no tuned-failure nonsense.
2. Field dyes reach every carrier type premium dyes can. Color *choice* may be limited;
   access never is.
3. **Preview never debits.** Try-on shows the dyed look on *your* item before purchase;
   a failed application refunds per the sink refund law.
4. Dyes ride the Charter but never require it: §9's free track ships a field-dye kit;
   the premium suite ships a seasonal wild dye; the dye economy stands on its own.
5. Provenance and the Toll (§10) are orthogonal — dyes do not grade, and grades do not
   gate color.

**Implementation seat (a build round):** a dye slot on the appearance record (mounts and
furniture need carriers beyond the item schema); dye .tres items in the consumable
family with their own stack behavior + the license permit; the item-catalog receipt
gains dye-legs (every dye resolves a look id, the preview-is-free leg, the refund leg);
icon minting rides the palette law. **Open question for that round:** is the dyed look
stamped on the item or kept as a wardrobe overlay layer? The overlay is the stronger
product (crafted gear keeps its authored look under paint) but touches persistence —
decide with data.

### The spitball bench

| Idea | Status | Home |
|---|---|---|
| Dyes — two-lane color economy + the colorist's license | AGREED, designed | §11 |
| *(next spitballs land here, one row per agreed idea)* | — | — |
| Wardrobe locker — carry owned looks across owned items | AGREED, designed | §12 |
| Guild heraldry packs — crew-bought social cosmetics | AGREED, designed | §13 |
| Lucky — the weekly luck pot (7 days: 2 earned, 5 bought) | AGREED, designed | §14 |
| The Whisper Ledger — the rumor mill + the Peal | AGREED, designed | §15 |
| Expedition pack — the four-tier storage ladder (deeds earn, coin buys the clock) | AGREED, designed | §16 |
| The title ropes — prefix/suffix walked back through §§11–16 | AGREED, designed | §17 |

## 12. The wardrobe locker — spitball #2 (2026-11-05)

> **Status: AGREED.** The transmog seat: one unlock lets a player carry any cosmetic
> look they OWN across any item they OWN. It multiplies the value of every cosmetic
> already sold (dyes, Charter suites, Mythos looks) without needing to sell anything new
> — pure convenience over the collection, which is the cleanest way for premium to grow.

**What the unlock does (per account, once):** looks live on the account, not stamped
into items. Own a look once (its unlock is a receipt-style registry row), apply it to
any carrier you own at the locker (§11's carrier law applies here too: one locker for
weps/armors/wearables/accessories/mount tack/gliders/furniture), and re-skin as often
as you like — the underlying item keeps all its own truth.

**It rides the cross-account transaction roots (the owner's rail).** Provenance already
exists stamped at the purse layer (§10: coin-sigil vs deed-sigil). The locker's
ownership and history checks run on the SAME roots: a look's unlock persists as
ledger lines inside the same account-scoped transaction family — not as item copies
surviving inventory moves. A deed-earned look stays graded exactly as §10 grades
earned-vs-bought; nothing converts into something stronger by passing through the
locker.

**Laws (a look is never a stat; the free lane stays real):**
1. A transmog look is cosmetic ONLY — the carrier keeps its own card's numbers. No
   look may smuggle a stat onto a free item, or the expensive tier's card onto a
   cheap one.
2. **The free lane:** field-crafted looks (the dye lane's mundane palette, plus
   craft-authored looks) are always locker-eligible and store free in a small set of
   slots; the paid unlock grows the slot count (unlimited), never the look access.
3. Charter cosmetics save looks too, free-tracked: owning the Charter must never be
   required to use the locker on a look the player already owns.
4. **Preview never debits** — §11's law, restated for the locker.
5. Provenance/toll stays orthogonal (§10): a graded item re-grades by its own purse
   truth; moving a look never touches the ledger.

**Implementation seat (a build round):** the look registry as an account-scoped ledger
(tx-root keyed, per the purse law), the locker UI over §11's wardrobe-overlay decision
(the overlay shape makes the locker nearly free — looks and dyes get ONE surface
patch), and the item-catalog receipt gains a locker leg (every look resolves a carrier
family, and the unlock leg follows the preview-free + refund laws).

## 13. Guild heraldry packs — spitball #3 (2026-11-05)

> **Status: AGREED.** Social cosmetics bought by the crew: banners on guild halls,
> barque-sail flags, house plaques, and heraldry trims. Ten dollars is nothing to a
> serious crew for a feature/flair/polish the whole party gets — the price scales by
> the group, not by one member's wallet (and groups churn less than solo players, so
> the payers the kit keeps are the durable ones).

**What ships:** kits of a guild's own marks (emblem + colors + motto) as looks applied
to the visible surface itself — the flag, not each frame's armor. Banners for the
guild hall, sail flags on the barque, house plaques for player housing, and matching
heraldry trims for member armor.

**The purchase shape (guild vault, not one wallet):** the kit is bought FROM the guild
vault, into which any member can deposit. The vault tracks its own earned-vs-bought
provenance mix per the §10 purse law, so an earned-crew guild buys kits wholly on deed
sigils, a bought-rich guild pays the Mythos toll per §10, and no member ever has to be
online to make the purchase unlock for everybody. The buyer permission is rank-gated
(leader/officer rank only) — never a random rank gamble.

**Laws:**
1. **Heraldry is a look, never a buff.** No buffs on flags, no damage bonuses for
   banner bearers. A flag's value is that everyone can see it.
2. **A guild owns its own emblems.** Hateful or misleading guild marks are real
   moderation work — the heraldry system ships with a report + takedown flow for
   hall flags, sails, and plaques from the first build round.
3. **The free lane:** every guild earns ONE standard-emblem banner for free at guild
   creation; the Concord kits widen the look range (animated sail seams, glossy
   plaques, legacy dread banners), never gating the guild badge itself.
4. The guild does not grade its kits (§10 stays orthogonal) and nothing requires the
   Charter — a whole pool can pay Charter-price in deed sigils if the crew wants to.

**Implementation seat (a build round):** a guild ledger table (or reuse the existing
persistence ledger service), the guild-vault deposit and kit-purchase as double-entry
tx legs with provenance stamps, the rank-gated buy permit, and the look surface riding
the same wardrobe-overlay recolor seat as §§11-12 so there is exactly ONE
cosmetic-on-surface patch designed once, reused thrice.

## 14. Lucky — the weekly luck pot (spitball #4, 2026-11-05)

> **Status: AGREED — the owner's shape plus two cuts.** A cheap burst of good
> fortune: each charm buys 24 hours of raised drop luck across the WHOLE economy —
> materials, craft inputs, weapons, armor, rare loot, the black-market roll — not just
> one gear chain. Affordable to grinders, and the earn law keeps what normal/moderate
> play can luck-earn to 2 of the 7 weekly pot days.

**The pot law (the reframe that keeps it honest).** Every account owns a weekly luck
pot — 7 luck-days per week, ALL at the same potency. Days 1-2 are earned nearly free
through deeds (the owner's earn rule: normal/moderate play lucks them in); days 3-7 are
bought at 25 sigils per 24-hour charm — the Soulbinder ticket's own price shape ($1.25
gross, ≈$1.00 net) and an existing sink row class. Money buys the CLOCK — skip the
deeds — never more luck than the same ceiling every account has access to. A charm
lasts 24 hours from activation; the pot resets on the world's weekly tick, not on a
purchase.

**The two cuts:**
1. **No XP leg.** Luck raises drop odds only — never XP gain, never gold-per-kill
   rates. §9's hard law (no XP purchase) does not bend for $1.25, and neither does the
   no-XP-pace tenet.
2. **The stat-only law needs its authored tradeoff, so Lucky carries a stamp.**
   Rare finds under a BOUGHT charm come out **fated** — bind-on-luck, soulbound, item
   card says so. Finds under a DEED-earned day trade free. Money cannot mint tradable
   wealth at scale, the economy stays purchase-proof, and deed luck is strictly better
   — the standing tenet that earned is worth more, applied to fortune itself.

### The spiritbind jackpot (the owner's addition to the pot)

Beyond the fated stamp on bought-luck finds: a GLOBAL modifier that has nothing to do
with the charm at all. **Every drop in the world — a wild stick, a market roll, an
earned mythic, a crafting station output — rolls the same tiny, authored chance to
land SPIRITBOUND**, the world's rarest binder. Luck of the draw whether the find is a
stick or a mythic: the froth is that the jackpot can land on anything, at any moment,
for anyone, and the item card is the only herald it gets.

**Laws (the jackpot is global, authored, and untouchable by money):**
1. The roll lives in the SAME central roll-time modifier as the Lucky charm — one
   global spiritbind leg, never a per-item bandaid. It applies to non-stackable gear
   only (weps/armors/wearables/accessories/instruments); stackable materials are
   vetoed, since a bound stack is junk-locked.
2. Spiritbound is permanent and honest — the item card says so, forever. It is not a
   punishment tier: it is the rarest provenance, its own prestige (a handful of items
   on the shard carry it).
3. **Money never touches the jackpot odds.** A bought charm lifts the charm's own
   drop rate only; the spiritbind leg rolls at its authored chance during bought AND
   deed luck AND no luck alike. Nobody can buy the rarest binder; that is exactly the
   froth.
4. Toll orthogonal (§10): a spiritbound landing needs no grading. Mythos items keep
   their toll grade; the jackpot lands ON TOP of whatever the purse already stamped.
5. The jackpot is free-path by construction: it rolls whether or not Lucky exists in
   the market. Lucky just widens the number of rolls a player makes — and so does
   plain grinding.

**Laws:**
1. Luck is ONE central roll-time modifier over the drop sources (loot tables, the
   black-market board, harvest bounty) — never a per-item bandaid. The black market's
   3/12 roll board gets the lift at modest odds only; flagged as the charm's loudest
   touchpoint.
2. **The pot is preshown.** The pot UI lists remaining earned/bought days BEFORE any
   purchase — the preview-never-debits law, in its cheapest dress.
3. The charm is a consumable with its own stack behavior; the day-purchase joins the
   sink catalog with the refund + receipt legs. No refund once a charm's 24 hours
   have started.
4. The weekly pot lives on the account ledger (the tx roots), each pot day stamped
   deed or bought — the provenance law reused.
5. Toll orthogonal (§10): Lucky never grades an item; the purse grades exactly as
   before. Lucky never requires the Charter; the free lane is the pot's own floor
   (2 deed days every week, forever).

**Implementation seat (a build round):** the weekly pot meter in the account ledger,
the charm .tres in the consumable family + the sink row (25-sigil day, economics
already in §2), the central drop-modifier resolution point (one function loot tables
and the market board both consult), the fated stamp on lucky-found premium rares, and
the pot UI. **Open question for that round:** does the charm lift HARVEST node yields
too, or only kill/roll drops? (Harvest-skip is the shape that starts to smell.)

## 15. The Whisper Ledger — the rumor mill and the Peal (spitball #5, 2026-11-05)

> **Status: AGREED.** The monetization of BEING SEEN — the one category the catalog
> did not yet sell. §14's spiritbind jackpot is world froth by law; this section gives
> the froth a mouth: a free rumor mill that tells the whole shard, and a small paid
> permit that lets a finder ring the bells over their own legend.

**Seat 1 — the rumor mill (free, worldbuilding first).** Every spiritbind landing
whispers through the village heralds' evening news: *"The Ledger reports a spade found
spiritbound near the pans — unnamed."* A notch too frequent to ignore, too rare to
feel like spam. The mill turns the jackpot into a world clock — players check the
herald the way they check weather — and every whisper advertises the whole luck
economy to the whole shard, free of charge. Everyone can read; nobody pays.

**Seat 2 — the Peal (the paid leg, the megaphone for your own legend).** When the
jackpot lands on YOUR find, the landing already rumors free (item + place, name
withheld). The Peal permit (deed-earned OR bought, the colorist license's own permit
shape, never Charter-gated) adds the celebration you get to ring: a zone-wide bell, a
sky-lantern burst, and the rumor line that carries your name instead of "unnamed".
The landing itself is never sold; only its echo is. Cosmetic only — by construction it
cannot touch a single number. A friend or the guild vault may buy a Peal FOR a finder
(the gift leg): celebrations are meant to be given, not only owned.

**Laws:**
1. **Nobody buys the landing.** Money never raises jackpot odds (§14's law already),
   and the rumor leg is free for every landing. The Peal only adds spectacle and the
   name token — an amplifier, never a vendor.
2. **No free text, ever.** Rumor lines are authored template sentences filled from the
   item card's own truth (item id, place, name-or-unnamed). Moderation here is just
   the withhold switch — no arbitrary strings, no heraldry-scale report flow needed.
3. **The location leg comes free:** the whisper names the place ("by the drowned
   pier") — a tourism engine zones would otherwise have to buy quests for.
4. Charter never gates: the permit is deed-earned or bought, its two lanes exactly
   equal in what they ring.
5. Toll orthogonal (§10), and the mill reads provenance WITHOUT grading — a whisper
   may honestly say a found mythic "wears its maker's toll" the same way the item
   card does, but the mill never sells anything about it.

**The carrier: the sky almanac (the owner's rail).** The Ledger's news is not new
furniture — it prints on the SKY ALMANAC (SkyAlmanacUI, the page the moon and sailing
reads already share), marching at the same almanac-day cadence the world's weather
calendar already keeps. The existing law is that the almanac is the world's memory —
so the Ledger writes INTO that memory instead of building a parallel book:

- **One derivation, two readers.** The whisper page derives from the same central
  drop/landing facts the town herald's voice reads — never a second copy. This is the
  honesty-law pattern the almanac already runs everywhere (ferry chart and dock
  cannot disagree; the bug could live in exactly one file). The chart in the page and
  the whisper in the village are one record.
- **Notable landings become chronicle.** A recorded landing files as an Acts-style
  chapter — index, source_name ("The Ledger"), record_text (the template line),
  gate_day (the landing's almanac day) — so the mill's news persists with the world's
  memory alongside the door records, and the page can print yesterday's rumors as
  history, not chat. The day a spade lands spiritbound is a day with a page number.
- **The fork resolves by the split itself.** A Peal rings LIVE, in the moment — bell
  in-zone, lantern burst, immediacy is the amplifier's own product. The free whisper
  prints at the almanac's dawn roll: the page is the delayed newspaper, editorial
  voice intact. Both seats get the timing that suits them, from the carrier's own
  clock — no schedule to invent.

**Implementation seat (a build round):** the Ledger as a subscriber to the central
drop event (the roll-time modifier point §14 already created); a whisper page in
SkyAlmanacUI beside the moon and sailing pages (registry rows + the page reader, no
new UI scaffolding); the chapter leg riding the existing Acts/chronicle record rails
(so the almanac schema already carries most of the shape); the Peal permit .tres +
its sink row + the zone-wide cosmetic event (bell + lantern particles); the gift leg
through the guild vault rail (§13). The herald line itself stays a thin voice-reader
of the same record, wherever the village chirp lives.

## 16. The expedition pack — the storage clock (spitball #6, 2026-11-05)

Four permanent tier unlocks — **Expedition I–IV** — that grow every container an
account actually works: the bag (`InventoryComponent.expand_inventory`, the `MAX_BAGS`
rails), the vault (`expand_bank`, the `MAX_BANK_EXPANSIONS` rails), and the guild
vault (the `GUILD_VAULT` container family; §13's vault rails). A tier is +12 slots on
its container (the container schema's own `SLOTS_PER_TIER` rail). The pack is a
permanent inventory/vault/guild-storage ADDITION, not a season item.

**The F2P leg:** each tier is deed-earnable in roughly a week of honest play — quest
milestones, ledger appearances, heraldry deeds — so the full ladder is about a month
for a free account, and *a week gets ya something*. Deed tiers grade Proven under
§10's provenance law: no tolls, full honor, and the tier's title (§17's ropes).

**The bought leg:** sigils skip the deed ladder — money buys the CLOCK, never new
capacity deeds can't reach. The authored tradeoff (the tenet required, never
stats-only-bonus): a bought tier is **chartered** — provenance-stamped in the account
ledger (§12's tx-roots family) and carrying the CHARTER'S TOLL: a small authored luck
damp (~5%) on the account's luck pool while any chartered tier is held, riding §14's
one central roll-time modifier. The grinders' edge is real and visible: identical
capacity, but the chartered hold never gets the genius of the deed-grader, and it
mints no title. The toll grades Proven/Tempered/Bought by the EXISTING purse law — an
account that mixes deeds and cash can be Tempered, exactly as §10 defines.

**Laws:**
- **Capacity is never a stat.** Slots store; nothing strengthens. No container
  upgrade changes damage, speed, or drop odds — the only purchased behavior is room.
- **Money buys the clock, never the ceiling.** The tier ladder's top stays
  deed-reachable for a free account; F2P can unlock all four tiers in about a month.
- **The toll is authored and visible.** The charter's luck damp is on the item card /
 Purchase flow the way Mythos tolls are; nobody buys a chartered tier by accident.
- **The guild vault leg rides §13.** Vault tiers are bought FROM the guild vault
  (rank-gated, no forced-online; deed-vs-bought mix tracked per the purse law).
- **Preview never debits** (the standing preview law); tier purchases are permanent — no refunds
  after the unlock receipt — and Charter never gates a tier's existence.
- **Toll orthogonal, never Charter-required.**

**Implementation seat (a build round):** four expedition SKU rows in the sink
catalog + the deed-earn hooks riding quest/achievement rails; container-tier unlock
receipts through the sink service; the charter's-toll hook into §14's roll-time
modifier; provenance lines via the account-ledger tx roots; zero service surgery —
the tiers are server ledger lines and authored DATA, the pack-export law of every
purchased entity this catalog has shipped.

## 17. The title ropes — prefix/suffix walked back through the walk (spitball #6b, 2026-11-05)

The commission: walk back through monetization and seat the PLAYER TITLES. The rail
predates the walk: `TitleData` (`core/schemas/title_data.gd` — both `prefix_form` and
`suffix_form` on the name plate; `Category`/`Rarity`/`UnlockMethod` including
`PURCHASE`) and `TitleService` (`core/services/title_service.gd` — unlocked books,
`equipped_prefix`/`equipped_suffix`, `title_color`, the `title_unlocked` signal). A
purchased title precedent already exists (`title_deepseabaron.tres`,
`unlock_method = PURCHASE`, source sigil_sink). Titles need policy, not a system.

**THE ROPE LAWS:**
- **A title is a look, never a number.** No stat rides any title, ever; the display
  IS the whole product. Rarity shades the plate (`title_color` = the schema's own
  Rarity rail) and rarity follows the deed's rarity, not the wallet.
- **Nobody buys an honor.** The PREFIX form is deed-minted ONLY. Sales mint SUFFIXES at most — the Deep
  Sea Baron's shape: purchasable, plainly-branded vanity, suffix-form first. The
  prefix/suffix split does the owning twice.
- **No free text ever.** Title strings are authored `.tres` (free text is
  never an unlock; the same template law the Ledger runs applies unchanged).
- **Toll orthogonal, never Charter-required.** Title purchases ride the sink
  catalog; nothing needs the Charter either to earn or to equip.

**THE WALK-BACK (where titles sit on what is already built):**
- **§11 dyes → "the Dyer."** suffix, deed: author a full dye-family palette in one
  season; the colorist license's customers already have the deeds.
- **§12 wardrobe → "Wardbearer."** suffix, deed: the first clean locker of owned
  looks across owned carriers.
- **§13 guild heraldry → "Herald of <Guild>."** the guild's public face, rank-gated (the
  guild's kit purchase already bills rank gates), the pack's herald rules carry it.
- **§14 Lucky → "the Fated" (prefix).** Land a rare find under a BOUGHT charm — the
  fated stamp already marks the item; the title marks the person. And the rope's
  crown: **"the Chosen" (prefix)** — a JACKPOT landing (§14's global leg). By
  construction nobody can buy it: money never touches jackpot odds. The rarest
  prefix in the game is unbuyable, which is exactly what makes the prefix law mean.
- **§15 Whisper Ledger → "Chronicler."** suffix, deed: the ledger's afternoon page
  says your name (the Peal'd finder or the found); the record becomes a name plate.
- **§16 expedition pack → "Expedition I–IV" (prefix form), deed tiers ONLY.** The
  chartered hold mints nothing — the honor difference is part of the charter's toll.

**Implementation seat (a build round):** authored title `.tres` files at the six
rope points + mint hooks riding each rail's existing event (the sink receipt, the
lucky-find stamp, the ledger chapter); one cheap sink row for purchasable suffix
vanity (the baron's shape); `TitleService` already carries unlock/equip/signal
through; zero new systems, one new proof-of-policy receipt.

## 18. The investor version (the one-paragraph answer)

*Synmergia's monetization is not a plan, it is an installed, receipt-audited system: a
wallet, three real-$ SKUs ($4.99–$24.99), a nine-row premium catalog (resurrection
tickets at $1.00 net per unit, a $7.50–$45 mount ladder, cosmetic titles at $10–25),
an in-game sigil market, a four-tier expedition storage ladder where deeds earn the slots and the wallet only buys the clock (a chartered buy carries a small authored luck-toll), and an earned-earn path that keeps F2P honest. Publishing
cadence is already contractual: seasonal packs authored by an income law that pays the
shared progression curve, with a level cap that lifts on data, not opinion. Pay-to-win is priced out by construction
rather than promised away: Mythos exclusives ship with an authored tradeoff toll that
grades by earned-vs-bought provenance — the buy-now version is strictly weaker than the
grind-earned version of the same item — and the season pass is cosmetics-and-convenience
with an earned-sigils-only purchase door, so the F2P trust floor is a **feature of the
model**, not damage control. The total
infrastructure cost of running the world at scale is benchmarked at roughly
$2,800–4,200/month at 10,000 concurrent players (~$0.35 per concurrent player-month,
~$0.04 per DAU-month), meaning roughly 2,000 monthly payers cover it entirely and the
rest of the budget is labor — which is exactly the conversation this document is a
baseline for.*

---

**Sources (server-price anchors, read 2026-11-05):** Hetzner cloud lineup
(hetzner.com/cloud, hetzner.com/cloud/shared-vcpu), Hetzner AX matrix
(hetzner.com/dedicated-rootserver/matrix-ax), Hetzner auction FAQ
(docs.hetzner.com/robot/general/server-auction-faqs), per-instance tables incl. 2026
adjustments (costgoat.com/pricing/hetzner, betterstack.com linode-vs-hetzner guide),
DigitalOcean droplets & managed PG pricing, Fly.io pricing service, Neon pricing,
Supabase pricing, AWS GameLift instance + Anywhere pricing pages, EC2 c6i.large reference.
Exact CPX/CCX figures vary by source (April vs June 2026 adjustments); verify in Hetzner's
calculator before committing budget.
