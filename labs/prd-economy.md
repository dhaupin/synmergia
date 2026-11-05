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
- The investor tie-back is DEFERRED by the owner's order: when it
  lands, the stool's Legs 2 and 3 (tailwind and cadence) absorb the
  loop paragraphs and the breath-chart evidence — one text, one
  landing, no investor doc touched this round.
- Build-round tests ride the standing isolation discipline
  (two-account isolation, foreign-origin 403s, hold-expiry proven
  no-debit, self-signing-twice refusal) plus the loop tests: a
  minted unit provenance-complete end to end, a warrant purse proven
  payer-posted → hunter-held → record-settled → raked → melted, and
  a sigil proven un-transferable between accounts.
