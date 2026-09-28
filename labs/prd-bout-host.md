# S12 - Bout Host (the instant-gratification keystone)

> Companion to prd-spherical-mvp.md (S9-S11 built the parts; this
> closes the loop). Owner framing: 3 systems + lobby + gliding grew
> large -- S12 is the consolidation: what exists gets a RUNTIME.

## Status quo (2026-09-28)

**UPDATE, same day: BoutHostService SHIPPED.** The golden path runs:
stone enqueue -> assembly -> hosted room with linked fighters ->
host start -> bridge power normalization -> CombatSystem kill ->
payout (PlayerManager ledger) -> return home to the stones -> stats
restored. probe_bout_host 21/21, in DEFAULT_SET (regression guards
the WHOLE loop now). bout_assembled grew a 5th arg (per-player
origin stones). Next open item: the trial-bout fallback below.

Original survey (parts existed, nothing assembled them):

- Queue/assembly: LobbyService (party blocks, bands, fill consent)
- Front door: InstanceService join paths (capacity/contract)
- Rooms: arena_instance.gd (bout controller, scatter, AFK, returns)
- Combat: ArenaCombatBridge (deaths, shield rule, power normalize)
- Movement: BoutTeleportService (assembly in, returns home)
- UI: LobbyUI (Bouts/Duels/LFG) + queue stones (queue_mode gateways)

## The keystone: BoutHostService

The runtime that hosts a bout when assembly fires. One service:

1. **On bout_assembled**: spawn the ArenaInstance room for the zone,
   seat every participant as a fighter (entity_id = fighter_id, team
   from the assembly), remember the host book (zone, participants,
   start deadline).
2. **Start**: after the zone's entry deadline (Contract
   entry_deadline), start_bout -- LOCKED, no more entrants.
3. **Teardown**: on bout_ended -> payout -> release the roster ->
   destroy the room. BoutTeleportService handles both ends of
   movement; it only ever needed a real room to exist.

## Owner clarifier (locked, 2026-09-28): fighters are the players

Players use their OWN class, gear, build, and stats in bouts. No
"duel set" loaner forms, no equipment swap, no class change. The
instance is a place, not a costume: what you fought your way to is
what you fight with. Power normalization (S11 decision 5, capped at
ratio 2) remains the ONLY stat touch inside a bout, and it is
bout-local with snapshot/restore. Linked-fighter implementation must
respect this: bind the player's live entity/combat to the seat --
never instantiate a separate loadout.

## Linked fighters

Real players ARE the fighters (no dummy bodies for humans):

- The seat binds the player's live entity/combat: CombatSystem events
  route by entity_id (the bridge already does); the room's fighter
  book uses the same id.
- Movement identity: BoutTeleportService teleports the player node;
  the room's fighter body is the physics representation during the
  bout (scene flow item where both must render; position stays
  authoritative).
- Deaths/shields/activity: entity_id-keyed, already entity-shaped.

## Payout (hook, then depth later)

First pass, honest bookkeeping via the duck-typed progression surface
(Entity.add_experience / PlayerManager.add_experience + add_gold):

- WINNERS: XP + gold on bout end (zone-scaled base; scale with
  kill_target/roster later).
- LOSERS: consolation XP (never zero -- queue again is the loop).
- Depth later: per-kill credit via CombatSystem attribution, first
 bout title wiring (TitleService), streaks, wagered duels.

## Trial bout fallback (the retention keystone for low population)

An empty-queue hour gives a new player nothing -- a queue of one
never assembles. Classic fix: **the marshal's trial bout**. First
stone touch ALWAYS ends in a fight, and the fight teaches the mode.

- Trigger: queue aging past a patience window (default 45 s) with no
  band-compatible partner, or a zone-level opt-in on first queue.
- Host fabricates a filler opponent block (training dummy fighters,
  team 1) and assembles 1 v N by the zone's shape.
- Dummies are room-fighter bodies, entity-free: the bridge routes
  only real entities; dummy deaths resolve through the room's own
  accounting. Never count as real players in any ledger.
- Reward = the same payout path (reduced), so the lesson pays.
- Cheap once BoutHostService exists: the host just fabricates the
  block. Parked until the keystone lands -- flagged here because it
  is the actual retention answer at low population.

**UPDATE, same day: the trial bout SHIPPED.** LobbyService ages
queue blocks (TRIAL_PATIENCE_SECONDS 45, swept on the 5 s timer) and
emits trial_fallback_due(zone, block); BoutHostService fabricates
TWO marshal's dummies (trial_health 45, entity-free, bridge resolves
their deaths from real entity damage via effective_health), hosts
the trial (AFK sweep exempt, 4 s fast start, queued origin stone
honored), pays reduced (40 XP + 10 gold win / 15 XP loss) and
credits the win into the quest and achievement hooks:
- quest_arena_trial "Prove Yourself" (data/quests): KILL "marshal's
  dummies" x1, elder-gated lvl 1-8 -- the first fight IS a quest.
- achievement_trial_by_fire "Trial by Fire": target_type bout_win,
  credited via AchievementService.track on every trial win.
probe_trial_bout 26/26 in DEFAULT_SET (regression 32/32).

## Golden-path probe (regression guard for the whole loop)

One probe driving two fake players through the REAL chain: stone
enqueue -> LobbyService assembly -> BoutHostService room + linked
fighters -> CombatSystem-routed kill -> bout end -> payout -> return
map home. The regression suite then guards the entire loop, not just
its parts. Runs in DEFAULT_SET.

## Explicitly parked (do not lose track)

- Real glider mechanic (deploy/stow, thermals, stamina, open world)
- ROYALE bounds-shrink pacing + win condition
- Visual scene swap (players render inside bout rooms)
- More town stones; per-zone glide profile overrides; drop AI
- Payout depth (per-kill credit, titles, streaks, wagers)
