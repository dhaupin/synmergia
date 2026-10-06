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
   quadruped, FLYING -> aerial, AQUATIC -> aquatic, SPACE ->
   leviathan -- its own class since R44, when the first space mount
   landed) and stamps the anticheat via
   `AntiCheatService.set_profile_limits`. (The SPACE default is
   `movement_leviathan`; the id `movement_lunar` was already S16.4's
   Lunar Settler humanoid and stays untouched.) Dismount hands
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
the layer. (As built R44: the Vesper -- `mount_vesper_whale` rides
`movement_leviathan`; see sec 8.)

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

## 7. Round Two as Built (2026-10-06): the cliff law lands, the warden takes the sky, the rider is told

The named seams of sec 6 stay seams (3D saddle physics, mount UI, grant
wiring). This round makes the LAYER real instead: the two laws that
were decided but unwired are now executed, and the rider hears about
it.

- **The cliff law, service-executed.**
  `glider_state.MOUNT_DISMOUNT_ON_FALL` was decided in S12 ("the mount
  BAILS ... the rider dismounts into freefall and the glider is usable
  from there; the mount despawns back to its whistle") with the note
  "implementation lands with the mount-riding system." It landed:
  `RideService.fall_stamp_for(player_id, falling, altitude)` ->
  `{action: none | ride | bail}`. The bail gate is the GLIDER's deploy
  gate (one number, `GliderState.DEPLOY_HEIGHT_METERS` = 6.0) --
  falling below it is a hop, not a bail. Only GROUND mounts bail
  (`MountData.bails_on_fall()`): sky mounts fly -- falling IS their
  job; swimmers swim; space is space.
- **The GM door.** `MountSource.GM` is the acquisition door that is
  not a door: `RideService.grant_mount` is FAIL-CLOSED for it (an
  unknown rider is not a warden), and `GameManager.player_entered_world`
  auto-answers a GM's entry with the whistle (idempotent -- the ledger
  refuses duplicates). `mount_gm_skywarden` ("Skywarden", FLYING,
  level 1, cost 0, soulbound) rides `movement_gm_sky` -- sprint 28
  (ceiling 70 = 28 x 2.5), jump 22 (55), gravity 5, air_control 1.0,
  sprint_stamina_cost 0 (the Warden does not tire). Fastest body in
  the sky by design; GM tooling, not a leaderboard entry.
- **The level gate closes.** `MountData.required_level` was declared
  in the first schema and enforced nowhere. `summon` now enforces it
  for every rider the service knows (world-entry truth); unknown
  riders (probes, admin paths, agents) stay trusted service-level
  callers -- documented, deliberate: the SOURCE gates acquisition
  (drop, quest, event, GM), the summon gate is the second lock on the
  same door.
- **The rider's voice.** `NotifKind.MOUNT_SUMMONED` /
  `MOUNT_DISMISSED` ride the typed pipeline ("You summon the Storm
  Lancer" / "The Storm Lancer returns to its whistle") with explicit
  INFO/NORMAL mappings. The service announces RIDING; acquisition
  announcements belong to whatever grants (quest, loot, GM command).

## 8. Round Three as Built (2026-10-06): the first space mount -- the Vesper answers a whistle

Sec 5 promised "one new profile, one new mount .tres, no new service
code." It held -- plus the one line sec 2 reserved: the kind default
grew its SPACE case when the mount landed. The Vesper is the proof:

- **`game/data/movement_profiles/movement_leviathan.tres`** -- NEW,
  the lunar class, under a NEW id: `movement_lunar` was already
  shipped canon (S16.4's "Lunar Settler" humanoid, the per-world
  low-gravity archetype) and the mount profile does not squat it.
  Locomotion 2 (aerial -- the class enum has no space;
  gravity being PROFILE data is the whole point), sprint 24 (stamp
  ceiling 60 = 24 x 2.5 -- the fastest PUBLIC body in the sky; the
  Skywarden's 70 stays warden-only), jump 24 (60), gravity 2.5,
  terminal 40, air_control 1.0, turn_grip 0.6 (a leviathan turns like
  a thought), no stamina. Nothing in code knows this mount is
  special: the profile owns the physics, the anticheat already
  speaks profile.
- **`game/data/mounts/mount_vesper_whale.tres`** -- NEW, MountKind
  .SPACE, EVENT-sourced (the moth's door, the scarcest), required
  level 60 -- the highest wall yet (the soarer's 55 was), cost 0,
  soulbound, `hitbox_sky_large` (mounts are rated bodies, not
  players). It swims the dark between the world's curve and the
  Watched Stone -- the spherical frame's above-the-sky stratum,
  lawful because the lunar profile says so.
- **`data_service.gd`** -- ONE line: kind default SPACE ->
  `movement_leviathan` (was the quadruped catch-all; sec 2's "its own
  class when space mounts land" is now true). Explicit
  `movement_profile_id` still wins; the one derivation is untouched.
- **The layer held.** probe_riding 53 -> 67 checks, 0 failures: the
  Vesper end-to-end through the IDENTICAL path -- grant/summon/
  dismiss, the anticheat stamp by its own profile (60 ceiling),
  wading rides, waterline dismount (space is not a swimmer), the
  cliff law (space does not bail: it remembers the way down), the
  level gate (59 waits, 60 rides), and the kind default proven by
  blanking the explicit id on a duplicate. No new RideService code;
  sec 5 was not a promise, it was a schedule.
- **The rider is told.** The Vesper's summon is asserted through the
  typed pipeline (`MOUNT_SUMMONED -> INFO`, player-directed,
  message "You summon the Vesper") -- the a11y human/agent controller
  layer hears the dark arrive the way it hears everything else:
  typed, mapped, addressable by screen reader and probe alike. No
  new NotifKind needed; riding already has a voice.
