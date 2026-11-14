# PRD - Housing and Plots

> **Status:** ACTIVE (2026-11-14). Canonical for `DwellingService`, player
> housing plots, house tiers, house guards, personal ankhs and placed
> stations. Territory ownership is a different layer:
> [`territory-system.md`](./territory-system.md). Guild organization:
> [`prd-guild.md`](./prd-guild.md). The paid homestead overlay is
> [`prd-monetization.md`](./prd-monetization.md) sec. 19; this document is
> the base service that overlay assumes.

A housing plot is a small player-owned parcel inside a zone. It is **not** a
territory: plots are personal, registered by a scene or world builder,
priced in gold, and held by one player. A territory groups zones and can be
claimed by a guild or contested in a faction war. Do not model plots as
`TerritoryData`, and do not let `/claim` touch a plot.

The current build is a real service with a narrow, chat-driven surface. It is
not yet a persistent housing system, and it is not the full `prd.md` feature
list.

## As-built surface

`game/core/services/dwelling_service.gd` is the authority. Autoload name is
`DwellingService`; it has no `class_name`.

| Capability | Entry point | Notes |
|---|---|---|
| Register a plot | `register_plot(plot_id, zone_id, center, radius, price)` | Scene/world-builder owned; no authored plot catalog yet |
| Buy a plot | `purchase_plot(player, plot_id)` | Deducts the plot price; one plot per player |
| Look up | `get_plot`, `get_plots`, `get_plots_for_player`, `get_nearest_plot` | Radius-based nearest lookup; filters `owned` / `unowned` |
| Build a house | `build_house(player, plot_id, house_id)` | One house per plot; reads `HouseData` |
| Place a guard | `place_house_guard(player, plot_id, name)` | 250,000 gold; one guard per plot |
| Place an ankh | `place_personal_ankh(player, plot_id)` | 100,000 gold; one ankh per plot |
| Place a station | `place_station(player, plot_id, dwelling_id)` | Consumes one placeable dwelling item; one slot per function |
| Remove a station | `remove_station(player, plot_id, function)` | Refunds the dwelling item |
| Plot status | `get_plot_stations` | Returns `{function: true}` for the plot |
| Station resolve | `resolve_nearby_station(player)` | Nearest placed station within its data radius |

The demo plot is registered in `game/scenes/worlds/globe_world.gd` as
`plot_haven_1` near the spawn surface, with a 50,000 gold price. There is no
`data/plots/` directory and no plot resource schema. A second plot requires a
scene edit or a new registration call.

## Commands

| Command | Result |
|---|---|
| `/buyplot` | Buys the nearest unowned plot the player is standing in |
| `/plotinfo` | Prints plot id, owner/sale state, price and placed station functions |
| `/buildhouse [tier]` | Raises `house_cottage` by default, or a `data/houses/` tier id |
| `/placeguard [name]` | Places the personal house guard on the owned plot |
| `/placeankh` | Places the personal respawn ankh on the owned plot |
| `/dismissguard` | Frees the guard slot; no gold refund |
| `/placestation <dwelling_id>` | Consumes a functional dwelling item and places its station |
| `/removestation` | Removes the first placed station and refunds the item |

All commands are routed through `ChatService` into
`DwellingService.handle_dwelling_command`. The service resolves the nearest
owned plot from the sender's current position; there is no housing UI and no
per-plot permission command.

## House tiers

Three tiers are authored in `game/data/houses/` and read through
`DataService.get_house` / `get_all_houses`. Geometry is procedural; every tier
uses the same wall/floor/gable builder parameterized by the data.

| Id | Display | Tier | Cost | Footprint | Wall height | Features |
|---|---|---|---|---|---|---|
| `house_claim` | Claim | 0 | 250,000 | 4 x 4 | 2.0 | wake clasp, bedroll |
| `house_cottage` | Cottage | 1 | 750,000 | 6 x 6 | 3.0 | chimney, sedum roof, conduit post |
| `house_hall` | Hall | 2 | 1,500,000 | 8 x 7 | 4.5 | stable bay, bell tower, gold finial, herb racks |

`HouseData` carries `cost`, `footprint`, `wall_height`, `door_width`,
`roof_pitch`, colors, `icon_path`, `model_path` and `features`. The tiers climb
in cost and wall height; `test_house_catalog` enforces the ladder. An unknown
tier does not crash: the service charges the fallback `HOUSE_COST` (750,000)
and builds the built-in cottage geometry, while stamping the requested tier
id. `build_house` stamps `plot.house_id` with the node name and
`plot.house_tier` with the data id.

`model_path` is currently blank on all three tiers. The procedural builder is
the real renderer; authored meshes are a seam, not a used path. `features` is
authored and checked by the catalog receipt, but the geometry builder does not
consume it.

## Placement access

`game/core/schemas/placement_access.gd` is the one ownership-scope vocabulary
shared by guards, ankhs, dwellings and future guild/faction halls:

| Scope | Who passes |
|---|---|
| `WORLD` | Everyone, except `deny_ids` |
| `PERSONAL` | Owner and `allowed_ids` |
| `GUILD` | Owner, allow list and same `guild_id` |
| `FACTION` | Owner, allow list and same `faction_id` |

`deny_ids` beats every scope, including `WORLD`; the owner always passes
before the scope check. Builders exist for `personal`, `guild`, `faction` and
`world`.

The current housing build is narrower than the vocabulary:

- House guards and personal ankhs are stamped `PERSONAL` with the buyer.
- A house structure itself has no access gate. Plot purchase does not create
  a `PlacementAccess`; entering the doorway is not permission-checked.
- Guild and faction scopes have builders and tests but no housing caller. A
  guild hall would need a plot owner kind, a guild access stamp and a
  permission path before the vocabulary becomes a real guild-house feature.

## Guards and ankhs

A house guard is a `GuardData`-driven NPC/enemy hybrid. `house_guard`
sets `PERSONAL` duty, the owner and allow list. `place_house_guard` attaches a
live `GuardAI`, posts it at the plot center, registers it with `EntityService`
and records `plot.guard_id`. The guard is friendly to the owner and allow
list; trespassers are valid targets and the guard keeps a permanent grudge
until an admin pardon. One guard per plot; dismissal clears the slot and does
not refund the 250,000 gold.

A personal ankh is created from `game/core/schemas/ankh.gd` with
`AnkhType.PERSONAL`, `PlacementAccess.personal(owner)` and the plot's zone.
`plot.ankh_id` records it. Binding sets `player.respawn_ankh_id` and the health
component's bind position, so `RespawnService` can offer the ankh respawn
mode. One ankh per plot; the 100,000 gold is not refunded on removal (there is
no removal command for the ankh yet).

## Stations and furniture

`data/dwellings/` has eleven placeable item resources. The station law only
accepts functional ones:

| `provides_function` | Station |
|---|---|
| `blacksmith` | Iron Anvil / Coal Forge repair station |
| `crafting_forge` | Coal Forge |
| `crafting_workbench` | Oak Workbench |
| `crafting_alchemy` | Brew Cauldron |

`place_station` consumes one item from the player's bag, builds a pedestal
node in the `placed_stations` group, stamps the plot's `stations[function]`
and exposes it through `resolve_nearby_station`. `remove_station` frees the
node and refunds the item. This is the functional-station arm of the crafting
law; the interaction opens the same `CraftingService.craft` gate an NPC bench
uses.

Decorative Hearth Kit items (`dwel_fireplace_stone`, `dwel_wooden_chair`,
`dwel_plank_bed`, `dwel_bookshelf`, `dwel_potted_megaseed`,
`dwel_coat_rack`, `dwel_lantern_post`) resolve as data and are checked by
`test_house_catalog`, but they are **not placeable** through `place_station`:
their `provides_function` is blank or non-station (`lore_library`,
`ambient_light`, `home_bind`). There is no general furniture-placement path.

`DwellingData.maintenance_cost` and `Item.maintenance_cost` exist but have no
reader; no housing upkeep is charged today.

## Persistence and authority

Housing is currently **runtime-only**. `_plots` is a plain dictionary on the
service; there is no `DictStore` key, no `save_plot`, no `load_plots`, and no
boot restore. The plot itself is registered by `globe_world` each boot. A
restart therefore returns the demo plot to unowned, removes every house,
guard, ankh and station, and clears the player's `house_tier`/station record.

The account-level home bind does survive through the existing player and
`RespawnService` state only as far as that state is persisted; the plot
record does not. Do not promise a durable homestead from this service yet.

## Receipts

- `game/tests/test_house_catalog.gd` (in `DEFAULT_SET`): house identity,
  filename==id, icon resolution, tier cost/height ladder, structural features,
  Hearth Kit data resolution, and `build_house` charging the tier cost and
  stamping `house_tier` (including the unknown-tier fallback).
- `game/tests/test_globe_gates_guards.gd` (in `DEFAULT_SET`): the demo
  `plot_haven_1` is registered on the globe in `zone_village_center` with a
  positive price.
- `game/tests/test_placement_system.gd` (not in `DEFAULT_SET`): plot
  registration/lookup, purchase gold and one-plot-per-player, non-owner
  denial, exact guard/ankh costs, guard ownership, ankh scope stamping and
  GuardAI personal targeting.
- `game/tests/test_guard_system.gd` (not in `DEFAULT_SET`): guard data
  factories, per-player hostility, watch-group sharing, permanent grudges,
  faction hostility and entity defaults.

There is no receipt for plot persistence, furniture placement, house access,
teleport home, storage, guild houses or relocation. Those are not shipped.

## Known gaps

- No plot persistence and no plot catalog. The demo plot is a scene
  registration, not authored world data.
- No housing UI. The only player surface is chat commands.
- No interior/exterior customization, no general furniture placement, no
  storage chest, no teleport-home command and no guild house.
- No plot access enforcement on the house structure; only guards and ankhs
  carry `PlacementAccess`.
- No relocation, sale, abandonment or demolition. One plot per player and one
  house per plot are hard rules.
- `prd.md` sec. 8 lists four house types (small/medium/large/mansion) and
  several P1 features that do not exist; the data has three tiers
  (Claim/Cottage/Hall) and the service has the narrower surface above.
- House tier `features`, `model_path` and maintenance costs are authored but
  unread; do not treat them as mechanics.
- `prd-monetization.md` sec. 19's deed move, clock door, hallmark and
  chartered homestead are a designed overlay, not current behavior. This
  document is the base they must build on.

## Open decisions

1. Define a persistent plot record and a durable house/guard/ankh/station
   overlay. Decide whether the plot catalog is authored data or scene-owned.
2. Decide whether the house structure uses `PlacementAccess` for entry, or
   whether plot ownership alone is the door law.
3. Add a general furniture path or delete the Hearth Kit promise. Functional
   stations are not furniture.
4. Decide the guild-hall shape: guild-owned plot, guild access stamp, rank
   gate, and what happens to placed objects when the guild disbands.
5. Decide relocation/sale/abandonment and the refund rules before charging
   more gold for a homestead.
6. Keep housing out of territory claims. If a future guild hall needs
   territory-scale ownership, link it through a separate record, not by
   overloading `TerritoryData`.
