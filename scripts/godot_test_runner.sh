#!/usr/bin/env bash
# Synmergia Godot test runner.
#
# Runs named headless Godot tests (default: the regression set covering
# the data-naming, movement, and 3d-pipeline work streams) and reports
# pass/fail per test. Godot tests exit 0 = pass, non-zero = fail;
# "resources still in use at exit" notes are benign.
#
# Usage:
#   sh ./scripts/godot_test_runner.sh                          # default set
#   sh ./scripts/godot_test_runner.sh test_movement_profiles   # named tests
#   sh ./scripts/godot_test_runner.sh --all                    # every test_*.gd
#
# Dash-safe: uses $0 (not BASH_SOURCE) so `sh ./scripts/...` works.

set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GAME_DIR="${ROOT_DIR}/game"

if ! command -v godot >/dev/null 2>&1; then
	echo "[runner] godot not on PATH. Install it or add it to PATH."
	exit 1
fi

# THE DISK-HYGIENE LAW (the 2026-10-13 incident: a runaway probe log
# ate 4.4 GB and the disk-full truncation cost a day of terrain work):
# (1) any single log file dies at the 256 MB cap - the writes fail
# with SIGXFSZ visibly (the test fails, the disk survives);
# (2) regenerable syn_* logs older than a day are swept at startup.
ulimit -f 262144
find /tmp -maxdepth 1 -name 'syn_*.log' -mtime +1 -delete 2>/dev/null

# Default regression set: work streams that must never silently rot.
DEFAULT_SET="
test_data_naming_lint
test_item_catalog
test_item_use
test_a11y_service
test_a11y_contrast
test_movement_profiles
test_anticheat_limits
test_hitbox_profiles
test_layer_profile
test_sign_service
test_daily_class_blessing
test_acts_service
test_daily_quest
test_quest_availability
test_level_curve
test_soulbind_revival
test_world_chunks
test_tick_n017_cleanup
test_tick_phase2_systems
test_combat_stack_live
test_globe_player_players_group
test_globe_concord_loop
test_globe_wildlife
test_globe_gates_guards
test_world_content_builder
test_globe_autosave_guard
test_blessed_mark
test_mysteries
test_audio_service
test_ambience_driver
test_cosmic_service
test_flywheel_service
test_weather_events
frame/math/test_spherical
frame/math/test_icosahedral_faces
frame/kv/test_folded_shell
frame/kv/test_t3_dedup
frame/kv/test_kv_schemas
frame/srv/test_star_cells
probe_ocean
frame/srv/test_swim_state
test_scope_stack_order
frame/srv/test_markov
frame/srv/test_cosmic_entropy
probe_swim
frame/srv/test_ferry_schedule
probe_ferry
probe_water_mounts
test_sundered_deep_economy
test_roster_and_dispatch
test_sundered_sea_swim
test_ui_manager_tooltip_wiring
test_sundered_ferry_barque
test_sea_bar_hud_ready
probe_riding
probe_ward_gate
probe_startup_flow
frame/srv/test_resource_scan
frame/srv/test_world_registry
probe_globe_world
probe_stream_flow_100m
probe_planet_control_100m
# CI-minutes chunks (the two former monolith probes, split):
# the 20 km continent shards + walk/rebase chunks exceed 4 min per
# process (boot ~76 s + streamed face ~50 s), so they run under the
# LONG_TIMEOUT cap below instead of the 240 s default.
probe_stream_continent_a
probe_stream_continent_b
probe_stream_continent_c
probe_stream_continent_d
probe_planet_walk_20km
probe_planet_rebase_20km
test_world_shape
test_terrain_determinism
test_terrain_splat_skin
probe_terrain_planet
probe_terrain_backend
probe_terrain_climate
probe_sundered_sea
test_instance_contract
test_shard_mesh_identity
test_adapter_http_transport
test_shard_bus
test_edge_transport
test_shard_mesh_topology
test_shard_tuning
test_shard_tuning_admin
test_content_packs
test_mesh_command
probe_arena_instance
probe_arena_trigger
probe_lobby_service
probe_arena_bridge
probe_bout_flow
probe_bout_host
probe_trial_bout
probe_recent_players
probe_social_presence
probe_dungeon_front_door
probe_scene_swap
probe_glider
probe_thermals
probe_royale_storm
probe_world_lattice
probe_world_state
probe_harvest
probe_crafting
probe_crafting_ui
probe_placeable_stations
probe_underworld
probe_world_scoping
probe_water_mounts
probe_terrain_backend
probe_round2_ui
probe_character_panel
probe_playtest_r12
probe_climb
probe_calibration
globe_driver
playthrough_driver
probe_ancient_loop
frame/math/test_penrose
frame/math/test_pentagrid
frame/srv/test_cosmic_rng
frame/srv/test_weather
probe_penrose_mesh
probe_sky_crate
probe_blacksmith_model
probe_wolf_model
probe_anim_play
probe_blacksmith_scene
probe_world_shape_ground
"

if [ "${1:-}" = "--all" ]; then
	TESTS=$(cd "${GAME_DIR}/tests" && ls test_*.gd | sed 's/\.gd$//')
else
	TESTS="$*"
	if [ -z "$TESTS" ]; then
		TESTS="${DEFAULT_SET}"
	fi
fi

pass=0
fail=0
failed_names=""
# LONG-TIMEOUT SET: process-heavy probes that cost minutes (20 km
# boots ~76 s + streamed faces ~50 s each). Everything else keeps
# the 240 s cap.
LONG_TESTS="
probe_stream_continent_a
probe_stream_continent_b
probe_stream_continent_c
probe_stream_continent_d
"
# The DEFAULT_SET above is comment-annotated; the raw list is word-split
# below, so comment words ("CI-minutes", "chunks", ...) and blank lines
# would become phantom test names -- and an empty token makes `grep -qx`
# match EVERY line, granting the long timeout to every test. Strip
# comments and blank lines from both lists before iterating.
TESTS="$(printf '%s\n' "${TESTS}" | sed 's/#.*//' | grep -v '^[[:space:]]*$')"
LONG_TESTS="$(printf '%s\n' "${LONG_TESTS}" | sed 's/#.*//' | grep -v '^[[:space:]]*$')"
for t in ${TESTS}; do
	# Frame primitives keep their tests co-located (frame rule);
	# a "frame/..." name resolves under core/frame/, else tests/.
	RES_PATH="res://tests/${t}.gd"
	FRAME_REL="${t#frame/}"
	if [ ! -f "${GAME_DIR}/tests/${t}.gd" ] && [ -f "${GAME_DIR}/core/frame/${FRAME_REL}.gd" ]; then
		RES_PATH="res://core/frame/${FRAME_REL}.gd"
	fi
	if [ ! -f "${GAME_DIR}/tests/${t}.gd" ] && [ ! -f "${GAME_DIR}/core/frame/${FRAME_REL}.gd" ]; then
		echo "[runner] ?? ${t}: no such test (game/tests/${t}.gd)"
		fail=$((fail + 1))
		failed_names="${failed_names} ${t}"
		continue
	fi
	echo "[runner] == ${t}"
	PER_TIMEOUT=240
	if printf '%s\n' "${LONG_TESTS}" | grep -qx "${t}"; then
		PER_TIMEOUT=600
	fi
	if (cd "${GAME_DIR}" && timeout ${PER_TIMEOUT} godot --headless --path . --script "${RES_PATH}" >"/tmp/syn_${t##*/}.log" 2>&1); then
		echo "[runner]    PASS ${t}"
		pass=$((pass + 1))
	else
		echo "[runner]    FAIL ${t} (log: /tmp/syn_${t}.log)"
		grep -E "FAIL|SCRIPT ERROR|Parse Error" "/tmp/syn_${t}.log" | head -5
		fail=$((fail + 1))
		failed_names="${failed_names} ${t}"
	fi
done

echo "[runner] ${pass} passed, ${fail} failed${failed_names:+ [${failed_names}]}"
[ "${fail}" -eq 0 ]
