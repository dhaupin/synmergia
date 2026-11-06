# LANE B smoke test -- player boot path + input -> movement wiring map

Scope: docs only. Every claim below is grounded in a file read in this
session; file:line references are the anchors. No game/ code was changed.

## Boot sequence (ordered)

Entry is `res://ui/menus/main_menu.tscn` (`game/project.godot` run/main_scene).
The world is swapped in by `GameManager`:

1. `GameManager._handle_playing_state()` runs on the PLAYING state
   (`game/core/autoload/game_manager.gd:163`). It calls
   `_initialize_world_services()`, then picks the world scene.
2. World-shape resolve: default is `res://scenes/world_playable.tscn`; if
   `WorldShapeResolver.is_spherical()` the path is swapped to
   `res://scenes/worlds/globe_world.tscn`
   (`game_manager.gd:170-174`, `core/frame/math/world_shape.gd:26`).
3. A persistent root `CanvasLayer` loading overlay (layer 100) is shown
   (`_ensure_boot_loading_overlay`, `game_manager.gd:227`), then the scene
   swap runs through the threaded loader
   (`_show_loading_and_change_scene` -> `_threaded_scene_swap`,
   `game_manager.gd:243`, `:284`) with `change_scene_to_packed` (`:317`).
4. `globe_world.gd::_ready()` builds the world synchronously
   (`game/scenes/worlds/globe_world.gd:121`), in this order:
   - `world_root` created and added (`:130-132`)
   - `_build_shell()` (`:133`), `_build_surface_pad()` (`:135`)
   - `_install_world_backend()` (`:137`)
   - `_build_sun()` / `_build_sky_sun()` / `_build_sky_moon()` (`:139-141`)
   - `_setup_streamer()` (`:146`) -- built BEFORE the player so the spawn
     height can ride the terrain law (comment at `:143-145`)
   - `_build_water()` (`:148`)
   - `_build_player()` (`:158`) -- see step 5
   - `planet_center` set, `player.planet_center` wired (`:160-161`)
   - `_install_hud()` (`:162`), `_setup_touch_hud()` (`:163`)
   - `_build_spawn_truth()` (`:172`) -- on-screen lat/lon/ground/sea line
   - `_boot_waves()` (`:178`) -- POIs, NPCs, decor, ambience land one per
     frame AFTER the overlay is down (`:186-201`), stamping
     `boot_waves_done_ms` meta (`:201`).
5. `globe_world._build_player()` (`:1342`) constructs the player entirely in
   code:
   - `CharacterBody3D.new()` + `set_script(load("res://entities/globe_player.gd"))`
     (`:1343-1345`), collision layer/mask set (`:1350-1351`)
   - adds `CollisionShape3D` sphere (`:1353-1357`), body mesh (`:1359-1368`),
     `CameraPivot` + `Camera3D` (`:1370-1377`)
   - spawn position = spherical convention on the walk surface
     (`:1418-1421`); a SEA GUARD lifts the boot above the sea line and logs
     LOUD if the terrain law would spawn underwater (`:1400-1405`)
   - `entity_id` stamped from `GameManager.selected_character_data`, else
     `"player_1"` (`:1411-1417`)
   - `player.planet_radius`, `ground_offset`, then `add_child(player)` (`:1430-1432`)
   - `_install_walk_provider()` (`:1433`) -- binds the player's
     `snap_height_provider` to the streamer's `walk_surface_h` (`:384-390`)
   - adopts `SkySun` / `SkyMoon` onto the player (floating-origin celestial
     frame) (`:1436-1447`)
   - `player.begin_loop()` (`:1448`)
   - `_notify_world_entry()` (`:1454`) emits `GameManager.player_entered_world`
     exactly once (`:1461-1469`), which is what StarterKitService listens to.
6. `globe_player.gd::_ready()` (`game/entities/globe_player.gd:449`) adds a
   `HealthComponent` (`:459-464`), builds/registers the inventory bag
   (`_setup_inventory_bag`, `:471`), calls `PlayerManager.set_local_player(self)`
   (`:478-480`), wires the touch joystick's `sprint_override` (`:484-488`),
   connects `RideService` mount signals (`:494-499`), reads the glider
   deployment setting (`:502-506`), and defers the anticheat stamp (`:509`).
7. Per-frame: `globe_world._physics_process()` (`:521`) updates the surface
   pad, streams terrain around the player, and runs the floating-origin
   rebase `_maybe_shift_world()` (`:538` -> `:258`); `globe_player._physics_process()`
   (`globe_player.gd:612`) is the movement tick.

## Input -> movement path

There are TWO input paths in the repo; the globe path does not use the
planar controller's signal path.

Plane A -- event signal path (planar `world_playable`, NOT the globe):
- `InputManager._input()` -> `_handle_event()` -> `_handle_keyboard_mouse()`
  maps keys to actions and emits `player_input(action, pressed)`
  (`core/autoload/input_manager.gd:280`, `:345`, `:354-362`;
  signal declared `:19`).
- `PlayerController._ready()` connects it (`entities/player/player_controller.gd:450`)
  and `_on_player_input()` consumes it (`:1267`), handling `sprint`,
  `target_*`, `interact`, `ability_1..8`.
- `ActionBar._connect_signals()` also connects `player_input` and routes
  `ability_*` to the local player's `use_skill`
  (`ui/components/action_bar.gd:355`, `:407-433`).

Plane B -- polled path (the globe player, `globe_world`):
- Movement: `globe_player._physics_process()` polls
  `InputManager.get_movement_input()` (with a raw `Input.get_vector`
  fallback for script-mode), then builds a CAMERA-RELATIVE wish vector
  (`globe_player.gd:699-701`). `get_movement_input()` merges
  controller > touch joystick > keyboard
  (`input_manager.gd:482-505`).
- Look: the touch HUD's `camera_look` is bridged in
  `globe_world._setup_touch_hud()` (`globe_world.gd:304-319`) into
  `globe_player.orbit_camera()` (`globe_player.gd:210`).
- Jump / crouch / sprint / dismount are read by raw `Input.is_action_*`
  polls inside `_physics_process`: crouch `:731`, sprint `:749`,
  jump `:838` (and mounted variants `:817`, `:856`, `:892`).
- `_text_entry_focused()` guards both the event pipeline
  (`input_manager.gd:351`) and the poll (`:485`, `globe_player.gd:386`).
- `InputManager._setup_input_actions()` (called at `input_manager.gd:110`,
  defined at `:213`) ensures the action names exist, and the
  keyboard/mouse/jump/sprint bindings live in `game/project.godot` `[input]`
  (line 135+).

So in globe mode the movement/jump/look loop is: engine input -> InputManager
poll helpers / touch-HUD signals -> `globe_player._physics_process()` ->
`move_and_slide()` with the radial `up_direction`.

## TODOs / stubs spotted on this path

- `input_manager.gd:338-341`: the `InputMode.TOUCH` branch of
  `_handle_event()` is an explicit `pass` -- touch input is fully delegated
  to the `VirtualJoystick` HUD, not handled here. Intentional, but it is the
  one literal stub on the event path.
- `globe_player.gd` has NO `player_input` connection and NO
  `_on_player_input` / `interact` / `ability_*` handling (grep returns
  nothing). Unlike `PlayerController`, the globe body never consumes the
  `player_input` signal -- so `interact`, targeting and ability actions
  emitted by `InputManager` reach only `ActionBar` (via its own connect),
  and the globe body itself only polls movement/jump/crouch/sprint.
- `globe_player.gd` is NOT added to the `"players"` group (no
  `add_to_group` call), whereas `player_controller.gd:452` does
  `add_to_group("players")`. `ActionBar._on_player_input()` resolves the
  caster via `get_tree().get_first_node_in_group("players")`
  (`action_bar.gd:431`), so on the globe that lookup cannot find the local
  body. (PlayerManager binding is fine -- `set_local_player` is called at
  `globe_player.gd:478-480`.)
