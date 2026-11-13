#!/usr/bin/env bash
# Synmergia Godot test runner -- THE runner (one implementation).
#
# Runs headless Godot tests and reports pass/fail per test. Tests exit 0 =
# pass, non-zero = fail; "resources still in use at exit" notes are benign.
#
# One script, three shapes:
#   named tests  -> run exactly those
#   (no args)    -> the DEFAULT_SET regression block below
#   --all        -> every test_*.gd (tests/ + the co-located core/frame/)
#
# It runs them CONCURRENTLY when that helps and SERIALLY when that is
# faster, so there is ONE runner to remember, not two:
#   * one test, or JOBS=1 -> a single boot, no warm-import tax
#   * many tests          -> the .godot import is warmed ONCE, single-
#     threaded (a cold cache hit by N importers at once is the "abort only
#     under concurrent load" boot-noise class), then the boots run
#     JOBS-at-a-time. The timing-sensitive movement/terrain probes run
#     ALONE (JOBS=1) FIRST so CPU contention can never fake a movement
#     regression.
#
# Usage:
#   sh ./scripts/godot_test_runner.sh                          # default set
#   sh ./scripts/godot_test_runner.sh test_movement_profiles   # named tests
#   sh ./scripts/godot_test_runner.sh --all                    # every test_*.gd
#   -j N / JOBS=N    concurrent godot boots (default 4; capped at 2x cores
#                    and by available RAM -- a worker is a full boot)
#   --resume FILE    ledger of already-PASSed names; they are skipped and
#                    new passes are APPENDED, so a killed run carries on:
#                    sh ./scripts/godot_test_runner.sh --resume /tmp/led
#   SKIP_WARM=1      skip the warm import (only safe on a warm cache)
#
# Dash-safe: `sh ./scripts/...` re-execs itself under bash (the concurrent
# workers need `export -f`).

set -u

# Bash-only (export -f + xargs workers): re-exec under bash when invoked
# through dash, so the `sh ./scripts/...` habit does not die on an illegal
# export.
if [ -z "${BASH_VERSION:-}" ]; then
exec bash "$0" "$@"
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GAME_DIR="${ROOT_DIR}/game"
JOBS=4

if ! command -v godot >/dev/null 2>&1; then
echo "[runner] godot not on PATH. Install it or add it to PATH."
exit 1
fi

# ---------------------------------------------------------------- args
resume_file=""
tests_named=""
while [ $# -gt 0 ]; do
case "$1" in
-j)
JOBS="${2:-}"
shift 2
[ "${JOBS:-}" = "0" ] && JOBS=1
;;
--resume)
resume_file="${2:-}"
shift 2
;;
--all)
# Every test_*.gd, including the co-located core/frame tests.
tests_named="$(cd "${GAME_DIR}" && find tests core/frame -name 'test_*.gd' -not -path '*/.*' | sed -e 's#^tests/##' -e 's#^core/frame/##' -e 's#\.gd$##' | sort)"
shift
;;
-*)
echo "[runner] unknown flag: $1"
exit 2
;;
*)
tests_named="${tests_named:+$tests_named }$1"
shift
;;
esac
done
# Cap: a worker is a full godot boot (derives spawn their own threads
# inside). Beyond ~2x cores the boot contentions outweigh the queueing.
NPROC=$(nproc 2>/dev/null || echo 2)
[ "${JOBS}" -lt 0 ] 2>/dev/null && JOBS=1
JOBS=$((JOBS + 0))
JOBS_MAX=$((NPROC * 2))
if [ "${JOBS}" -gt "${JOBS_MAX}" ]; then
echo "[runner] JOBS ${JOBS} > 2x cores (${JOBS_MAX}), capped"
JOBS="${JOBS_MAX}"
fi
# MEMORY CAP: a worker is a full godot boot (measured ~1-1.5 GiB peak);
# beyond what MemAvailable holds the box swaps and every worker crawls.
MEM_PER_JOB_MB=1536
MEM_AVAIL_MB=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
if [ "${MEM_AVAIL_MB}" -gt 0 ]; then
MEM_MAX=$((MEM_AVAIL_MB / MEM_PER_JOB_MB))
[ "${MEM_MAX}" -lt 1 ] && MEM_MAX=1
if [ "${JOBS}" -gt "${MEM_MAX}" ]; then
echo "[runner] JOBS ${JOBS} > RAM budget (${MEM_MAX} x ${MEM_PER_JOB_MB} MiB of ${MEM_AVAIL_MB} MiB), capped"
JOBS="${MEM_MAX}"
fi
fi

# ------------------------------------------------- timing-sensitive set
# A movement/terrain probe measures walked distance against a WALL-CLOCK or
# FRAME budget. Under CPU contention the measured frame rate drops and the
# budget expires early, so the probe fails even though the engine is fine.
# Verified: probe_planet_control_100m passes solo and at JOBS=1, but fails
# at JOBS>=2 with an identical "100 m walk reaches ~30 m (got 9.8)" -- the
# walk simply did not get its frames. These run ALONE (JOBS=1) ahead of the
# swarm so a timing artifact never reads as a regression. The heavy
# continent shards are NOT listed: their long boots dominate, and they are
# re-run by name when they flake.
SERIAL_SET="
probe_planet_control_100m
probe_stream_flow_100m
probe_globe_world
probe_planet_walk_20km
probe_planet_rebase_20km
probe_riding
probe_climb
probe_glider
probe_thermals
"

# ------------------------------------------------------- default set
# THE regression block: work streams that must never silently rot.
# gen_fleet_packs.mjs parses this block (its regex is unanchored, so do NOT
# write the literal assignment token in prose above it), and comment lines
# and blanks are stripped when the block is read.
DEFAULT_SET="
test_data_naming_lint
test_class_focal_stats
test_achievements
test_achievement_flow
test_achievement_trigger_coverage
test_title_grant_parity
test_waking_verbs
test_sky_witness
test_quest_bridge_coverage
test_quest_lore_bridges
test_quest_explore_bridge
test_quest_swim_bridge
test_quest_glide_bridge
test_quest_craft_bridge
test_general_skills
test_item_catalog
test_zenith_capstone
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
test_character_select_zone
test_globe_wildlife
test_spawn_tables
test_globe_gates_guards
test_globe_input_parity
test_minimap_vendor_marker
test_content_ref_integrity
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
probe_ground_law_audit
probe_clipmap
probe_deep_garden
probe_instance_props
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
probe_conjured_ground
probe_prop_layer
probe_prop_port_laws
probe_world_scoping
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
probe_sky_crate
probe_blacksmith_model
probe_wolf_model
probe_slime_model
probe_bandit_model
probe_training_dummy_model
probe_thistle_boar_model
probe_anim_play
probe_blacksmith_scene
probe_world_shape_ground
test_agent_door_spec
test_agent_body_lifecycle
test_agent_roster_panel
test_globe_look_direction_wiring
"

# ------------------------------------------------------- resolve tests
# No named tests -> the DEFAULT_SET regression block. Strip its comment
# lines and blanks (the block is comment-annotated; a raw word-split would
# turn comment words into phantom test names).
if [ -z "${tests_named}" ]; then
tests_named="$(printf '%s\n' "${DEFAULT_SET}" | sed 's/#.*//' | grep -v '^[[:space:]]*$')"
fi

# ---------------------------------------------------------------- laws
# THE DISK-HYGIENE LAW (the 2026-10-13 incident: a runaway probe log ate
# 4.4 GB and the disk-full truncation cost a day of terrain work):
# (1) any single log file dies at the 256 MB cap - the writes fail with
# SIGXFSZ visibly (the test fails, the disk survives); (2) regenerable
# syn_* logs older than a day are swept at startup. Tolerate a pre-set
# hard limit (a re-set can fail when a parent already lowered it).
ulimit -f 262144 2>/dev/null || true
find /tmp -maxdepth 1 -name 'syn_*.log' -mtime +1 -delete 2>/dev/null

# ------------------------------------------------- resume ledger skip
if [ -n "${resume_file}" ]; then
touch "${resume_file}"
names=""
skipped=0
for t in ${tests_named}; do
if grep -qx "${t}" "${resume_file}"; then
skipped=$((skipped + 1))
else
names="${names} ${t}"
fi
done
echo "[runner] resume ledger: skipping ${skipped} already-passed names"
tests_named="$(printf '%s\n' "${names}")"
fi
if [ -z "$(printf '%s' "${tests_named}" | tr -d '[:space:]')" ]; then
echo "[runner] 0 passed, 0 failed (nothing to run)"
exit 0
fi

n_tests=0
for t in ${tests_named}; do
n_tests=$((n_tests + 1))
done
echo "[runner] ${n_tests} tests, ${JOBS} jobs"

# ------------------------------------------- warm the import (1 boot)
# The warm import makes every CONCURRENT worker's cache lookups read-only.
# It only helps when boots actually overlap: a single test, or JOBS=1, runs
# one boot at a time and needs no warm-up.
need_warm=0
if [ "${JOBS}" -gt 1 ] && [ "${n_tests}" -gt 1 ]; then
need_warm=1
fi
if [ "${SKIP_WARM:-0}" = "1" ]; then
echo "[runner] warm import: skipped (SKIP_WARM=1)"
elif [ "${need_warm}" = "1" ]; then
warm_t0=$(date +%s)
godot --headless --path "${GAME_DIR}" --import >/tmp/syn_warm_import.log 2>&1 ||
echo "[runner] WARN: warm import nonzero (see /tmp/syn_warm_import.log)"
echo "[runner] warm import: $(( $(date +%s) - warm_t0 ))s"
else
echo "[runner] warm import: skipped (single boot)"
fi

# ------------------------------------------------------------ workers
status_dir="$(mktemp -d /tmp/syn_par.XXXXXX)"
trap 'rm -rf "${status_dir}"' EXIT INT TERM
export status_dir GAME_DIR
run_t0=$(date +%s)

run_one() {
t="$1"
FRAME_REL="${t#frame/}"
RES_PATH="res://tests/${t}.gd"
if [ ! -f "${GAME_DIR}/tests/${t}.gd" ] && [ -f "${GAME_DIR}/core/frame/${FRAME_REL}.gd" ]; then
RES_PATH="res://core/frame/${FRAME_REL}.gd"
fi
if [ ! -f "${GAME_DIR}/tests/${t}.gd" ] && [ ! -f "${GAME_DIR}/core/frame/${FRAME_REL}.gd" ]; then
echo "[runner] ?? ${t}: no such test (game/tests/${t}.gd)"
echo "missing" >"${status_dir}/$(printf '%s' "${t}" | tr '/' '_')"
return
fi
# LONG-TIMEOUT SET: the continent shards cost minutes (20 km boots
# ~76 s + streamed faces ~50 s each). Everything else keeps 240 s.
PER_TIMEOUT=240
case "${t}" in
probe_stream_continent_a|probe_stream_continent_b|probe_stream_continent_c|probe_stream_continent_d) PER_TIMEOUT=600 ;;
esac
slug="$(printf '%s' "${t}" | tr '/' '_')"
t0=$(date +%s)
if (cd "${GAME_DIR}" && timeout "${PER_TIMEOUT}" godot --headless --path . --script "${RES_PATH}" >"/tmp/syn_${slug}.log" 2>&1); then
echo "[runner]    PASS ${t} ($(( $(date +%s) - t0 ))s)"
echo "pass" >"${status_dir}/${slug}"
echo "${t}" >>"${RESUME_APPEND}"
else
echo "[runner]    FAIL ${t} ($(( $(date +%s) - t0 ))s, log: /tmp/syn_${slug}.log)"
grep -E "FAIL|SCRIPT ERROR|Parse Error" "/tmp/syn_${slug}.log" 2>/dev/null | head -3
echo "fail" >"${status_dir}/${slug}"
fi
}
export -f run_one
RESUME_APPEND="${status_dir}/passes"
export RESUME_APPEND

# ------------------------------------------------- phase split
# Timing-sensitive probes run ALONE first (JOBS=1) so CPU contention cannot
# fake a movement regression; the rest run as the swarm.
serial_names=""
par_names=""
for t in ${tests_named}; do
if printf '%s\n' "${SERIAL_SET}" | grep -qx "${t}"; then
serial_names="${serial_names} ${t}"
else
par_names="${par_names} ${t}"
fi
done

if [ -n "${serial_names// /}" ]; then
n_serial=$(printf '%s\n' ${serial_names} | grep -c .)
echo "[runner] serial phase: ${n_serial} timing-sensitive probes, JOBS=1"
printf '%s\n' ${serial_names} | xargs -P 1 -I{} -n1 bash -c 'run_one "$1"' _ {} | cat
fi

if [ -n "${par_names// /}" ]; then
printf '%s\n' ${par_names} | xargs -P "${JOBS}" -I{} -n1 bash -c 'run_one "$1"' _ {} | cat
fi

# ------------------------------------------------------------ tally
pass=0
fail=0
missing=0
failed_names=""
for f in "${status_dir}"/*; do
v="$(cat "${f}")"
case "${v}" in
pass) pass=$((pass + 1)) ;;
missing)
missing=$((missing + 1))
failed_names="${failed_names} $(basename "${f}")"
;;
fail)
fail=$((fail + 1))
failed_names="${failed_names} $(basename "${f}")"
;;
esac
done

if [ -s "${RESUME_APPEND}" ] && [ -n "${resume_file}" ]; then
# Sorted append: idempotent (a re-run name re-passes once).
sort -u "${RESUME_APPEND}" >>"${resume_file}"
fi
rm -rf "${status_dir}"

echo "[runner] ${pass} passed, ${fail} failed${failed_names:+ [${failed_names}]}${missing:+ (${missing} unresolvable names)}"
echo "[runner] wall time: $(( $(date +%s) - run_t0 ))s (${JOBS} jobs)"
[ "${fail}" -eq 0 ] && [ "${missing}" -eq 0 ]
