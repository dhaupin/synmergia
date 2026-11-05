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
| The deed plate — the achievement walk-back over the model's earn rails | AGREED, designed | §18 |
| The Homestead Ledger — the deed cottage, the hallmark law and the homestead tolls | AGREED, designed | §19 |
| The Waystone Ledger — the Bender-only recall fix + the three-charge party stone | AGREED, canon landed | §20 |
| The Anchor Room — the pub's own door: room clock (deed grant vs clock buys), tavern license, hallmark furniture, one-click travel | AGREED, designed | §22 |
| The Sponsor Stage — the $20 public pace stage; the rate is the ceiling, buys stack the clock; Investor suffix / Philanthropist prefix | AGREED, designed | §23 |
| The Investor Stool — reorganized into the focal answers (Hearts / Margin / Cadence / Grudge) | AGREED, doc-only | §28 |
| The Consecrated Ankh — home respawn; dedication earn → 4h clock, bought blessing → 6h clock; permanent | AGREED, designed | §27 |
| The Grudge Book — belfry rites, pledged rivalries, "the Unforgiving" / "the Spiteful" split | AGREED, designed | §25 |
| The Glad Ring — announced bouts, best-of-5 rounds, gold-only book, purse + rake | AGREED, designed | §26 |
| The Tide-Mender Trade — vehicle wear, repair + modifiers; the two movers (personal vs ancient); no engines, all clock | AGREED, designed | §29 |
| The Concord's Table — the money ladder: every seat, SKU, price, sink kind + earn path on one page | AGREED, canonical | §30 |
| The Mystery Gate — the ancients' wake-keys: server puzzles, tram effort, observation, interaction, pure luck; some keys sealed server-side even from dev docs; nothing purchasable wakes the unwoken | AGREED, canon | ancients PRD |
| The Oracles — the wish to wake, priced in shots: sidecar wisdom batches + the Sigil meditation; buy the shot, never the act | AGREED, designed | §31 |
| The Wake Event — every wake prints a free ceremony, the record names the first waker forever; the Peal's second voice sells the echo | AGREED, canon | §32 |
| The Civic Bill — woken ancients accrue stewardship on a TAKE-family book; the Steward's Pledge adopts an ancient, never a toll discount | AGREED, canon | ancients PRD |
| The Warrant Board — bounties on mysteries (vant-modeled): purses escrow-held never debited, settle a record-read, sweeps return expired purses whole; the Crier buys front-page days, the rake cuts at settle | AGREED, designed | §33 |

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

## 18. The deed plate — spitball #7 (2026-11-05)

> **Status: AGREED.** The owner's pitch: achievements alongside the model — "the
> Chosen is def achievement territory — get your first Spiritbound item." Buffy's
> yay with one sharpening: the plate is not a new economy, it is the EARN SIDE
> the model already runs, made visible. The schema was built for this and never
> met a customer: `AchievementData` carries Rarity tiers, `title_reward`,
> `hidden` + `secret_description`, a meta-ACHIEVEMENT category with
> `required_achievements` chains, and 32 authored definitions already ride
> `AchievementService` + its listeners. The plate needs laws, not a system.

**THE WALK-BACK (the plate's seats across §§9–17):**
- **§14 Lucky → "the First Landing."** the owner's own: first spiritbound item —
  HIDDEN until landed (the schema's mystery fields; the "hehe" economy is
  fielded), LEGENDARY by construction, and the Chosen prefix (§17) mints from
  the SAME trigger — the plate and the title are one fact read twice.
- **§14 fated stamp → "the Fated Find."** a rare item stamped bind-on-luck; the
  find is celebrated, the charm that enabled it never is.
- **§10 Mythos → "Proven."** own a Mythos exclusive graded Proven (100% deed
  pooling) — the purse grade becomes a trophy the wallet cannot fake.
- **§9 Charter → "the Earnest One."** a Charter bought WHOLLY on 300
  earned-only sigils — the F2P door exercised as an event. The single
  purchase-adjacent seat, and it is still a deed story: deeds did the buying.
- **§11 dyes → "Full Spectrum."** a complete authored dye family carried across
  the carriers.
- **§12 wardrobe → "Handled."** the first locker move: an owned look carried
  across owned carriers.
- **§13 heraldry → "the Standard Bearer."** your crew's kit flying in a world
  event.
- **§15 Whisper Ledger → "Named on a Page."** the Peal'd finder reads their own
  name at the almanac's dawn — the record becomes the trophy.
- **§16 expedition pack → "Expeditioneer."** a PROGRESS chain mirroring the four
  deed tiers; chartered holds light nothing (§16's law keeps).
- **§17 meta → "the Full Rope."** a `required_achievements` chain over the
  rope's prefix plates — the meta-ACHIEVEMENT category's exact purpose.

- **§19 homestead → "Settled."** a player's first front door landed the
  EARNED way; a chartered buy fires nothing — the plate read stays world-only.

**Laws of the plate:**
- **The plate reads the world, never the wallet.** No achievement fires on a
  purchase act. The Earnest One is the standing exception and it is a deed
  story (earned sigils doing the buying). Chartered holds, bought suffixes and
  kit wallets mint nothing — the quiet seats stay quiet.
- **Verbs, never grinders.** The canon quest law verbatim: "collect 10,000
  herbs" stays banned; every plate answers one of the world's own verbs (a
  landing, a find, a glide, a page, a banner).
- **One derivation, three readers.** The trigger fact is read by the title mint
  (§17), the Ledger chapter (§15) and the plate — never a parallel counter. The
  honesty-law pattern, now in its third dress.
- **Every plate free by construction.** Money never lifts, skips or buys
  progress (the jackpot law extended plate-wide); rewards pay through the
  schema's own gold/xp fields — earned by act, never by invoice.
- **Rarity follows the verb.** How rarely the world does the thing, not how
  much was spent (the title law extended).
- **No new fields.** Mystery = `hidden` + `secret_description`; trophy titles =
  `title_reward` resolving to the SAME authored TitleData `.tres` the ropes
  mint — never a copy.

**Implementation seat (a build round):** authored achievement `.tres` riding the
existing `AchievementListeners` bridges (the plates subscribe to events the
listeners already track, including the §14 landing event and the fated stamp);
the item-catalog receipt grows the coupling law — every `title_reward` resolves
to a real authored TitleData. Zero new systems.

## 19. The Homestead Ledger — spitball #8 (2026-11-05)

> **Status: AGREED.** Buffy pitched housing (the owner's "immediate lasting value"
> pillar); the owner yay'd all three seats and added the P2W balance by amendment:
> EARNED housing gets its first deed move FREE, the PAID door carries a +20% move
> cost, and a catalog signature piece (the special hearth) carries a small luck damp
> — the §16 chartered shape, verbatim. Rails verified before the write:
> `DwellingService` stands (plot 50k / house 750k / guard 250k / ankh 100k — ALL
> priced in gold, with placed stations hosting the real `CraftingService.craft` gate),
> §11 already names housing furniture among its carriers, and the almanac owns the
> world's clock. The deed move is NEW furniture authored in this section — nothing
> relocates a homestead today — with its pricing born inside the toll law.

**THE THREE SEATS (owner amendments folded in):**
- **Seat 1, the front door — TWO DOORS, ONE COTTAGE.** the deed ladder's flagship
  reward: a first plot + deed cottage earnable fully FREE by deed milestones
  (~a month of honest play, the §16 week-per-tier shape). Gold plot prices stay the
  in-world economy — real money never touches a price tag, only the clock door's SKU.
  THE CLOCK DOOR: money buys the same cottage NOW — the **chartered homestead**,
  provenance-stamped in the account ledger — and the clock is the only thing it buys
  (§16's law holds: money buys the clock, never the ceiling).
- **Seat 2, the furniture two-lane — THE HALLMARK LAW.** field furniture is
  craftable (furniture bills at the REAL stations — a placed station gates through
  the same `CraftingService.craft` a bench runs); catalog kits sell spectacle +
  breadth only (§11 law verbatim: never exclusivity of a field-reachable look);
  furniture paint rides the dye lanes; kits ride the §12 locker overlay the moment
  the overlay decision reaches housing. THE HALLMARK: crafted furniture carries the
  maker's hallmark and grades Proven by the §10 purse law; catalog furniture is
  hallmark-less and stamps no deed-truth — a hall dressed wall to wall in kits reads
  *nice hotel*, and any visitor can see it. Deed-made furniture is worth more, and
  the crafter industry wins to the kits, not loses.
- **Seat 3, the deed museum — the earn side stands in the world.** the deed plate
  (§18) and the Ledger's chapters (§15) get a physical seat — the deed bookshelf
  station and the front-door plate, readable by visitors. A home is a résumé: walk
  another's hall and you see the Chosen prefix its owner minted, the pages their
  finds printed, the rarity lines. Housing becomes the display case the whole earn
  side already earned.

**THE TOLLS (the owner's amendments, ridden as the §16 chartered shape):**
- **THE DEED MOVE** (new mechanic, born this section): relocating the homestead —
  re-stamping the plot deed and hauling placed objects to the new grounds. Pricing
  reads provenance: the EARNED cottage's first move is FREE (the courtesy a deed
  buys), later moves at the flat rate; the CHARTERED homestead pays **+20% on every
  move** — money bought the arrival, never a cheaper road.
- **THE CHARTER'S TOLL ON SIGNATURES.** catalog signature centerpieces (the special
  hearth and its showcase line) carry the toll's other face: a small authored luck
  damp (~5%) while the piece stands placed, riding §14's ONE central roll-time
  modifier beside the chartered tiers — tolls share the central bucket, never
  per-item bandaids, and the spiritbind jackpot leg rolls identically beneath all of
  them (§14's law keeps: nothing buys the jackpot). The damp is visible on the
  piece's item card and the purchase flow.

**PLATE CROSSING:** §18's walk-back gains one seat, appended there —
**§19 → "Settled."** the first front door landed the EARNED way; a chartered buy
fires nothing.

**Laws of the homestead:**
- **Furniture is a look, never a number.** zero stats, zero function — no
  home-hearth heal, ever; the signature damp is a tradeoff the buyer carries, never
  a bonus anything gets.
- **Placement scopes are service truth and never sold.** nothing real-money
  confers, widens or pries an access scope.
- **NOBODY BUYS AN HONOR.** the chartered homestead mints no house name, no gate
  title, no plaque wording — honors are deed-minted (§17's law walks home).
- **Prices stay gold.** the in-world economy (plot, walls, guard, ankh) keeps its
  currency; real money touches only the clock door SKU and catalog looks.
- **Preview never debits; tolls are authored and visible** on the piece's card and
  the purchase flows (the §10/§14 shape).
- **Rarity follows the verb.** the hallmark's grade, the deed truth, the visitor's
  read — never the wallet.

**Implementation seat (a build round):** the clock door SKU + catalog kit SKUs ride
the webhook-provider seam (§9's shape); sink rows carry toll fields (§10's
stamping); the deed move rides `DwellingService` as a relocation command reading
the account ledger's deed/bought stamps for the FREE/+20% legs; hallmark fields on
furniture item cards (provenance reuses the purse stamps); the deed bookshelf and
front-door plate read the SAME account ledger through the deed plate's readers
(§18 — no new shelf of truth); the cottage's deed ladder rides the deed sources
§§9–16 already run (quest milestones, ledger appearances, heraldry deeds — one
book of acts, one new shelf). Zero new services.

## 20. The Waystone Ledger — spitball #9 (2026-11-05)

> **Status: AGREED.** the owner pitched the FIELD DOOR: UO-style recall runes landing
> through the res shape ("instead of res, ~3 teleports on a stone — then the stone
> dies"), scoped to the decision from the project's ancient times: BENDERS were the
> only class that could teleport its party, and everyone else deserved a door. RAILS
> VERIFIED: the res rails stand (`item_soulbind_ticket`, stack 10, soulbound, 25-sigil
> sink ≈ $1.25); the class family table carries the Bender row (Akkan → Seer, Human →
> Temporalist, Synthetic → Overclocker, role = 5); and the "benders port the party"
> canon line existed ONLY as institutional memory — the grep found nothing in any PRD
> or class data — so this section writes it into the canon BEFORE it sells anything.

**THE CANON FIX, FIRST.** `prd.md`'s class table gains the standing line it always
deserved: **Benders are the only class family that can teleport party members** —
one verb, three voices (the Seer's spatial fold, the Temporalist's slip, the
Overclocker's blink). The waystones below are the door for everyone else, and they
never dilute the class edge: a stone is slower (a 6-second channel, never instant),
charge-bound, and mark-scoped — a Bender ports faster, farther, free. The class
stays better at its own verb.

**THE STONE (three seats, one item family):**
- **MARK.** a blank stone kneels and inscribes (3-second channel): the player's
  CURRENT standing ground is written in, one place per stone — the item speaks its
  mark on its own card ("Waystone: the Salt Pans"). UO's rune-marking, authored.
- **RECALL.** the charge spend: three charges, then the stone crumbles to dust and
  the mark dies WITH it (no orphaned marks — the world forgets at the same pace the
  stone does). Any party member may inscribe; the recall is a PARTY CALL — the
  caller pulls their own party to the mark, each member answers through a 10-second
  consent prompt (never forced displacement — the honor edge), solo use stays legal.
- **THE PRICE (the owner's felt balance, signed into law).** the stone is BOTH:
  craftable at the alchemy bench from honest reagents (the hours-farm lane), AND on
  the Concord shelf at **15 sigils ≈ $0.70 gross ≈ $0.50 net** (the res row's
  sink shape). The two lanes brew the exact hesitation the owner named — "worth it
  right now? it'll cost me hours to forge another, but then again it's only $0.50"
  — THE WORTH-IT SCISSORS: a sink earns its keep only when the price tugs.

**LAWS:**
- **Convenience, never power.** a recall unsticks nobody's math: no XP, no gold, no
  stat, no cooldown shortcut on anything the world sells — the §9 charter family's
  law holds stone-side.
- **The map's hold is the door.** marks refuse to INSIDE drifts and disputed grounds
  (dungeon entrances, instance doors, warded holds — the recall leg refuses there by
  name); the sea keeps its res law: a recall that would land IN the sea or inside
  rock resolves to the nearest safe ground, never through the world.
- **Consent and cooldown.** party members are never yanked unbidden (the 10-second
  prompt); the recall leg rides the game's own QoS rate gate (the roll board's
  `CooldownService` law) so a stone is a door, never a spell macro.
- **No charter gate, no toll, no grade.** the stone is a one-time sink like the res
  ticket — money never mints permanence here, so the §16 chartered shape does not
  apply; the shelf row and the bench bill are priced as sinks, period.
- **Preview never debits.** the stone's card shows its charges remaining and its
  mark, the shelf shows the price before any click, and the consent prompt shows
  the destination before any accept.
**THE OWNER'S AMENDMENT — THE OPEN MARKET (the runner industry):**
- **THE STONE TRAVELS.** never soulbound — the deliberate divergence from the res
  rails (the Soulbinder's Ticket binds to the hand that needs it; a waystone binds
  to its PLACE, and places pass hands). Stones ride the trade window from birth
  (`TradeService` stands) and the player markets the day that seam lands.
- **THE RUNNER INDUSTRY** (the owner's living): marking stones is a VERB, not a
  chore — a runner crafts blanks (the alchemy bill), inscribes fresh 3/3 marks at
  the doors people want (the dungeon mouth, the harbor berth, the deep-dive shelf)
  and sells them at prices they set. The sink multiplies by design: every traded
  recall consumes a stone, every consumed stone sells a blank, every blank pulls
  reagents — the runner is the supply chain, and nothing mints marks for free.
- **THE GAZE BEFORE THE LEAP** (the owner's anti-ripoff seat, law-grade). viewing
  OR using a stone pops the destination BEFORE anything fires: the mark's name,
  its zone, and the map ping to the exact spot — a destination-confirm step with
  no hand taken (preview never debits, in its most literal dress); a recall leg
  without a confirm path refuses to exist. The spent stone stays spent, so the
  gaze is the guard — and it is SERVER TRUTH: the eye sees the actual mark, never
  the seller's blurb (NO FREE TEXT EVER — the destination line is the inscription
  record, not the vendor's promise; AS-MARKED AS-GOES: a stone delivers you where
  it says, the preview proves it).
- **THE MARKET LAWS.** a traded stone keeps ITS mark (the mark rides the item,
  never the marker); a traded blank is a fresh blank (trade never mints marks);
  the Concord shelf price is the floor of the law, not the price of the market —
  player prices float honestly above it.

**Implementation seat (a build round):** `item_waystone` blank + the inscribed state
ride the res-ticket .tres shape; per-item mark storage is the OPEN SEAT and the
market leg makes it LOAD-BEARING (a traded stone must carry its mark through the
trade window, or the runner industry cannot exist) — per-slot item meta does not
exist in the bag schema today, so the interim fallback is a fixed one-mark-per-
character owner-home stone and the instancing decision gets its own build round; the recall leg rides the existing
`PlayerLockService.cancel_on_teleport` chain; the consent prompt rides the party UI
fabric; the shelf row joins the RESPAWN-family sink rows (a new TELEPORT row, same
no-fake-sinks law: the grant leg ships WITH the row or the row doesn't land).
DOC-ONLY round: zero .tres, zero service changes, the pack export stands.

## 22. The Anchor Room — the pub's own door (spitball #10, 2026-11-05)

> **Status: AGREED (owner yay on all seats).** The owner's reading is the pitch: "you
> pay a 'tax' and synmergia allows you to open the pub." A guild (or any standing
> party) holds a persistent SOCIAL instance — one tavern — and runs it the way a
> homestead runs a hall: furniture they crafted, a hearth they earned, and a door the
> world can walk through. Rails real before the seats: `InstanceService` spins live
> instances today; prd-social-instances.md's social law is presence ambient, action
> one click; §19 owns the furniture laws.

**Seat 1 — the pub tax (the room clock).** A deed-earned weekly allotment keeps the
honest door open: several held evenings a week at zero cost (the §16 week-per-tier
shape). Money buys MORE CLOCK and LONGER HOLDS (the charter-tier shape), never bigger
rooms, never broker content. Payable from the §13 guild vault (rank-gated, the mix
tracked) or by the deed holder's own ledger.

**Seat 2 — the tavern license (the owner's tax).** A held room DECLARES itself OPEN:
the door lists on the world's travel board and anyone may walk in. The deed plate's
name IS the advertisement — there is no custom signage to buy.

**Seat 3 — the furnished night.** The hallmark law verbatim (§19): field tavern
goods — bar, long table, lantern rings — craft at the real stations and carry the
maker's hallmark, grading Proven by the purse; catalog kits sell spectacle + breadth
only. A hall dressed wall-to-wall in kits reads "nice hotel" to any visitor: crafted
furniture is worth more and the crafter industry wins.

**Seat 4 — the door that travels.** Entry is one click from ambient presence: a
friend inside shows "join" (the LFG petition path), the open pub shows on the travel
board. The pub is a social MODE, not a standing cost — the clock runs while held,
never while you sleep.

LAWS: a room is a look, never a number — no combat stats, no buffs, no
my-pub-is-statistically-better; money never buys content the free doors don't also
get (the early-entry law: never a paid "see things first" stage); tolls orthogonal
(the Charter never gates a pub); placement scopes are service truth and never sold;
preview never debits; no free text ever — signage and the queue line read service
record.

IMPLEMENTATION SEAT (build round): the persistent hold keyed (world, owner, slot)
through the existing instance lifecycle; the travel-board row as a thin reader of
that hold record; tavern furniture as furniture carriers on the §19 rails (dye lanes
and the §12 locker overlay apply); the room clock as a ledger tx leg; a small public
board page reading service truth only (names, nothing personal).

## 23. The Sponsor Stage — the shard's public rite (spitball #11, 2026-11-05)

> **Status: AGREED (owner pitch, Buffy yay + dress).** The owner's shape: **$20 buys a
> server-wide stage — +10% drop AND xp for EVERYONE for 40–60 minutes** — with the
> sponsor's name, guild and faction credited across the whole hour, and the roll
> public on the website. The ego is the product and the buff is everyone's: nobody
> buys personal power, the whole shard rides the same clock.

**The rate is the ceiling (the clock law, literal).** Concurrency never stacks the
rate: a second $20 during a live stage EXTENDS the stage's clock, never makes it
+20%. The ceiling is authored at +10% and no purchase moves it — money buys the clock,
never the ceiling, in the section that proves the law was written for this.

**The sponsor's credit (the roll).** Name + guild + faction read from the service
record; the in-world banner and the website's public roll page show the same truth
(who, when, how long). **NO CUSTOM MESSAGE — the owner's anti-abuse call, become
law:** the stage has no message slot, period. The no-free-text rule in a sponsorship
jersey: nothing to moderate and no report flow needed.

**The combat-stat firewall.** The stage never touches duels, arena or rated rooms;
those read base rates at all times. A personal statistic changes by purchase NOWHERE
in this section.

**The title split (the owner's fairness model, the §17 ropes shape).** The BUY route
mints the suffix "the Investor" (the baron's shape: a sale mints a suffix, at most).
The DEED route — a stage slot bought whole on earned-deed sigils, the §9 charter's
two-way door — mints the prefix "the Philanthropist," deed-minted only: NOBODY BUYS
AN HONOR. The wallet can buy the hour; it cannot buy the prefix. A paying player
earns "the Philanthropist" the same grind way as anyone else and gets nothing early
for paying — fairness for the grind, exactly as pitched.

**An honest seam, recorded.** §9's no-XP law governs PERSONAL and track purchases.
This stage's XP leg is the owner's authored exception for the PUBLIC shape: every
rider, paid or free, shares the identical +10%, so the exception runs ALONGSIDE the
law (it lifts the shard, never the individual) and is capped to this section. No
personal XP purchase exists anywhere in the model; nothing else ever lifts XP.

**The F2P door on everything.** The stage slot itself prices two-way ($20 OR its
earned-deed sigil price — the §9 charter's 300-sigil shape; the exact number is a
build-seat tuning). The free row never rides worse than the seat next to it.

LAWS: the buff is public-domain (nobody buys personal or party power); the ceiling
never moves; credit reads service record only; no refund once the stage starts;
preview shows remaining window + rate BEFORE purchase; no Charter gate; toll
orthogonal (a sponsor's deed-versus-buy provenance is recorded, graded nothing).

IMPLEMENTATION SEAT (build round): the stage clock keyed on the shard ledger (the tx
roots stay the spine); the +10% drop leg riding THE SAME central roll-time modifier
§14's luck charms landed on (one bucket, never per-system bandaids) and the XP leg on
the gain hook — `LevelCurve` remains the ONE authority (the stage changes the gain,
never the curve file); the roll page reading service truth; one $20 SKU riding the
webhook seam + a STAGE sink row; prefix + suffix `TitleData` rows minted per the
deed/buy split.

## 25. The Grudge Book (spitball #13, 2026-11-05)

The spite model, seated. The rails stand verified: ArenaRoomService records
RECENT_PLAYERS per participant on every bout_ended (zone, mode, result, when, the
head-to-head line), the one-click Rematch is SHIPPED, and every consent path is
hard law. The stool's Leg 4 clears its TBA here.

**Seat 1 -- the Rematch Belfry.** The duel never changes and never costs anything:
same arena ladder, same consent, base rates. What is sold is the event wound
around it. For a bout between two fighters on each other's heated-rival list,
either side may ring the Belfry -- a zone bell, then a banner in the sec 15
Whisper Ledger's exact dress: an authored template sentence filled from the
service record ("Belfry: Kestrel and Oldwren settle their grudge at the Salt Pans
-- 2 losses in the book"). NO FREE TEXT EVER runs here verbatim: the line reads
the record, never a vendor's promise. The rite is a one-time consumable, priced
on the pot charm's affordable impulse shape (~$1.25 net), deed-or-buy two-way.

**Seat 2 -- the Grudge Book proper.** The shipped ring buffer stands free (twenty
bouts, FIFO). New free rail: any player may PLEDGE one active rival -- recorded
server-truth, both fighters see it, zero cost, unpledging free. The paid leg is
CAPACITY: each additional pledge is a spare row in the book, every slot
deed-earnable in roughly a week or bought on the chartered family with the
central-bucket toll (the sec 16 expedition pack's own shape). Capacity, never a
stat; the pledge itself is never sold as privilege -- everyone owns one.

**Seat 3 -- the Settled Score.** Title split, the owner's fairness model verbatim:
a PLEDGED grudge settled by winning mints the prefix "the Unforgiving" -- deed by
construction, NOBODY BUYS AN HONOR. The belfry rites (the buy route) mint at most
the suffix "the Spiteful" -- the baron's shape. The same grind reaches the good
name whether paid or not.

**LAWS (the spite firewall).** Nobody buys power over another player: no curses,
no debuffs, no enemy-facing anything ("no enemy-facing aura debuffs, no social
engineering", the sec 9 charter verbatim) -- spite is CELEBRATED, never
WEAPONIZED. The Rematch click and every consent path stay free forever. Banners
are server truth. AppFirewall's one-duel rate limit rides untouched. Spectate
seats stay the social doc's parked shape (greyed with a tooltip, never hidden)
until spectating ships.

IMPLEMENTATION SEAT (build round): the pledge leg on the recent-players ledger
(ids and standing stamp only, the security note verbatim), the belfry rite .tres
+ its sink row + the zone event + the banner line through the sec 15 broadcast
rails, the pledge-slot SKU on the chartered family, two TitleData rows on the
sec 17 shape.

## 26. The Glad Ring (spitball #14, 2026-11-05)

The owner's ball: gladiator-style spectator wagering on certain duels -- the
high-profile bouts are PLANNED and ANNOUNCED ahead of time, fought over multiple
rounds like boxing. The fighters make out well, the engine makes out well.

**Seat 1 -- the Gladnight (the venue clock)** rides the sec 22 Anchor Room shape
verbatim: on a held pub evening the open ring runs as the Glad Ring. The
deed-earned allotment runs it free; money buys a LONGER clock and extra announced
weeks -- never better floors, never broker content. The clock door is the pub
tax's own jersey.

**Seat 2 -- the Made Bout (the fight card).** A fighter with an active sec 25
pledge may MAKE the bout: a Glad Ring match scheduled to an almanac day and
announced ahead on the schedule board -- both fighters' names, the rounds format
(BEST-OF-FIVE, 60-second break between rounds), and the feud's head-to-head line
printed from service record. Both fighters sign consent; the board announces to
the shard. NO FREE TEXT: the card reads the pledge and the record, never a
promoter's blurb.

**Seat 3 -- the Book (the wagering).** GOLD ONLY: real money never places a bet
and no sigils touch the felt (the RMT firewall -- gold in, gold out, the house
takes its cut). Odds are SERVER TRUTH: the same head-to-head ledger the Grudge
Book reads, printed as authored template lines the almanac carries beside the
card ("the pans book called it 3-to-1"). Bets open when the card posts and close
at the first bell (the closed-book law -- no mid-round action), settling per
round and for the bout. A per-account, per-almanac-day wager cap (small, the QoS
rate-limit family's own shape) keeps impulse lawful.

**Seat 4 -- the Purse and the Rake.** The winner's purse is the bet pool minus
the rake; the RAKE (authored 10%) is gold to Concord -- a new sink row under the
no-fake-sinks law, audited beside the roll board. Fighters may hang a SPONSOR'S
NAME on the card -- the sec 23 dress verbatim: service-record credit, no custom
message, nothing to moderate. THE COMBAT FIREWALL IS VERBATIM HERE: duels, made
bouts, rated rooms and the Book read BASE RATES always -- no rate ever moves by
bet, bell or banner.

**The Undisputed.** A champion of made bouts mints the suffix "the Undisputed" --
deed by construction (winning is a verb); no purchase route exists for it at
all. The prefixes of this economy were minted in sec 25 and stay deed-only.

LAWS: both fighters consent and either may walk before the first bell; no
fighter wagers on their own bout; the rounds format is identical for every bout
(money never authors a friendlier shape); the rake is authored and visible.

IMPLEMENTATION SEAT (build round): the rounds format + break clock on the duel
lifecycle, the card and odds reader beside the travel board on the almanac's
schedule page face, the wager window + cap on the account ledger through the tx
roots, the rake + Gladnight sink rows, the made-bout board.

## 27. The Consecrated Ankh (spitball #15, 2026-11-05)

The owner's easy win, the house's oldest seat: the ANKH item already exists --
DwellingService prices it gold (100k) and the sec 19 homestead rails carry the
placement. What never existed is the BLESSING: a plain ankh is an inert device.
This section authors it: resurrection at your own house, the death screen's third
door, and the clocks are the toll.

**Seat 1 -- the Door.** When a fighter falls and holds a CONSECRATED ankh, the
death screen gains a line: "Ankh at Home" -- stand up at the ankh's placement in
the held cottage. The fall never teleports the living; the death door is the
door. The cooldown book is read BEFORE the door shows green: a cold ankh greys
with a tooltip (the social doc's parked shape -- greyed, never hidden), the
screen prints remaining time, and looking costs nothing (preview never debits).
No charge takes while the door is dim.

**Seat 2 -- two blessings, one ankh, the clocks honest.** The blessing is EARNED
or BOUGHT -- never both at once, never a subscription.

THE EARN -- THE DEDICATION: after achieving a house, the clergy opens a
dedication chain -- a couple of weeks of earned deeds (the sec 16 week-per-tier
shape) gated on the actual DwellingService dwelling record, not a receipt,
riding the real quest rails. The earned blessing runs the FASTER clock: house
respawn every FOUR HOURS.

THE BUY -- THE CHARTERED BLESSING: money skips the dedication and consecrates
TODAY. The bought blessing carries the toll in its only lawful dress, TIME (the
sec 16 chartered shape verbatim): house respawn every SIX HOURS. Same door as
the grinder's -- the grind keeps the sooner clock, the wallet buys the door NOW.
Nobody buys a better ceiling; they buy today.

**Provenance and cooldown.** ONE blessing per homestead, PERMANENT (a purchase,
never a lease, purchases-permanent law), stamped in the account ledger through
the tx roots as EARNED (4h) or BOUGHT (6h) beside the dwelling record -- provenance
reused, the sec 10 purse law. The cooldown is ONE keyed book per account
(CooldownService's book, NOT the central roll-time modifier -- this is a clock,
never a die); it starts at use and prints concrete remaining time at the death
screen. The blessing is keyed to the DWELLING, not the plot: a sec 19 deed move
carries the blessing intact (the earned blessing moves free the first time; a
chartered homestead's move toll applies as authored already -- the blessing
never re-bills).

**LAWS:** convenience never power (no XP gain, no gold-per-death, no stat, no
combat rate touched -- the sec 9 charter family holds ankh-side); the ankh
resurrects, it never TRAVELS the living (a revival door, never a travel door --
the sec 20 map's-hold-is-the-door scope stays separate); death never loses its
free doors (zone spawn and the shipped stand-up remain every account's constant
floor -- the ankh is a THIRD door, never a toll-gated only door).

IMPLEMENTATION SEAT (build round): the door-routing on RespawnService's
death-screen reader (ownership + ankh-placed + the blessing, read from
DwellingService), the cooldown book on the account ledger via the tx roots, the
dedication quest chain on the quest .tres rails gating the dwelling record, one
webhook SKU + a new sink row (BLESS family, the no-fake-sinks law: ship the
grant leg with the row), the blessing field on the ledger's provenance print,
and the death-screen line + a11y remaining-time text.

PRICE FELT: the bought blessing sits at the doc's small-SKU top -- a one-time
~$4.99 (the Charter's own price point riding the existing webhook processor
SKUs). The exact cent is a build-seat number; the owner's veto reserved.

## 28. The investor version (the one-paragraph answer)

*Synmergia's monetization is not a plan, it is an installed, receipt-audited system: a
wallet, three real-$ SKUs ($4.99–$24.99), a nine-row premium catalog (resurrection
tickets at $1.00 net per unit, a $7.50–$45 mount ladder, cosmetic titles at $10–25),
an in-game sigil market, a four-tier expedition storage ladder where deeds earn the slots and the wallet only buys the clock (a chartered buy carries a small authored luck-toll), an achievement plate that reads nothing but the world's verbs (gold, coin and title rewards — never purchasable), a homestead with an earned front door (the clock door carries the move-toll and the signature toll, furniture sells breadth under the hallmark law), a public tavern door (the Anchor Room: guilds buy the pub's hour by the clock and the deed grant keeps F2P honest), and a sponsor stage (the $20 public pace stage where the rate is the ceiling and buys stack the clock — paid mints the Investor suffix, the deed route mints the Philanthropist prefix), and an earned-earn path that keeps F2P honest, a vehicle trade under one law (the Tide-Mender Trade: stations mend free, the kit mends the field, modifiers lace capability — never a rate, never an engine), a Mystery Gate that prices nothing (the ancient movers wake by server puzzle, tram effort, observation, interaction or pure luck — some wake-keys sealed server-side, beyond our own docs by design — and no purchase ever opens a gate; the Oracles (sec 31) lawfully sell only the wider SHOT on the same sealed doors — wisdom batches and meditation days, more dice never a better die; and the wake event (sec 32) is the owner's investor leg ON PURPOSE — a permanent ledger (first-waker names ride the wake record forever, the ego stoked by a suffix minted by the record itself), an easy spend on a hair trigger — the celebration permit bought at the emotional peak -- the lab: labs/prd-ancient-movers.md), and its Concord's Table pricing the whole SKU stack on one page, and
a Warrant Board (sec 33) keeping the owner's UO bounty want lawful —
purses announced on mysteries into escrow, settlement a deterministic
record-read nobody can whisper around, a Crier toll that buys
front-page days, a house rake at settle, and the hunt itself the free
door (the head is a record, never a scalp). Publishing
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
### The investor stool — the four focal answers (spitball #12, 2026-11-05)

One model, four hats: an investor hears the one they sit on. Every answer below is
honest on its own — no leg contradicts the paragraph above it, because they are all
readings of the same math.

**Leg 1 — the Hearts answer (the ego economy).** "Players never rent power here —
they buy *presence*: their pub's door on the world's travel board, their guild and
name over the shard's +10% stage, a waystone that remembers a place and passes hand
to hand. Emotional spend means no pay-to-win lawsuit surface and no whale churn
cliff — every dollar builds a legend, and legends retain."

**Leg 2 — the Margin answer (the cost side).** "~$0.04 per DAU-month and ~$0.35 per
concurrent player-month at 10k CCU, benchmarked against dated publisher-page
anchors. About 2,000 monthly payers cover the entire infrastructure budget, and the
rest of every dollar is margin or labor. Costs are measured, not vibes."

**Leg 3 — the Cadence answer (the machine).** "Content ships by a signed income
law: seasonal packs author income against the shared level curve, the cap lifts on
data not opinion, and publishing cadence is contractual. Investors underwrite a
schedule, not a hope."

**Leg 4 — the Grudge answer (the spite model — TBA).** Revenge, grudges, rivalry:
the fourth psychological model — folks spend before thinking when a name is in
front of them. The rails already stand: the recent-players heated-rival list and
its one-click Rematch are this psychology's front door. The concrete spend seats
landed as §25 (the Grudge Book) — the seats inherit every law in
this document (no stat purchase, no free text, the authored-tradeoff rule), so the
investors' line is honest: *impulse spend is the cheapest product we do not yet
sell.*


## 29. The Tide-Mender Trade (spitball #16, 2026-11-05) — vehicles, worn and woken

The owner's abstract, adopted whole: the Mender's Kit is not a boat story. It is
the standing TRADE for every mover Synmergia has and every mover it will add —
vessels, mounts and tack, gliders, breather helmets, and the woken platforms
(the Conduit Glider, Islet Lifter and Caravan Crawler ride the gemini vehicles
seed rails: multi-passenger platforms woken by a tablet, never built or fueled).
One trade law, every mover, the kit grows to fit.

**The two movers (canon from this round; world-building PRDs make the
distinction wherever they speak of vehicles).** PERSONAL MOVERS: a player-owned
mover — a granted mount on the RideService ledger (single-rider, the riding
layer's one ledger), a platform woken by YOUR tablet, a glider you own, a
helmet in your bag. Personal movers wear honestly, repair freely at stations,
take kits into the field, and take modifiers at the bench. ANCIENT MOVERS: the
server-unlocked ancients — the ferries (the Gullwing has run the Haven lane
since the first sailing law; the ferry honesty law's "server-owned vessel" is
this canon's first verse), the dormant ruin movers, the islets' orb machines.
An ANCIENT mover belongs to no player, never prices a personal SKU, and is
never sold to one — its bill is a CIVIC bill: settlement deeds, warden take,
the same audited Concord sink rows every other civic duty pays. Movers are
kept in two lanes forever, and the lanes never cross in a price tag.

**The no-technology law was already canon.** The vehicles pack wrote it first
("vehicles are woken, never built, fueled or manufactured; no engines, no
wheels, no fuel") — so the owner's extension lands along the SAME lane: in
this world a MEND is binding work, not tech work — re-binding root and
wrapper, re-blessing the orb, re-lacing a conduit seam. A MODIFIER is the same
craft in the other direction: verse work — knot-charms, tablet statutes,
conduit arcanum laced through the mover's own dormant body. NEITHER touches an
engine, because there are no engines to touch.

**Seat 1 — the station bill.** Repairs at any repair station are FREE forever.
Fenwick's pending tide-side service is this trade's first desk: dock-side,
free, the honest wear of a used hull settled at the bench.

**Seat 2 — the field kit.** A Mender's Kit is a CRAFTABLE CONSUMABLE: built at
Fenwick's bench from an honest salvage haul (things that were wet get mended
with wreck things), good for exactly one field mend on any class of personal
mover — vessel, mount, glider or helmet. The IDENTICAL kit sits on the Concord
shelf for the took-it-now player (the waystone row's sink shape, ~$0.50, felt
number in the owner's hands). Two-way by construction: every shelf kit is
craftable and every craft is free; no coin ever mends a kit better and no kit
ever knows it was bought.

**Seat 3 — the modifiers lane.** The owner's extension, dressed in the world's
own voice — capability, never tech tuning. Laws before any SKU: (a) a modifier
NEVER moves a combat rate, not one tick; (b) a modifier NEVER raises a
travel-speed ceiling — movement profiles are the one derivation and they stay
data; (c) what a modifier may buy is capability and comfort verbs — a
deep-lung verse for the breather, a quiet sail, a grip that holds through
swell — capability, and time, never the rate family; (d) two-way: the same
modifier is earned by crafter bills and deeds or bought on the chartered
shape, an authored, visible toll in the chartered family's currency (the clock
runs the verb's quiet stretch, never the verb's strength); (e) provenance
stamped EARNED/BOUGHT in the account ledger beside the mover's own record.

IMPLEMENTATION SEAT (build rounds, gated on movers that exist to mend): the
kit .tres + a shelf row + a new MEND sink family (the grant leg ships with the
row), Fenwick's repair service as the trade's first station, wear and cooldown
books on the mover's ledger through the tx roots, modifier verses on the
chartered family. PRICING FELT: kit ~$0.50 shelf; modifier prices felt when
the first woken platform ships — all build-seat numbers, owner's veto
reserved.

## 30. The Concord's Table (spitball #17, 2026-11-05) — the money ladder, canonical

The owner's second yay: the doc has earned the investor hat — the whole
machine on one page, one row per seat, each row carrying its SKU, its felt
price, its audited sink and its honest earn path. The F2P trust floor stops
being a promise and becomes a COUNT — investors read the table and see, row
by row, what is sold, what is sanked, and what stays free.

| # | Seat | SKU / how it is sold | Price felt | Sink kind | Earn path (the free door) | Home |
|---|---|---|---|---|---|---|
| 1 | Season Charter | one purchase per season, real $ | ~$8.99 | catalog receipt | purchasable whole on ~300 earned sigils (F2P two-way) | §9 |
| 2 | Mythos exclusives | catalog exclusives, charter-free buys | exclusive-priced | toll fields in sink rows | craft / find routes always exist; earned grades Proven, bought grades Bought | §10 |
| 3 | Dye spectacle + colorist license | shelf dyes + reusable permit | kit SKUs, ticket-shaped permit | COLOR rows | every field look craftable free from harvests | §11 |
| 4 | Wardrobe locker | per-account unlock, one buy | small SKU | cosmetic | field-crafted looks always locker-eligible free | §12 |
| 5 | Guild heraldry packs | vault-bought kits, rank-gated | scales by group | GUILD rows | every guild earns ONE standard banner free | §13 |
| 6 | Lucky | 24h charm x 5 per weekly pot | 25 sigils (~$1.25) each | LUCK rows | days 1-2 of every pot earned nearly free via deeds | §14 |
| 7 | The Peal | permit, deed-earned or bought | ticket-shaped | REVEL rows | the landing rumors FREE to every account, always | §15 |
| 8 | Expedition pack | 4 tiers on the shelf | per-tier, small SKUs | capacity rows | every tier deed-earnable ~a week; the full ladder ~a month free | §16 |
| 9 | Cosmetic titles | suffix-only purchases | ~$10-25 | TITLE rows | every prefix deed-minted ONLY; suffixes by deed, by name, not sold | §17 |
| 10 | Resurrection ticket | 25 sigils (~$1.00 net) x1, x8 at 150 | small SKU | RESPAWN rows | zone spawn + the shipped stand-up free floor, always | §3 |
| 11 | Waystone | Concord shelf | 15 sigils (~$0.70 gross / ~$0.50 net) | TELEPORT rows | craft at the alchemy bench from honest reagents | §20 |
| 12 | Homestead clock door + signature tolls | the chartered homestead, one-time | front-door range | HOMESTEAD rows | full cottage earnable free by deed milestones (~a month) | §19 |
| 13 | Furniture kits + hall dyes | hall kits, catalog looks | breadth SKUs | cosmetic | field furniture craftable; hallmark law: the craft rolls Proven | §19 |
| 14 | The pub's clock | Anchor Room room clock | room-hour SKUs | TAVERN rows | deed-earned weekly allotment opens the pub free several evenings | §22 |
| 15 | The sponsor's stage | 40-60 min +10% shard-wide stage | ~$20 | STAGE rows | ride free like everyone; the deed route mints the Philanthropist prefix | §23 |
| 16 | Grudge seats | Belfry rite (~$1.25), pledge capacity rows | small SKUs | REMATCH + capacity rows | the rematch, the pledge and the prefix all free by construction | §25 |
| 17 | Glad seats | longer clocks, more announced weeks | clock SKUs | GLAD rows | venue, bouts and the book run free on the deed allotment; wagers GOLD only | §26 |
| 18 | Ankh blessing | the Consecrated Ankh, one-time | ~$4.99 | BLESS rows | dedication deed-chain gates the 4h clock (bought 6h) | §27 |
| 19 | Mender's kit | consumable, identical craft / shelf | ~$0.50 | MEND rows | craft at any repair bench from honest salvage | §29 |
| 20 | Mover modifiers | chartered shelf verses, capability verbs | build seat, felt number | MODIFIER rows | same modifier earned by crafter bills + deeds, two-way | §29 |
| 21 | The Wisdom Call | sidecar compute work units (Rust/Julia batches on a named door) | ~$0.25/unit, build-seat | WISDOM rows | small weekly earned allotment via witnessed deeds | §31 |
| 22 | The Meditation Ceremony | ceremony day, Lucky-pot shape (25 sigils ~$1.25) | small SKU | ATTUNE rows | days 1-2 of every week earned free via deeds | §31 |
| 23 | The Wake Peal | the standing Peal permit, rung at a wake (celebration voice) | same Peal permit (deed-earned or bought) | PEAL rows (second voice) | the Peal permit's earn path covers both voices | §32 |
| 24 | The Warrant Board | warrant purses (announced, escrow-held) + the Crier toll + the house rake at settle | purse chosen by the poster; the Crier a small clock SKU | MERIT + CRIER rows | the hunt and every claim are free; bounties are purses posted into a hold, never purchases | §33 |

**How to read the table.** Where money buys the clock (rows 6, 8, 14, 15, 17,
18), the chartered shape is the toll family and the toll is visible; where
money buys presence (rows 3, 4, 5, 7, 9, 13), no rate moves anywhere; where
money buys the NOW (rows 10, 11, 12, 18, 19), the same door stands free by
deed. Two structural rows hold the top: the Charter (row 1) is cosmetic plus
convenience with an earned-sigils purchase door, and Mythos (row 2) is the
provenance-graded tradeoff. The count is the pitch: TWENTY-FOUR rows stand priced
and NONE turns a stat on by purchase (rows 21-22 sell only the wider SHOT
at the unopened doors — the Oracles: money cannot buy the act; row 23 is
the Peal permit celebrating in its second voice — the echo bought, never
the event; row 24 posts purses on mysteries — the Crier buys front-page
days (the clock, never rank), the rake cuts only at a record-certified
settle, and the verdict is certified by the ledger itself — the hunt is
the free door, the head a record not a scalp).


## 31. The Oracles (spitball #18, 2026-11-05) — the wish to wake, priced in shots

The owner's pitch, dressed in the world's law: the sealed keys are encrypted
from every hand — even the server holds only one-way derivations nobody can
read back (the ancients PRD, sec 7). But the WISH to wake an ancient is
enormous and patient — and it can lawfully help pay for the servers it
dreams on. TWO LANES, both answering one law: NOTHING PURCHASABLE OPENS A
WAKE-KEY — a wallet buys MORE DICE for the week, never the act and never a
stronger die; the clue, the honest search and the free path stand every
single account, always.

SEAT 1 — THE WISDOM CALL (delegated wisdom, the sidecar oracle). A Rust/
Julia sidecar under the standing sidecar plugin law: a bought batch of real
compute runs attested wake rolls against ONE named door's locked shape —
which ancient, how big, audited on the receipt. The sidecar NEVER prints a
hint or a coordinate; it reports only whether the batch's dice made a hit.
No price makes a single die better — the wallet buys dice-COUNT, not
dice-QUALITY — and weekly caps ride the QoS family, so no budget cracks the
door: the sealed shape is far bigger than any bought dice can sweep. PRICE
FELT: ~$0.25 per work unit (build-seat exact, owner's veto), each batch
priced to cover its own marginal compute so every bought wish pays its own
server shed honestly (the owner's "help pay for our servers hehe", signed).
New WISDOM sink rows on the audited catalog.

SEAT 2 — THE MEDITATION CEREMONY (the Sigil rite). The Lucky pot's shape
applied to waking: each account owns a weekly wake-tune pot of ceremonies —
days 1-2 of every week granted FREE via witnessed deeds (the owner's earn
rule), the rest bought at 25 sigils ~$1.25 (the charm's price shape, the
same potency whoever pays). A held ceremony day lifts the odds of the LUCK
lane's wake rolls for that 24 hours — the same odds every account's
ceremony carries; money buys the door to dice, never a better die. It
works ONLY where an ancient's wake-key includes a luck leg: riddles, tram
roads, watching and tablet rituals stay hands' work. ANTI-SMELL: no stat
anywhere (wake odds are luck-lane facts, never combat numbers), NO WIKI
(nothing prints how close a door is — rolls spent are yours, truths stay
the world's), provenance stamped EARNED/BOUGHT on every ceremony through
the tx roots. New ATTUNE sink rows (no-fake-sinks: the grant legs ship
with the rows).

IMPLEMENTATION SEAT (build round, gated on a first ancient): the sidecar
plugin adapter (a Rust/Julia batch runner over the sealed-shape attester),
the wake-luck rolls reading ONE shared roll bucket beside Sec 14's (never
per-item bandaids), the attestation receipts, both sink rows with their
grant legs, the weekly earned allotment (witnessed deeds) for both lanes,
the QoS cap book, and the meditation charm .tres. PRICING FELT: wisdom
work unit ~$0.25; ceremony 25 sigils ~$1.25; all build-seat numbers,
owner's veto reserved.

THE LAWS: nothing purchasable opens a wake-key, at any price (the Oracles
sell only the wider shot); compute pays its own compute (no subsidy, no
loss lane); no guarantee exists at any price; no combat stat ever; no
wiki for a door; no free text ever (wake banner lines print from service
record only); every roll provenance-stamped; the F2P earn path stands on
both seats.


## 32. The Wake Event (spitball #19, 2026-11-05) — the echo after the door turns

When ANY wake fires — sealed or carved, luck or ledger, ancient or hidden
verb — the world prints ONE ceremony, and the ceremony is where the money
lawfully lives.

THE FREE EVENT (never sold): a zone-visible rise — the islet lifting free
of its overgrowth, the ruin mover's first breath of dust, the hidden verb
unbinding at its ground — and the wake files as a WHISPER LEDGER CHAPTER
on the sky almanac rails (one derivation, two readers, the carrier law
verbatim). Every witness reads it free, forever.

THE FIRST WAKER: the wake RECORD names the first waker forever —
service-record credit, never custom text — and the record itself mints a
SUFFIX deed by construction ("the Dawner", the Spiteful's shape: titles
are minted by deeds only). NOBODY BUYS AN HONOR applies at its sharpest:
the suffix cannot be bought, gifted, reserved or traded, and a bought
peal never mints anything.

THE PAID LEG — THE WAKE PEAL: the standing Peal permit's SECOND VOICE
(the mourning SKU rung in celebration — one permit, two voices, no new
SKU, no new payment code; deed-earned or bought, never Charter-gated):
a bigger bell, a longer echo, and the finder's name carried in the
celebration line. Money buys the echo, never the event.

THE INVESTOR LEG (owned, verbatim, on purpose — "make investors know the
psy"): a PERMANENT LEDGER (first-waker names ride the wake record
forever — the ego stoked by a suffix minted by the record itself), an
EASY SPEND on a HAIR TRIGGER (the celebration permit bought at the
emotional peak, in the moment the story is made). Social proof
monetized without a single number shown to any onlooker.

LAWS: no stat anywhere (a wake is a ceremony, never a rating); no wiki;
no free text (every wake banner and ledger line authored from service
record only); provenance EARNED/BOUGHT on every ring through the tx
roots; the F2P floor is the WHOLE event — the rise, the ledger chapter
and the suffix are free by construction; the peal re-sells the same
permit the mourning seat already sells (tolls orthogonal, one SKU).

IMPLEMENTATION SEAT (build round, gated on the first wake): the wake
banner through the sec 15 print rails, the ledger-chapter leg on the
almanac derivation, the suffix mint condition reading the wake record,
and the Peal permit's celebration-voice binding (the existing .tres, a
second use-case; zero new payment code).


## 33. The Warrant Board (spitball #20, 2026-11-05) — bounties on mysteries, modeled on vant

The owner's TRIPLE YES, with the want behind it named plainly: "like old
school ultima online where you could bring back the head of the player
lol." The UO instinct is kept; the head is not. Synmergia has no combat,
so nothing here pays for a player's anything: the Board posts bounties
on MYSTERIES — a named ancient's claimed deeds, a creature's verified
passage, an oddity confirmed. The head always meant the PROOF of a
deed; at this Board the deed plate already keeps the proof. (Modeled on
dhaupin/vant: bin/escrow.js, bin/market.js, bin/forum.js and
bin/consensus.js were read section-by-section for this design.)

THE POST: a player files a warrant from TEMPLATE LINES ONLY (clauses
name a world fact the record can check — "first record of the drowned
pier's false light", "warrant on the road under the fog", "confirm the
islet orb's silent minute"), wraps a PURSE in sigils, and the purse is
ANNOUNCED into an escrow hold — the mix law tracks its quarters
through the hold exactly as everywhere else (deed-earned sigils stay
graded, bought sigils stay visible, nothing converts by sitting in a
hold). NOBODY MAY FILE A WARRANT NAMING A PLAYER: no heads, no scalps,
no enemy-facing anything — the file format has no player field to
abuse, and the census refuses the file. Free text, likewise, has no
field to land in.

THE CLAIM — HOLD, NEVER DEBIT (the vant escrow law, transplanted):
bin/escrow.js's own comment IS the mechanic: "a hold is a reservation
with a timeout - it does not debit budget." A hunter's claim is
exactly that: a RESERVATION AGAINST THE PURSE with a countdown,
referencing deed tx roots only, never prose. If the record confirms
the clauses inside the window, the claim settles; if the clock runs
out, the hold releases and NOTHING DEBITED anywhere.

THE SETTLE — THE RECORD IS THE JUDGE (vant's settle shape, minus the
buyer's discretion): in bin/market.js, settlement is confirm|refute by
the buyer. Here nobody judges a bounty with a whisper: SETTLE IS
DETERMINISTIC — a claim confirms when the deed tx roots match the
clauses, and nothing else gets a vote. Vant's propose→vote surface
(bin/consensus.js) is the one model the Board REFUSES on purpose: no
ballots, no votes, no social wire to argue over — the ledger is the
consensus. And vant's "delivery never blesses unverified bytes" rides
over intact: a claim is a POINTER into the record, and the record
decides what it means, never the claimant's story.

THE SWEEP (the vant skill-sweep precedent): a warrant unclaimed past
its own file clock releases by sweep — the purse returns WHOLE, no
rake, no penalty, no trust mark. Expiry is administrative, never
punitive.

THE MERIT LEDGER (vant's decision trail, forum-shaped): every settle
files a MERIT chapter — the warrant, the clauses, the purse, the claim
roots, the finder — a public, read-free surface with the deed plate's
law (template lines only). And the Board keeps vant's SHILL CENSUS:
the top claimant's share of settled purses prints beside the ledger —
a noticed pattern nobody can argue with, the one warning light that
works without a single word being spoken.

THE PAID LEGS (two, both small, both orthogonal):
- THE CRIER TOLL: money buys the CLOCK — a front-page feature buys
  DAYS in the Board's rotation, deletable and calendar-shaped, never
  rank, never a ceiling, never a better verdict. Handbills rotate the
  front page free; the clock only stretches one handbill's stay.
- THE HOUSE RAKE AT SETTLE: the Book's 10% shape applied to settled
  purses — the rake cuts at the moment value flows, on an outcome the
  record certified. An expired purse pays nothing (the sweep).

LAWS: the hunt is FREE and always was — reading, hunting, claiming and
the ledger all cost nothing per account (the F2P floor is the whole
service); no wiki (the Board is an agora of what HAS happened —
precedent, never a guide); provenance travels lawfully — the finder's
claim grades EARNED or BOUGHT through the tx roots like every purse;
money buys the clock and the rake share, never the act, never the
verdict, never the odds; sink kinds MERIT rows and CRIER rows ship
WITH the grant legs (no-fake-sinks).

IMPLEMENTATION SEAT (build round, gated on the first warrant): the
warrant ledger on the keyed account-ledger family (hold / timeout /
claim state, purse-mix tracked through the hold), the deterministic
verifier over deed tx roots, the sweep job, the front-page
derivation, the merit-chapter file, the census surface, and both sink
rows.
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
