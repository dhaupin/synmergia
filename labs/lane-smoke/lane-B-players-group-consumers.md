# Lane B - "players" group consumer audit (globe body safety)

Branch: `openhands/a9c64a14-1802-41cd-b7f9-c0f99c3c7ffd` (based on `staging`).
Change under audit: `game/entities/globe_player.gd` `_ready` now calls
`add_to_group("players")` (line 488), so the spherical body (the world the
player actually plays, `globe_world`) is now a member of the `"players"`
group alongside the planar `PlayerController` (`player_controller.gd:452`).

Task: audit every consumer of the `"players"` group and decide whether each
is safe when it resolves a **globe body** (`GlobeWorldPlayer`,
`game/entities/globe_player.gd`) instead of a planar `PlayerController`
(`game/entities/player/player_controller.gd`).

No `game/` code was changed. Findings only.

---

## Census of "players" group consumers

Exhaustive grep over `game/` (`--include=*.gd`) for
`get_first_node_in_group("players")`, `get_nodes_in_group("players")`,
`is_in_group("players")`, `call_group("players")`, `add_to_group("players")`.

**Production code (3):**

| # | file:line | member used on the resolved node | globe body HAS it? | verdict |
|---|-----------|----------------------------------|--------------------|---------|
| 1 | `game/ui/components/action_bar.gd:431` | `has_method("use_skill")` then `use_skill(slot_index)` | **No** (`use_skill` absent from `globe_player.gd`) | SAFE (guarded) - functional no-op |
| 2 | `game/scenes/world_playable.gd:576` | `"character_class" in player`, `player.entity_id`, `player.add_child(mark)`, `player.character_class` | **No** (`character_class` absent) | SAFE (guarded) - skipped |
| 3 | `game/core/services/player_progress.gd:294` | node returned to `save_player()` (duck-typed) | `entity_id` YES; `experience`/`gold`/`level` **No** | **UNSAFE (latent) - see TOP RISK** |

**Test code (3, non-production):**

| # | file:line | member used | globe body HAS it? | verdict |
|---|-----------|-------------|--------------------|---------|
| 4 | `game/tests/test_respawn_live.gd:144` | `take_damage`, `health_component`, `get("_pending_respawn_mode_int")`, `entity_id`, `global_position` | `take_damage`/`health_component`/`entity_id`/`global_position` YES; `_pending_respawn_mode_int` No | test-only; guarded fallback (`Player` node preferred) |
| 5 | `game/tests/test_loot_tables_live.gd:261` | `"gold" in _player` (guarded), `global_position`, `take_damage`, `entity_id` | `gold` No (guarded); rest YES | test-only; guarded fallback |
| 6 | `game/tests/test_globe_player_players_group.gd:73,76,84` | `is_in_group("players")`, `get_first_node_in_group("players")` | YES (this is the receipt) | intended |

Group writers: `globe_player.gd:488`, `player_controller.gd:452`. No
`call_group("players", ...)` anywhere. The `"players"` *string* also appears
in many unrelated dict keys (`zone_manager`, `instance_service`, ...) - those
are not group lookups.

---

## Per-consumer detail

### 1. `game/ui/components/action_bar.gd:431` - SAFE

```
431  var player = get_tree().get_first_node_in_group("players")
432  if player != null and player.has_method("use_skill"):
433      player.use_skill(slot_index)
```

- **Member used:** `has_method("use_skill")`, `use_skill(slot_index)`.
- **Globe body has it?** No. `grep -n 'func use_skill' game/entities/globe_player.gd`
  returns nothing; the globe body has no skill/cast surface at all.
- **Risk if absent:** none (crash-free). The `has_method` guard short-circuits,
  so the call is skipped. Behaviour is identical to the pre-change world where
  the lookup returned `null`.
- **Note:** the `globe_player.gd` comment (lines 483-486) cites ActionBar as a
  reason for joining the group, but joining does **not** make abilities cast -
  the body lacks `use_skill`, so the skillbar still silently no-ops in globe
  mode. Membership fixed the lookup, not the capability. Flagged, not a crash.

### 2. `game/scenes/world_playable.gd:576` - SAFE

```
576  for player in get_tree().get_nodes_in_group("players"):
577      if not is_instance_valid(player) or not ("character_class" in player):
578          continue
...
583      mark.set_wearer(str(player.character_class), player)
```

- **Member used:** `is_instance_valid`, `"character_class" in player`,
  `player.get_node_or_null(...)`, `player.add_child(...)`, `player.character_class`.
- **Globe body has it?** `character_class` No (`grep -c` = 0).
- **Risk if absent:** none. The `not ("character_class" in player)` guard
  `continue`s past a globe body. `world_playable` is also the *planar* scene, so
  a globe body would not normally be in this tree at all - defence in depth.
- **Risk:** none (crash-free, correctly skipped).

### 3. `game/core/services/player_progress.gd:294` - TOP RISK (unsafe, latent)

```
287  func _find_tracked_player(character_id: String) -> Node:
288      if EntityService and EntityService.has_method("get_entity"):
289          var found = EntityService.get_entity(character_id)
290          if found != null and is_instance_valid(found):
291              return found
292      if get_tree() == null:
293          return null
294      return get_tree().get_first_node_in_group("players")
```

Caller (autosave tick):

```
71   for character_id in _last_saved.keys():
72       var player: Node = _find_tracked_player(character_id)
73       if player != null:
74           save_player(player, "autosave")
```

- **Member used:** the node is passed straight to `save_player()`.
- **Globe body has it?**
  - `entity_id`: YES (`globe_player.gd:43`), non-empty (globe_world stamps it).
  - `experience` / `gold` / `level`: **No** (grep 0 / comment-only).
  - is a `Node3D` inside the tree: YES.
- **Crash risk:** none. `save_player` duck-types every field:

  ```
  115  if not ("entity_id" in player) or str(player.entity_id) == "":
  116      return false
  121  "experience": int(player.experience) if "experience" in player else 0,
  122  "gold": int(player.gold) if "gold" in player else 0,
  123  "level": int(player.level) if "level" in player else 1,
  ```
  and position is guarded by `player is Node3D and player.is_inside_tree()`.

- **The real risk (silent progression corruption):** the group fallback
  **ignores `character_id`**. It returns *whatever* live `"players"` node exists.
  In globe mode the body is **never registered with `EntityService`**
  (no `register_entity` call exists anywhere in the globe path -
  `globe_world.gd`, `globe_player.gd`), so `EntityService.get_entity(character_id)`
  returns `null` and the fallback is taken. `save_player` then keys the snapshot
  by `player.entity_id` and reads fields the globe body lacks as **0 / 0 / 1**.
  Consequences:
  1. When the globe body's `entity_id` equals the requested `character_id`
     (the normal case - `globe_world.gd:1411-1415` stamps it from
     `selected_character_data.character_id`), the autosave **overwrites a real
     save with experience=0, gold=0, level=1 every 30 s**
     (`AUTOSAVE_INTERVAL = 30.0`, `player_progress.gd:40`) - durable progression
     loss.
  2. The written `position` is the globe body's floating-origin local position
     (near the world origin), meaningless in the planar frame the snapshot is
     later restored into.
  3. When the ids differ, it writes a junk `player_1`-style key into the store
     and pollutes `_last_saved`.
- **Trigger condition:** the tick only runs for ids already in `_last_saved`,
  so it needs a prior `save_player`/`restore_player`/`load_progress` for that
  character (e.g. a session that touched the planar path first). Latent, not
  every-boot - which is exactly why it is dangerous.

---

## Receipt result

Command:

```
godot --headless --path game --script res://tests/test_globe_player_players_group.gd
```

Result: **PASSED, exit 0** - `5 checks, 0 failed`:

```
--- GLOBE PLAYER 'players' GROUP RECEIPT ---
   PASS  globe_player.gd loads
   PASS  globe body is in the 'players' group after _ready
   PASS  get_first_node_in_group('players') resolves the globe body
   PASS  a freed body leaves no live 'players' entry
   PASS  planar player_controller.gd still joins 'players' (parity)
=== GLOBE PLAYER 'players' GROUP RECEIPT: 5 checks, 0 failed ===
GLOBE PLAYER 'players' GROUP RECEIPT PASSED
```

Run note: this is a git worktree and `game/.godot/` (gitignored import cache,
including `global_script_class_cache.cfg`) was absent, so the first run spewed
`Could not find type "CharacterData"/"ZoneData"` parse errors and hung. Copying
the generated cache from the primary checkout (`/workspace/project/synmergia/game/.godot`,
not tracked, not code) let the receipt run clean. This is an environment artifact
of the worktree, not a repo defect.

---

## TOP RISK

**`game/core/services/player_progress.gd:294`** - the `_find_tracked_player`
fallback returns the globe body for *any* requested `character_id` without
checking identity. Because the globe body is not registered with `EntityService`
and lacks `experience`/`gold`/`level`, the autosave tick can silently overwrite
a real character snapshot with zeros (and a meaningless floating-origin
position) every 30 s. Crash-free but a durable-progression-loss bug.

Mitigating guards that make it latent (not an immediate crash): `save_player`
null/id-guards, the `"x" in player` field guards, and the fact the tick only
runs for ids already seen by the save path.
