# PRD: The Ward Gate - the hard gate registry and the breach embargo

> **Status:** SHIPPED (as built 2026-10-06)
> **Law:** `labs/prd-psy.md` (no religion anywhere in this doc), locked
> decisions in `AGENTS.md`, the riding layer in `labs/prd-mounts.md`
> (the Skywarden is the key), role truth in
> `game/core/schemas/character_class.gd` (`Role.GM = 0`, "Reserved.
> Never via .tres. Admin-only, guarded at login").
> **Naming:** gates are `gate_` prefixed data ids in `data/gates/`,
> filename == id; the service is `WardGateService`; the embargo ledger
> lives under `ward_gate/embargo/` in the DictStore.

## 1. The Owner Vision (2026-10-06)

"Ah that's a crutial part of the puzzle to solve! If species 0 gm AND
holds mount_gm_skywarden it opens gates and stuff. We should make a
tres or inventory for max Gms, skywardens, or other admin things. Hard
gate, defense in depth. You could also put items here in a breach,
like if they figured out how to dupe ores, you could drop ores in this
gate to temporarily prevent their drops or dupes."

So: the Skywarden is not a reward, it is a CAPABILITY TOKEN. The admin
keys live in one registry, the gate opens only when every signal
matches, and the same registry doubles as the breach kill switch.

## 2. The Law: Defense in Depth

1. **Every key signal must match.** A gate opens only when the role
   truth AND every token mount AND every token item all verify. The
   absence of any one signal keeps it closed.
2. **Fail-closed is the posture.** An unknown rider is a closed gate.
   An unknown gate id is closed. A missing InventoryService lookup is
   closed. No signal is treated as a pass anywhere in the chain.
3. **Role truth is server-side.** The role resolves from the
   character's class through `CharacterData.is_gm_class` (the repo's
   one class-truth path), from the service's OWN session book -- kept
   independent of RideService's (two books, same hook: if one is ever
   poisoned, the other still gates). Client claims never open gates.
4. **The mount token is independently verified.** The Skywarden cannot
   be granted to a non-warden (the GM source door in RideService is
   fail-closed), so its presence in the ownership ledger is a second,
   separately-verified signal -- exactly the depth the owner asked
   for: role 0 gm AND holds mount_gm_skywarden.

## 3. The Registry (`data/gates/`, `gate_` prefix, filename == id)

`WardGateData` fields: `key_role` (the reserved GM role, 0),
`key_mounts` (the token mounts -- the Skywarden), `key_items` (the
token items), `opens` (labels of what the gate unlocks -- admin shell
tiers, warden tools, future multiworld gates), `embargoed_items` (the
standing breach list), `embargo_reason`.

Shipped: `gate_warden_keys` -- "The Wardens' Keyring": role 0 + the
Skywarden, opens `admin_shell` and `warden_tools`, embargo SHIPS EMPTY
(a breach is an edit or an API call, never shipped data). More gates
are one .tres away: a lesser warden gate with a subset of keys, a
future moon gate, whatever the world needs gated.

## 4. The Breach Embargo

Two layers, one check:

- **Standing** (`embargoed_items` in the .tres): for bans that should
  survive reboots by data, not by ledger.
- **Temporary** (`WardGateService.embargo_item(item_id, reason, by,
  duration_s)`): the runtime ledger row (DictStore,
  `ward_gate/embargo/<item_id>`) with reason, author, and an optional
  expiry. Expired rows erase themselves on read -- "temporarily" is a
  real contract. `lift_embargo` clears one by hand when the breach is
  handled. Both notify `ADMIN_ALERT` / log loudly; reasons are admin
  truth, never shown to players.

The bite: `LootService` asks `allow_drop(item_id)` at CREATION (the
rolled drop never materializes) and again at PICKUP (pending loot dies
at the gate, loudly logged). The duped ore stops existing as a drop
the moment it enters the gate -- no restart, no deploy.

## 5. As Built (2026-10-06)

- `game/core/schemas/ward_gate_data.gd` -- NEW schema.
- `game/core/services/ward_gate_service.gd` -- NEW autoload (registered
  after RideService). `can_open` / `gate_open_for` (public per-gate
  verdict so probes need no test-only data), `embargo_item` /
  `lift_embargo` / `is_embargoed` / `allow_drop` / `embargoed_items`.
- `game/core/services/data_service.gd` -- `load_gates`, `get_gate`,
  `get_all_gates` (the generic directory scan, one line per category
  as always).
- `game/core/services/loot_service.gd` -- `_filter_embargoed` wired at
  creation, container creation, and pickup.
- `game/data/gates/gate_warden_keys.tres` -- the keyring registry.
- `game/tests/probe_ward_gate.gd` -- NEW, 31 checks, in the runner
  DEFAULT_SET: registry law, every defense-in-depth leg (unknown
  closed, non-warden closed, warden open, revoke-closes, item leg
  fail-closed), the full embargo cycle (persist, live list, self-
  erasing expiry, lift, lift-twice no-op), and the loot seam end to
  end (embargoed ore filtered from a drop, fully-embargoed drop spawns
  nothing, lift restores the flow).
- `game/tests/test_data_naming_lint.gd` -- the `gate_` category joined
  the prefixed-styles audit.

## 6. Where Gates Plug In

Callers ask `WardGateService.can_open(player_id, gate_id)` and act on
the gate's `opens` labels. The checks are in place before there are
doors to open: admin shell tiers, warden tools, and the multiworld
Moon Gate (prd-multiworld) can each demand the keyring without new
plumbing. The item token leg upgrades automatically when
InventoryService grows a player-level lookup -- the gate's lookup is
defensive by design.
