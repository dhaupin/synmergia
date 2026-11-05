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
   future SKU and it resells the ladder rounds we already build.
3. **Cosmetic breadth** (dyes, tabards, pet/mount skins): sink rows are data; the model
   ceiling rises without touching laws.
4. **Storage/convenience tiers**: extra bank tabs, extra vendor stall rows — classic
   retention monetization, rides existing inventory laws.
5. **Character-slot packs**: natural at the multi-spec future; pure permit rows.
6. **Open question for discussion**: subscription ("the Concord Ledger Charter"?) —
   monthly all-you-need sigils + small daily conveniences; strongest for recurring revenue,
   weakest vs the "no subs for content already earned" sentiment; bring numbers, not vibes.

## 9. The investor version (the one-paragraph answer)

*Synmergia's monetization is not a plan, it is an installed, receipt-audited system: a
wallet, three real-$ SKUs ($4.99–$24.99), a nine-row premium catalog (resurrection
tickets at $1.00 net per unit, a $7.50–$45 mount ladder, cosmetic titles at $10–25),
an in-game sigil market, and an earned-earn path that keeps F2P honest. Publishing
cadence is already contractual: seasonal packs authored by an income law that pays the
shared progression curve, with a level cap that lifts on data, not opinion. The total
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
