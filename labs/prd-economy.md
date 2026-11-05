# The Living Economy — spitball #23 (2026-11-05)

> **Status:** DESIGN (pre-implementation; doc canon only — this PRD adds
> no SKU, no sink row, no server change). Inspiration shelf: `labs/prd-
> monetization.md` (the Concord's Table, twenty-four priced rows) and
> `labs/prd-vant-engines.md` (the Engine Block). This PRD loses on any
> disagreement with the anti-smell tenets; it exists to bind them into
> a loop.

> **Purpose:** the owner's ruling: "we should actually build it. We can
> segway into prd-economy, leveraging these systems, defining how they
> create a living breathing system. We can circle back to investor docs
> and tie it back after." This is the system document: it prices
> NOTHING — it defines WHAT the money does between the Concord's
> twenty-four rows and the four engines — the mint, the moves, the
> melts, and who breathes the oxygen behind all of it. Investor
> tie-back lands in a later round on the owner's schedule.

## 1. What the economy is

The economy is a LOOP, not a shop. A dollar enters once (the
storefront), then it lives: it posts purses, buys wagers, pads runner
industries, fills pub evenings — passes through player hands — and
finally melts into the audited sinks. A wallet that melts instantly is
a vending machine; a wallet that circulates is a world. THE BREATHING
LAW: money's first stop after the storefront should be PLAYER EFFORT
wherever a lawful lane exists — purses to hunters, wagers backing
bouts, blanks bought from runners, crowds gathered in held rooms —
and the census watches the whole loop from the wardens' observatory,
never printed at players.

## 2. The three motions

**MINT — the one door.** Sigils mint at exactly one door: the
storefront SKU (webhook seam), stamped bought by the purse law at
birth. Gold mints ONLY from the world's verb pay tables (drops, deeds,
witnessed work) — never an admin grant, never a rescue mint. Every
minted unit carries its provenance from its first tx root; nothing is
ever minted free of the stamp.

**MOVE — between players, engines only.** Player-to-player money
moves through exactly these lanes: (a) the trade window (TradeService:
items and gold — the waystone runner industry, crafted furniture, dyes
and field kits ride here), (b) engine holds — warrant purses, the
Glad Book's gold wagers, the Steward's Pledge escrow, guild vault
flows — where the Purse Engine holds the money through a countdown,
and (c) earned allotments the world itself grants (witnessed deeds).
THE FIREWALL LAW: sigils never move between accounts — a bought sigil
and a deed sigil stay mixed exactly as the purse law stamped them, no
trade window, no gifting, no site can ever clear outside real money —
the RMT rail closes at the provenance stamp, so the claimant's purse
earn and the seeker's wager are the only rich veins, and both are
audited.

**MELT — the sinks.** Every melt rides an audited sink row beside the
roll board (the no-fake-sinks law verbatim: a row ships with its grant
leg or it does not land). Two sink families already price in canon:
GOLD sinks (the house ankh, the homestead deed move, civic bills, the
Book's rake) and SIGIL sinks (the Soulbinder ticket, Lucky pot days,
dye/locker/heraldry kits, the Pub clock, the Belfry, the Crier, the
Wisdom batches). THE MULTIPLICATION LAW (the runner pattern verbatim):
a sink that consumes and regrows (waystone charges, mender's kit
consumables, dye after dye, wager after wager) multiplies the melt;
each repeat pulls from the world's own suppliers, so the melt feeds
back through OTHER players before it feeds the wall.

## 3. The engines carry every motion

| Motion | Purse Engine | Settle Engine | Agora Engine | Ledger Quorum |
|---|---|---|---|---|
| MINT | holds nothing; stamps provenance at birth | never | printable (the receipt) | root attest |
| MOVE | holds purses, wagers, pledges, recoveries | settles by record, refuses what is not in the clause | prints the receipt (book odds, merit chapters) | cross-shard root agreement |
| MELT | caps the sinks (limits, never unlocks) | certifies the debit moment | prints the melt line when lawful | attests the audit trail |

Nothing moves that the engines did not hold, settle and attest; a
money surface that walks beside the engines does not exist in Synmergia.
Every future service reaches them through a TENANT SHEET on the
Drivers (prd-vant-engines.md sec 4): no service ever implements its
own hold, settle or sweep, and no sheet can waive a law.

## 4. The flywheel

The gas is the payer's spend: the hunter's purse, the runner's blank
industry, the Book's felt odds, the pub's crowd and clock, the sponsor
shard-wide stage, the wake celebrations. The payer's dollars fund the
F2P effort DIRECTLY — first-waker glory costs nothing, claimed purses
pay the hunter's mix (provenance: as posted), the Book's winner takes
the pool minus the authored rake, and the sinks eat everything
eventually. The F2P player is NEVER a serf class: he earns through the
same rows the payer melts into, and the census's only permitted
observation — the shill concentration pattern — stays tool-side
forever, a noticed pattern, never a punishment.

## 5. Invariants (what this economy will never do)

1. no combat stat by purchase; the money BUYS THE CLOCK, NEVER THE
   CEILING (the standing tenet, the Concord's read law verbatim);
2. NOBODY BUYS AN HONOR: prefixes, first-waker names and deed-minted
   titles stay deed-only forever;
3. no free text anywhere in any money lane (template clauses;
   authored lines; the moderation surface is a switch, not a forum);
4. the tolls orthogonal law holds row by row: no purchase ever stacks
   a different family's felt toll;
5. holds never debit — expiry returns WHOLE, no penalty row exists
   anywhere in the Purse and Settle engines;
6. sinks are audited, visible and capped (each price authored, the
   QoS family caps impulse lanes per account per calendar);
7. the census publishes the PATTERN, never the person, wardens-side
   only — the stake is the balance, never the blame;
8. tuning melts at build rounds against the census evidence, never
   live-throttled mid-flight (stability is authored, not improvised).

## 6. The pulse (the wardens' observatory)

The economy's health is read, never squeezed: a breath chart (daily
mint/move/melt in both denominations, dated anchors), the sink-alive
board (a row with no debits for a full week reads DYING — a retune
audit item, never a live change), the purse concentration pattern
(the shill census tool-side), and the faucet/sink ledger (mints
against melts, per calendar week). All of it exists so the NEXT
spitball is priced into a loop whose temperature is known —
evidence for the investor tie-back when it lands.

## 7. Scope and gates

- This PRD adds NO Concord row and NO SKU: it binds the twenty-four
  priced rows into a loop and rides the Engine Block's migration
  order (Purse first, then Settle, then Agora, then Quorum); no row
  lands before its engine, and no engine lands without the census
  seat beside it.
- THE APESHIT BATCH (spitball #26) is the loop's first children
  beyond tenant zero: the Guild Contract Board (prd-monetization.md
  sec 34), the Kindling (sec 35) and the Runner's Exchange (sec 36) —
  every one a tenant sheet on the Drivers, mint/move/melt riding the
  same engines,
  the Concord count reached TWENTY-SEVEN at the batch
  and TWENTY-EIGHT after the plates (row 28, the Boom — spitball #28).
- The investor tie-back LANDED (owner order, spitball #27): the
  stool's Legs 2 and 3 absorbed the loop paragraphs and the
  breath-chart evidence, and the Palette leg (the platform answer)
  was authored beside them — one text, in prd-monetization.md sec 28.
- Build-round tests ride the standing isolation discipline
  (two-account isolation, foreign-origin 403s, hold-expiry proven
  no-debit, self-signing-twice refusal) plus the loop tests: a
  minted unit provenance-complete end to end, a warrant purse proven
  payer-posted → hunter-held → record-settled → raked → melted, and
  a sigil proven un-transferable between accounts.

## 8. The dogfood mirrors — the palette painted downstream (spitball #27)

> **Status:** the owner's ruling: "Synmergia + vant = dogfooding
> humans/agents into our own ecosystem, alignment, no friction...
> vant is a palette, synmergia (or any other user) is the art." This
> section is the economy's side of the Dogfood Loop
> (prd-monetization.md sec 37): three laws the loop binds onto every
> future tenant sheet, and no price in them.

**THE TAPE RULE (no open pricing).** No player-facing or agent-facing
board quotes a price from anywhere but a machine-readable TAPE over
realized settles — count, last-N realized prices, median with count
guardrails, tenant-gated (the census's standing shape: publish the
pattern, never the person). A money surface may quote the tape or
refuse to quote; it may never quote opinion, hearsay or a
screenshot. The Crier rows and every future price display on the
boards ride this rule from birth.

**THE MEMORY LAW (standing is durable).** Standing — deeds, purse-mix
traced through holds, warrant retirements, guild memory — lives as
DURABLE state: no TTL decay touches a standing fact, because standing
that decays on a timer is a bug and standing that is erased silently
is theft. Multi-writer guild memory rides the ENVELOPE shape
(revision + writers, conflicts flagged for later readers, never
silently merged), and a forget is a tombstone with a RECEIPT, never
silence. The census reads the pattern and prints neither the person
nor the purge.

**THE SPECIES-BLIND LAW.** The pulse (sec 6) counts one population:
agents and humans mint, move and melt into the same instruments, and
no read anywhere distinguishes them — no species field, no "bot
sink", no machine-rate printer. Alignment is the absence of a special
case.

**GATES:** no Concord row, no SKU, no engine change — these are
economy laws riding the tenant sheets (prd-vant-engines.md sec 4),
and the framework machinery that can power them (the credit-side
ledger, the market tape, memory standing) travels upstream as the
palette asks, dhaupin/vant #336–#338 (the Two-Houses law: the art
never forks the palette to finish the painting).

## 9. The plate economy — player-run channels (spitball #28)

> **Status:** the owner's gravity: "player-run channels are ripe for
> boosting or promoting, easy Sigil eater, consistent." This is the
> loop of sections 1–4 applied to the channels:
> prd-monetization.md sec 38's five plates read through
> mint / move / melt.

**THE MELT SHAPE.** The Boom is the plates' recurring sink: front-page
days ride BOOST rows and eat sigils consistently — and the melt
multiplies exactly like the runner industry: a boosted storefront
makes sales, the sales refuel the next boost; a boosted auction fills
the hall, the hall fills the next lot's boost; a boosted event draws
the crowd, the crowd funds the next schedule. THE MULTIPLICATION LAW
verbatim: a sink that consumes and regrows feeds back through OTHER
players before it feeds the wall — boosted presence sells other
players' goods, and the goods' sales fund more boosts.

**THE MOVE SHAPE.** Player-to-player money on the plates rides
exactly the standing lanes: the trade window's gold lane (storefront
rows), single-claimant holds on the Purse (auction lots), engine-settled
rakes at settle. SIGILS NEVER MOVE (the firewall verbatim): the Boom
eats sigils TO the sink — never across a counterparty.

**THE PARTY POD (the mesh/pod letter's economy).** Vant's
certified-letter posture (lib/carriers.js, pass 259) routes work
through stations under CHECK / RISK / AUDIT, and the party question is
upstream-alive (dhaupin/vant #341 sec 3): a stage may ride HELD BY A
POD (a peer set) while WHO acted stays individual. The economy reads
the same shape: a party pod is one hold family on the Purse (the
stewardship escrow's multi-claimant shape), the RISK lane of every
privileged hop is the single-use approval burn (#337's economy hooks
point at the same station record), and a pod that earns a route's
purse splits it by the route's template — deterministic, census-counted,
species-blind. An agent party here is the same object an industrial
party is upstream: similar systems, familiar architecture, one
economy underneath.

**THE TAPE RULE HOLDS PLATE-WIDE (sec 8).** A storefront quoting
prices quotes the tape — evidence over realized settles, nothing
else; no plate ever quotes opinion, hearsay or a screenshot. The
feature windows ride the same census discipline (feature-frequency
counters live tool-side forever: a noticed pattern, never a
punishment, never a printed leaderboard of boosts).

**THE MEMORY LAW HOLDS PLATE-WIDE (sec 8).** A plate's retirement is
a tombstone with a receipt: an expired auction lot, a closed
storefront, a past event's chapter keep their residue — standing is
never erased silently. Guild boards ride the envelope shape for
multi-writer contest (revision + writers, conflicts flagged, never
merged away).

**GATES:** no Concord row beyond the Boom itself, no SKU, no engine
change — the plates ride the Drivers as tenant sheets
(prd-vant-engines.md sec 4); the general plate/channel and boost
primitives travel upstream (dhaupin/vant #339/#340) and the game owns
only its templates (the Two-Houses line); everything on every plate
is free by construction except display time.
