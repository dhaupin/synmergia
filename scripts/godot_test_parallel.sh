#!/usr/bin/env bash
# Synmergia Godot test runner - PARALLEL edition.
#
# Sister of scripts/godot_test_runner.sh with the same laws (per-test boot,
# per-test timeout, /tmp/syn_*.log, "N passed, M failed" summary, exit 0 iff
# no failures) but the boots run CONCURRENTLY: the 90-minute full sweep
# drops to roughly wall-time / JOBS instead of a serial march.
#
# `--all` is PARALLEL from BOTH entry points: godot_test_runner.sh --all
# delegates here, and this script's own --all does the same full sweep.
#
# Usage:
#   sh ./scripts/godot_test_parallel.sh                       # default set
#   sh ./scripts/godot_test_parallel.sh test_movement_profiles # named tests
#   sh ./scripts/godot_test_parallel.sh --all                  # every test_*.gd
#   -j N / JOBS=N   number of concurrent godot boots (default: min(4, nproc))
#   --resume FILE   ledger file of already-PASSed test names; they are
#                   skipped (a line per name, '#' comments allowed) and any
#                   pass is APPENDED to it. Restart a killed run as:
#                   sh ./scripts/godot_test_parallel.sh --resume /tmp/led
#
# Ordering law of cooperation (why this script CAN parallelize what the
# serial runner could not):
# (1) THE IMPORT CACHE IS WARM-BOOTED FIRST, once, single-threaded.
#     Every godot process touches game/.godot on boot; a cold cache hit by
#     N importers at once is the "abort only under concurrent load" boot
#     noise class (the continent shards). One `--import` pass first makes
#     every worker boot read-only-warm.
# (2) Workers share NOTHING outside the cache: each test keeps its own
#     per-test log file and its own status file; named tests with '/' in
#     them (frame/...) are flattened to a safe slug.
# (3) A test that fails stays failed: no blind auto-retry hides a real
#     break - a flake is re-run BY NAME, visibly, the way the serial
#     runner records it.
#
# The ping of the run: the walls are the sandbox's, so JOBS is capped to
# the CPU budget; two heavy terrain shards running together is slower,
# not faster (the long probes are already multi-threaded derives). The
# default JOBS floor is modest on purpose; raise it with -j on fatter
# hosts (CI runners: -j 4).

set -u

# Bash-only script (needs `export -f` for the xargs workers): the
# dash-safe `sh ./scripts/...` invocation re-execs itself under bash so
# the dash-safe habit does not die on an illegal export.
if [ -z "${BASH_VERSION:-}" ]; then
	exec bash "$0" "$@"
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GAME_DIR="${ROOT_DIR}/game"
JOBS=4

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
		# Recursive: the --all contract in web-ci's old loop walked
		# game/tests/ subdirectories too (lint/, frame/... co-located).
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
# Cores are the usual ceiling, but on a small-RAM host this is the real
# one -- the parallel runner must not be the thing that OOMs the box.
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
# at JOBS=2 and JOBS=4 with an identical "100 m walk reaches ~30 m (got
# 9.8)" -- the walk simply did not get its frames. These run ALONE (JOBS=1)
# ahead of the parallel swarm so a timing artifact never reads as a
# regression. The heavy continent shards are NOT listed: their long boots
# dominate, and they are re-run by name when they flake.
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
if [ -z "${tests_named}" ]; then
	# The runner's own DEFAULT_SET block is the single source of truth
	# (gen_fleet_packs.mjs parses the same block).
	block="$(sed -n '/^DEFAULT_SET="/,/^"$/p' "${ROOT_DIR}/scripts/godot_test_runner.sh")"
	tests_named="$(printf '%s\n' "${block}" | sed 's/^DEFAULT_SET="//; s/"$//' | sed 's/#.*//' | grep -v '^[[:space:]]*$')"
fi

if ! command -v godot >/dev/null 2>&1; then
	echo "[runner] godot not on PATH. Install it or add it to PATH."
	exit 1
fi

# ---------------------------------------------------------------- laws
# Same disk-hygiene law as the serial runner (2026-10-13 incident).
# Tolerate a pre-set hard limit: when the serial runner delegates here
# via `--all`, its dash `ulimit -f` already lowered the HARD limit, so a
# re-set here would fail. The cap is inherited either way -- a failure to
# re-set is not a reason to abort the sweep.
ulimit -f 262144 2>/dev/null || true
find /tmp -maxdepth 1 -name 'syn_*.log' -mtime +1 -delete 2>/dev/null

n_tests=0
for t in ${tests_named}; do
	n_tests=$((n_tests + 1))
done
echo "[runner] parallel: ${n_tests} tests, ${JOBS} jobs"

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

# ------------------------------------------- warm the import (1 boot)
# The one serial boot: makes every worker's cache lookups read-only.
# SKIP_WARM=1 skips it for fast local iteration (only safe when the
# cache was already warmed by a prior run).
if [ "${SKIP_WARM:-0}" = "1" ]; then
	echo "[runner] warm import: skipped (SKIP_WARM=1)"
else
	warm_t0=$(date +%s)
	godot --headless --path "${GAME_DIR}" --import >/tmp/syn_warm_import.log 2>&1 ||
		echo "[runner] WARN: warm import nonzero (see /tmp/syn_warm_import.log)"
	echo "[runner] warm import: $(( $(date +%s) - warm_t0 ))s"
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
	# LONG-TIMEOUT SET: same two-shard list the serial runner holds.
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
# Timing-sensitive probes run ALONE first (JOBS=1) so CPU contention
# cannot fake a movement regression; the rest run as the parallel swarm.
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
