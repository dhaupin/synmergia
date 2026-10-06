# PRD: The Riding Layer - One Ledger for Land, Water, Sky, and Space Mounts

> **Status:** SHIPPED (as built 2026-10-06)
> **Law:** `labs/prd-psy.md` (no religion anywhere in this doc), locked
> decisions in `AGENTS.md`, water-band truths in `labs/prd-ocean-depths.md`
> sec 15, movement truths in the Movement Design System
> (`data/movement_profiles/`, `game/core/schemas/movement_profile.gd`).
> **Naming:** mounts are `mount_` prefixed data ids, `mount_` prefix,
> filename == id; the service is `RideService`; anticheat stamping goes
> through `AntiCheatService.set_profile_limits`.

## 1. The Owner Vision (2026-10-06)

"Let's make a riding service next to tie land mounts, water mounts, and
make it flexible for sky mounts and space mounts. Currently we just have
gliders, launchers, and vortex for sky. But if our engine is to be as
glorious as we want, sky mounts are best to build alongside land and
sea. We can drop a few sky mount tres in. Three are the hardest mounts
to acquire by far, they are like elite creatures that should be
difficult to acquire."

So: one service that every kind of mount rides through, not three
parallel systems. Land already worked (S14.6 wading + dismount law),
water mounts work (S14.6 rated bodies), and this layer makes sky and
space mounts lawful the same way -- by data, never by special cases.

## 2. The Three Laws

1. **One ledger per rider.** What a player OWNS is persisted truth
   (DictStore key `ride_service/mounts/<player_id>`, the
   WaypointService/FerryService wake idiom). What a player is RIDING is
   session truth (`_active` book; summon again next login, like the
   ferry manifest). Quests, drops, vendors, and events all call
   `RideService.grant_mount` -- there is no second path, no dual-format
   shim, and duplicates are refused (soulbound is the default posture).
2. **Profiles own speeds.** The service never stores a number. Summon
   resolves the mount's MovementProfile through
   `DataService.get_mount_movement_profile` (the one derivation:
   explicit `movement_profile_id` wins, else kind -- GROUND ->
   quadruped, FLYING -> aerial, AQUATIC -> aquatic, SPACE -> mechanical
   today, its own class when space mounts land) and stamps the
   anticheat via `AntiCheatService.set_profile_limits`. Dismount hands
   the body back `movement_standard` (humanoid 25/25/110).
3. **The water handoff is one call.** `RideService.water_stamp_for(
   player_id, band)` returns `{action: ride | dismount | swim | none}`:
   land (and air/space) mounts ride while WADING and are dismissed at
   the waterline (`swim_state.MOUNT_DISMOUNT_ON_SUBMERGE`, the S12
   glider law mirrored); water mounts return their S14.6 swim stamp
   (speed, squeeze grace, crush bonus, current immunity) for the caller
   to feed `set_aquatic_limits` + `set_current_drift`. The band laws
   live in exactly one place.

## 3. The Stamping Seam (anticheat)

`AntiCheatService.set_profile_limits(player_id, profile_id)` resolves
the profile via `DataService.get_movement_profile` and stamps through
the existing `_limits_from_profile` path (x2.5 speed, x2.5 jump, x2.0
fall multipliers). Unknown profile -> false, no stamp. NO new anticheat
fields: every mount is just a movement profile wearing a costume, and
the S14 ray ceiling (9 m/s cruise x 2.5 = 22.5) already proved the
shape.

## 4. The Elite Three (acquisition difficulty lives in the DATA)

The service is the ledger, never the gate. Difficulty is `source`,
`required_level`, and the drop's rarity, all in the .tres:

| Mount | Kind | Source | Level | Profile | Notes |
|-------|------|--------|-------|---------|-------|
| `mount_storm_lancer` | FLYING | 0 (DROP) | 50 | `movement_sky_lancer` | sprint 21, jump 16, gravity 8 -- the ceiling ceiling: 21 x 2.5 = 52.5 |
| `mount_skyreef_soarer` | FLYING | 1 (QUEST) | 55 | `movement_sky_soarer` | sprint 17, air_control 1.0, gravity 7; `hitbox_sky_large` |
| `mount_moonwing_moth` | FLYING | 4 (EVENT) | 50 | `movement_sky_moth` | sprint 15, gravity 5, turn_grip 0.9 |

All three: cost 0, soulbound, `locomotion_class = 2` (the aerial class
`movement_aerial.tres` already claims). Drop/quest/event are the three
hardest acquisition doors the game has; the moth being EVENT-only makes
it the scarcest, the soarer the highest wall (level 55 + a quest line),
the lancer the boss-drop trophy.

## 5. Space Is Already Lawful

`MountKind.SPACE` rides the same ledger, the same stamping seam, and
the same dismount law. When a space mount lands, its profile owns the
gravity and the stamp just works -- no new RideService code, one new
profile (a `movement_lunar`-class .tres) and one new mount .tres. That
is the flexibility the owner asked for: the KIND is data, the LAWS are
the layer.

## 6. As Built (2026-10-06)

- `game/core/services/ride_service.gd` -- NEW autoload (registered
  after FerryService in `project.godot`). grant/revoke/owns (ledger),
  summon/dismiss/active_mount (session), water_stamp_for (handoff).
- `game/core/schemas/mount_data.gd` -- `MountKind.SPACE` added.
- `game/core/services/anticheat_service.gd` -- `set_profile_limits`.
- `game/data/movement_profiles/movement_sky_{lancer,soarer,moth}.tres`
  -- NEW elite flight profiles.
- `game/data/mounts/mount_{storm_lancer,skyreef_soarer,moonwing_moth}.tres`
  -- NEW elite sky mounts (the table in sec 4).
- `game/data/hitbox_profiles/hitbox_sky_large.tres` -- NEW (sphere 1.6,
  the soarer; playable species keep the ONE player hitbox -- mounts
  are rated bodies, not players).
- `game/tests/probe_riding.gd` -- NEW gate probe, 33 checks, in the
  runner DEFAULT_SET: declarations/elite-law/hitbox refs, ledger
  persistence + duplicate refusal, summon stamping (lancer ceiling
  52.5 = 21 x 2.5, dismiss -> humanoid 25.0), water handoff (ray swim
  stamp, glider immune, wyrm crush bonus, plains_runner wading rides
  band 1 and dismounts band 3 with book cleared + restamp, no-mount
  "none"), SPACE enum, revoke-dismisses.
- NOT in this slice (by design, seams not screens): runtime 3D riding
  (saddle points, mount-follow physics), mount UI, vendor/quest wiring
  that calls grant_mount. RideService is the seam those features plug
  into.
