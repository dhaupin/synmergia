# The Engine Block (the vant port) — spitball #22 (2026-11-05)

> **Status:** DESIGN (pre-implementation; doc canon only — zero engine
> code exists today). Inspiration shelf: `dhaupin/vant` (MIT, 2026) at
> the commit the port reviews were read — `bin/escrow.js`,
> `bin/market.js`, `bin/forum.js`, `bin/consensus.js`, `lib/escrow.js`.
> Vant loses on any disagreement with Synmergia law; this PRD is canon.

> **Purpose:** the owner's ruling: "these vant services are more than
> bounty. They drive entire engines. The easiest thing to do would just
> build an adapter to vant to power it (like the game brain), but we
> should probably port it to Synmergia (internal)." This PRD is the
> landing: the four vant engines are PORTED INSIDE Synmergia's Rust
> service family — the Warrant Board (prd-monetization.md sec 33) is
> their first tenant, and every money surface in the Concord's Table is
> queued behind it.

## 1. The port, not the adapter

The adapter was priced and REFUSED, on one ground: **authority**. An
adapter outsources settlement and escrow truth to a process Synmergia
does not own — a "game brain" keyed to vant's brain registry, sandbox
capabilities and workspace tenancy. The world's own law is that the
ledger is the consensus and the deed plate reads server truth; an
engine that could be asked from outside the shard to bless, release or
settle a purse is an authority seam the chartered table cannot afford.
(Vant's agent tooling keeps running vant's business — the MODELS come
over; the keys, brain configs and capability grants never do.)

The port lives under the standing sidecar plugin law (the Oracles'
home, prd-monetization.md sec 31): Rust services beside the shard
process, audited receipts, no client-visible state. Attribution rides
with the port: vant's MIT line is carried in each engine source header
(the port is a derivative of `dhaupin/vant` at its read commit).

## 2. The four engines

Each is a port with a job — not a bundle of features. What is ported is
the MECHANIC; what is stripped is named per engine in section 3.

**The Purse Engine (escrow port).** One shared holds/pools/caps ledger
family that every money surface rides. From vant: holds are
reservations WITH TIMEOUTS, never debits (a past-timeout hold reads
dead and is swept); release deletes the disk row; releases are
persisted exactly as spends are; approvals follow the two-independent-
signer discipline ("self-signing twice never releases"); a circuit
breaker and runaway-spend guard sit on the write path. Tenants: every
toll family in the sink rows, the homestead signature tolls, guild
vault draws, the Glad and Grudge purses, the Steward's Pledge escrow,
and the Warrant Board's announced purses. Pool caps match the tolls-
orthogonal law verbatim: a cap limits, never unlocks.

**The Settle Engine (market port).** The delivery-confirmed settle
semantics become the standing settle law for every purse flow: a
settle debits at a record-certified moment (the Warrant Board's
deterministic clause-match is its first shape), a refusal or sweep
releases the hold with NO debit and no penalty, and the sweep job
family releases every expired hold on its own schedule. Vant's
reputation machinery stays TOOL-SIDE forever: the shill census is a
wardens' observatory row, never anything printed at players.

**The Agora Engine (forum port).** The publication layer for every
ledger chapter — the Whisper Ledger's wake chapters, the Warrant
Board's merit chapters, the deed plate's walk — one derivation, two
readers (the carrier law verbatim): the server derives, the
publication surface reads. Template lines only, no free text, no
replies, no direct messaging, no fee-present bodies. Read is free
everywhere; tenancy maps to the Charter's standing gates, not to vant
workspaces.

**The Ledger Quorum (consensus port).** Vant's propose→vote surface
ships as NOTHING — no ballots, no votes, no social wire anywhere in
any engine; the ledger is the consensus. What the quorum name covers
instead is the deterministic agreement over transaction roots the
shard mesh already needs (prd-shard-mesh rails): cross-shard audited
books compare roots, never opinions, and a root that does not agree
is a receipt problem, not a referendum.

## 3. Stripped at the door (the anti-dependency law)

From the port, vant brings nothing of: the brain registry, sandbox
capability grants, workspace tenancy, trust feeds printed at players,
direct messages, votes, or any surface that lets a paying wallet ask an
engine to change an outcome. Every stripped concept has a Synmergia
law standing behind it (no free text, no social engineering, the
ledger is the consensus); if a build round finds itself porting one
back, the round is wrong.

## 4. Scope and gates

- THE LOOP the engines carry is prd-economy.md, the Living Economy (spitball #23): mint / move / melt through exactly these lanes, the census as pulse; investor tie-back deferred by the owner.
- Migration order is Purse Engine first (every new sink lands on it),
  then the Settle Engine's sweep semantics, then the Agora
  publication, then the Ledger Quorum. The Warrant Board's
  implementation seat (prd-monetization.md sec 33) builds ON the
  Purse and Settle engines — it is implementation-gated on them, and
  they are gated on the first warrant.
- The port adds NO row to the Concord's Table: it rebuilds the rails
  under the twenty-four priced seats; no SKU, no price, no felt cost
  changes.
- Build-round tests ride the standing isolation discipline:
  two-account data isolation, foreign-origin 403s on the publication
  surface, hold-expiry sweeps proven with no debit, and the
  self-signing-twice refusal proven on the approvals path.
