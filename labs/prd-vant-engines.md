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

**THE TWO HOUSES** (the repo boundary — spitball #25, the owner's
ruling: "you made a shitload of vant, like you built it specifically.
You're the Buffy. You can and should use it here. Absolutely attrib,
MIT, self win. But otherwise vant <> synmergia (submit issues there if
you find stuff, extend, etc pls!)"):

1. **Build on it.** vant is family — much of it authored by the same
   hands — so Synmergia builds on it freely under MIT, attribution
   carried; the self-win is allowed to be cheap.
2. **Bugs travel upstream.** Anything the port or the Drivers turn up
   in vant's models is filed as an issue on `dhaupin/vant` (the read
   commits are the receipts); a defect never stays hidden in the
   derivative.
3. **Extensions travel upstream too.** Capabilities general enough to
   serve vant users beyond the game (deterministic settle, census
   patterns) are proposed on the vant side — the first one was filed
   the day this law landed (the port-review series: #333 settle contracts, #334 trust
   opt-out + settle-verifier seam, #335 publish-only trail +
   reconcile mode; #336 memory standing, #337 the economy seam, #338
   srv wire contract).
4. **Game logic never goes upstream.** Nothing in `dhaupin/vant`
   should ever learn that Synmergia exists as more than an issue
   number: beyond the share, vant <> synmergia — separate houses, one
   family, MIT in both directions.


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


## 4. The Drivers (the spine doctrine) — spitball #24

> **The owner's ruling:** "these vant imported systems should not just
> be the warrant board. These can drive many services across
> synmergia. These should take a high level to *drive* other services,
> just like vant." Buffy yay — and the block is hereby promoted from a
> library with tenants to THE SPINE.

**THE SPINE LAW.** The engines are not a library beside the services;
they DRIVE them. A money service never implements a hold, a settle, a
sweep or an audit book — it SUBSCRIBES: a short authored data manifest
(**the tenant sheet**) names the service's purses, its settle
clauses, its publication subset and its census feeds, and the engines
read the sheet and run the flow. Vant already runs this exact shape —
one shared escrow state, tools reading config; the port keeps it: one
shared engine state, many tenants, the sheet as the interface.

**THE TENANT SHEET** (the driver's shape — four fields, data never
logic):

- **PURSES** — denominations, pool caps, hold timeout, and the
  provenance/mix policy the Purse Engine tracks through each hold;
- **SETTLE** — the clause list the record must match (template
  fields, no free text) and the deterministic judge that reads them;
- **PUBLICATION** — which Agora chapter the flow prints and which
  census counters it feeds (read free everywhere, tool-side only);
- **QOS** — the impulse caps the flow rides (per account, per
  calendar, the standing QoS family).

**THE NO-WAIVER LAW.** The sheet cannot grant a law away: no field
exists that disables provenance stamping, return-whole sweeps,
no-penalty expiry, census observation or the deterministic judge. A
tenant needing a different law is a NEW SPITBALL, not a field.

**THE CHEAP MACHINE.** A future money spitball therefore lands as one
tenant sheet + its sink rows + its UI readers + its tests — build
rounds never fork engine code. The Warrant Board is tenant zero
(prd-monetization.md sec 33); the Glad Book, the guild vaults and
every tenant after them author the same four fields. This is how the
block "drives other services, just like vant": the flow stays the
engines'; the service only says what flows.
## 5. Scope and gates

- Every money service travels as a tenant sheet on the Drivers (sec 4); no service ever forks the engine code.
- THE TWO HOUSES (repo boundary): build on vant under MIT with
  attribution carried; port-found bugs and general-purpose
  capabilities travel upstream to `dhaupin/vant` as issues; game-
  specific logic never goes upstream.

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

## 6. The framework asks (the palette round) — spitball #27

> **The owner's ruling:** "tell vant what it needs to be, as a
> framework, so you can do those things it is not. Vant thrives on
> this stuff! Like vant is a palette, synmergia (or any other user)
> is the art. Submit vant issues, update prd-economy and the prd
> investors, and let's look further using those methodologies and
> systems."

**THE PALETTE LAW.** A palette must hold any brush that paints on it.
Vant is the palette; any downstream economy — Synmergia or any other
user — is the art, and the framework must be complete enough that the
art never has to fork the palette to finish the painting. What the
art asked for was filed upstream the day this landed (three
port-review notes; the series line in sec 1 grew the same day):

| Ask (the framework's missing organ) | Upstream | Why the art needs it |
|---|---|---|
| Credit-side ledger — the purse's other half (`lib/ledger.js`; the debit side is already disciplined; settlement.js's own header concedes the gap: "credit-side accounting is a deliberate non-goal for v1") | #337 (Port review 4) | a seller must always be able to answer what it has earned and what it holds |
| Market tape — read-only price discovery over realized settles (count, last-N, median, guardrails), tenant-gated on the #335 exportTrail shape | #337 | boards price from evidence they can re-derive, never word of mouth |
| Typed economy events — listing/hold/settlement life-cycle as subscribable types over the bus, durable where the bus persists | #337 | the tenant seam: subscribe, don't poll |
| World-shaped connector — `identities()` / `inventory()` / `txForward()` base contract (neither git-shaped nor compute-shaped) | #337 | a foreign world rides vant without becoming a code path or a hosted service |
| Memory as standing — a durable state class (no TTL decay touches standing), tombstone receipts on `forget()`, envelope co-authoring as a declared mode | #336 | standing must never decay silently and erasure must leave receipts |
| srv wire contract pinned as a supported interface (version marker on `/health`) | #338 | the rust/julia sidecars' uniform wire becomes a contract, not a coincidence, before future hot-path seats depend on it |

**THE RESIDUE LAW.** The palette never renders the art: every ask is
engine-generic (ledgers, tapes, buses, connector contracts, memory
classes), and the Two-Houses law holds — game logic never goes
upstream, and nothing in `dhaupin/vant` learns what the art painted.
The hygiene notes rode inside #337 (kernel-ledger.js is the docs-gates
witness for kernel.js, not a money ledger — the name misleads every
integrator; connectors/index.js's qdrant()/weaviate() factories ship
but throw at call; settlement.js's MAX_PRICE is a hard constant that
should parameterize).

**GATES:** no engine change in this PRD, no Concord row, no SKU; the
asks land as upstream code (the palette's own files), and the
Synmergia side inherits them as consumer laws through the tenant
sheets (prd-economy.md sec 8) when the palette ships them — the
framework thrives exactly as the owner said it does.
