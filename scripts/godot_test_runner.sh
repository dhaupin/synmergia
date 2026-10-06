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

# Default regression set: work streams that must never silently rot.
DEFAULT_SET="
test_data_naming_lint
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
test_world_chunks
test_tick_n017_cleanup
test_tick_phase2_systems
test_combat_stack_live
test_blessed_mark
test_mysteries
test_audio_service
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
probe_swim
frame/srv/test_ferry_schedule
probe_ferry
probe_water_mounts
probe_startup_flow
frame/srv/test_resource_scan
frame/srv/test_world_registry
probe_globe_world
probe_terrain_stream
probe_planet_scale_20km
test_world_shape
test_terrain_determinism
probe_terrain_planet
test_instance_contract
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
probe_underworld
probe_world_scoping
probe_round2_ui
probe_character_panel
probe_playtest_r12
probe_climb
probe_calibration
globe_driver
probe_ancient_loop
probe_blacksmith_model
probe_wolf_model
probe_anim_play
probe_blacksmith_scene
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
	if (cd "${GAME_DIR}" && timeout 120 godot --headless --path . --script "${RES_PATH}" >"/tmp/syn_${t##*/}.log" 2>&1); then
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
