## AntiCheatService - Detects and prevents cheating for humans AND agents
## Includes bot detection, macro detection, speed hacks, and anomaly detection
extends Node

## Runtime autoload lookups (script-mode-safe; the bare identifiers
## fail compile when autoloads are absent -- test_islands).
func _r_securityservice() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("SecurityService")) if tree and tree.root else null

func _r_dataservice() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("DataService")) if tree and tree.root else null

func _r_gamelog() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameLog")) if tree and tree.root else null

const DictStore = preload("res://adapters/persistence/dict_store.gd")

signal cheat_detected(player_id: String, cheat_type: String, confidence: float, evidence: Dictionary)
signal player_flagged(player_id: String, flag_type: String)
signal player_banned(player_id: String, reason: String)
signal player_unbanned(player_id: String)

## Detection thresholds
const PERFECT_TIMING_THRESHOLD: float = 0.02  # Human jitter is ~50ms+
const MOVEMENT_PREDICTION_WINDOW: float = 5.0  # Seconds of movement to analyze
const RESPONSE_TIME_VARIANCE_HUMAN: float = 0.3  # Humans have ~30% variance
const IDLE_CHANCE_HUMAN: float = 0.02  # Humans idle ~2% of time
const PATH_REPETITION_THRESHOLD: float = 0.8  # 80% same path = suspicious

## Session heuristics
const SESSION_VARIANCE_HUMAN_MIN: float = 0.1  # Variance in session lengths
const BREAK_FREQUENCY_HUMAN: float = 0.1  # Expected breaks per hour

## Hard physics limits (Movement Design System -- the limits RESOLVE
## FROM each player's MovementProfile .tres, so a retune of game feel
## retunes the anticheat with it; nobody edits two sources of truth).
## Multipliers sit ON TOP of the profile's legal maxima: a speedhack
## must beat the fastest LEGAL state (slide peaks ~1.9x walk, dodge
## adds a small hop) by a wide margin before it counts.
const SPEED_LIMIT_MULTIPLIER: float = 2.5   # x profile's fastest legal speed
const JUMP_LIMIT_MULTIPLIER: float = 2.5    # x profile's jump_force launch
const FALL_LIMIT_MULTIPLIER: float = 2.0    # x profile's terminal_fall_speed
const VERTICAL_HARD_CLAMP: float = 120.0    # abs(vy) sanity bound (m/s)

## Glide device bounds (S11 groundwork: gliders, BotW-style). Gliding
## is SLOW and gravity-tamed by design -- a fast-falling or speeding
## wing is a hacked wing. While a player is flagged gliding, these
## REPLACE their profile speed/fall maxima (jump stays profile-bound;
## gliders cannot jump). The controller calls set_glide_active() when
## the wing deploys/stows.
const GLIDE_MAX_SPEED: float = 24.0   # ~1.4x the fastest wing's sprint
const GLIDE_MAX_FALL: float = 14.0    # glide sink is gentle by design
## Consecutive violating frames before an exploit report. One bad
## frame is lag/teleport-lag/noise; half a second of sustained
## over-limit motion is a hack.
const SUSTAINED_FRAME_LIMIT: int = 30

## Launch/throw whitelist (S12.5 sky roads + S13 ROYALE drop): an
## ancient launcher hurls you up at 30+ m/s and the Royale throw
## starts the bout from the sky. Both are LEGAL upward speeds far
## above the profile jump limit, so upward violations are forgiven
## while a launch ticket is live. Tickets are written server-side by
## ThermalService's launcher path and the arena drop -- a player can
## never claim one -- and they legalize ONLY the vertical vector:
## horizontal speedhacks and absurd |vy| stay hard-flagged.
const LAUNCH_GRACE_SECONDS: float = 2.5
const LAUNCH_SPEED_CEILING: float = 40.0  # above this, no ticket helps

## player_id -> expiry (Time.get_ticks_msec). Transient by design:
## a reboot kills seconds-old tickets, which is harmless.
var _launch_grants: Dictionary = {}

var _player_profiles: Dictionary = {}  # player_id -> Profile data
var _suspicion_scores: Dictionary = {}  # player_id -> suspicion (0.0 to 1.0)
var _banned_players: Dictionary = {}  # player_id -> ban info
## Movement-limit state per player: stamped limits, violation streaks,
## GM bypass. Stamped by the player body at spawn (GlobeWorldPlayer
## _call_deferred_stamp; the planar controller did the same before Step 5)
## -- an unregistered player's telemetry is still counted (the profile
## defaults below) so nothing escapes by skipping registration.
var _movement_limits: Dictionary = {}  # player_id -> {max_speed, max_jump, max_fall}

## DictStore key prefix
const _kv_prefix := "anticheat:"

class PlayerProfile:
	var player_id: String
	var is_agent: bool
	var action_timestamps: Array = []
	var movement_paths: Array = []  # Array of Vector3 positions
	var response_times: Array = []  # ms between stimulus and action
	var idle_periods: Array = []  # Array of {start, end} idle times
	var session_start: int = 0
	var last_position: Vector3 = Vector3.ZERO
	var last_action_time: int = 0
	## Consecutive frames over a hard movement limit (speedhack streak).
	var speed_violation_streak: int = 0

	func _init(p_id: String, agent: bool):
		player_id = p_id
		is_agent = agent
		session_start = Time.get_ticks_msec()
		last_action_time = session_start

## Boot: restore persisted suspicion/ban state and wire the escalation
## chain -- cheat_detected -> _r_securityservice().exploit_detected so
## hard-limit confirmations join AutoResponseService's speedhack rules
## (3 confirmations -> admin review; auto-ban stays config-gated).
func _ready() -> void:
	_load_state()
	if _r_securityservice() and _r_securityservice().has_method("report_anticheat_finding"):
		cheat_detected.connect(_r_securityservice().report_anticheat_finding)


## Register a new player
func register_player(player_id: String, is_agent: bool = false) -> void:
	if not _player_profiles.has(player_id):
		_player_profiles[player_id] = PlayerProfile.new(player_id, is_agent)
		_suspicion_scores[player_id] = 0.0
		_persist_suspicion(player_id)
		_r_gamelog().info("AntiCheatService: Monitoring %s (%s)" % [player_id, "Agent" if is_agent else "Human"])

## Unregister player
func unregister_player(player_id: String) -> void:
	_player_profiles.erase(player_id)
	_suspicion_scores.erase(player_id)
	_movement_limits.erase(player_id)
	_launch_grants.erase(player_id)
	_aquatic_limits.erase(player_id)
	_current_drift.erase(player_id)
	_dive_grants.erase(player_id)


## == Launch tickets (launcher rides / bout throws) ==========================

## Stamp a launch ticket for one upward burst. `speed` is the throw's
## vertical speed: refused above LAUNCH_SPEED_CEILING so no caller can
## legalize an absurd velocity. Returns whether the ticket was granted.
func grant_launch_grace(player_id: String, speed: float = 32.0, duration: float = LAUNCH_GRACE_SECONDS) -> bool:
	if speed <= 0.0 or speed > LAUNCH_SPEED_CEILING:
		return false
	_launch_grants[player_id] = Time.get_ticks_msec() + int(duration * 1000.0)
	return true


## Is a launch ticket live for this player? Expired entries are pruned
## on read so the book never grows.
func _launch_ticket_live(player_id: String) -> bool:
	var until: int = int(_launch_grants.get(player_id, 0))
	if until == 0:
		return false
	if Time.get_ticks_msec() > until:
		_launch_grants.erase(player_id)
		return false
	return true


## Public read (probe/UI seam): does this body currently ride a
## launch ticket?
func has_launch_ticket(player_id: String) -> bool:
	return _launch_ticket_live(player_id)


## == Aquatic limits + dive tickets (S14.3) ==================================

## The aquatic limit book: per-body swim maxima, stamped by the body
## when it binds the swim movement profile (mirrors set_movement_limits
## but sourced from movement_swim.tres -- a swimmer's hard limits are
## the swim maxima, NOT the humanoid's).
var _aquatic_limits: Dictionary = {}   # body_id -> {max_speed, max_dive, max_fall}

## Current-drift exemption book: per-body current vector at the last
## stamp. Currents move bodies PASSIVELY (server-side truth from the
## OceanVolume declaration); the horizontal validator forgives drift
## up to this stamped vector while it is live (a swimmer fighting a
## current is legal displacement, not a speed hack).
var _current_drift: Dictionary = {}    # body_id -> Vector3 (m/s)

## Dive tickets (prd sec 6: "grant_vector_grace with a NEGATIVE speed
## legalizes the entry plunge -- falling off a boat at sail speed;
## horizontal stays hard-checked"). Same ticket discipline as the
## launcher's grant: speed ceiling, expiry, prune-on-read.
const DIVE_SPEED_CEILING: float = 30.0
const DIVE_GRACE_SECONDS: float = 3.0
var _dive_grants: Dictionary = {}      # body_id -> expiry (msec)


## Stamp the aquatic limits for a body from its swim profile. Speeds
## are the swim maxima x the same multipliers the humanoid stamping
## uses, so the validator's horizontal check stays one code path.
func set_aquatic_limits(player_id: String, swim_speed: float, dive_speed: float, max_fall: float) -> void:
	_aquatic_limits[player_id] = {
		"max_speed": maxf(swim_speed, 1.0) * SPEED_LIMIT_MULTIPLIER,
		"max_dive": maxf(dive_speed, 1.0),
		"max_fall": maxf(max_fall, 1.0),
	}


## Stamp the hard limits for a body from a MovementProfile by id --
## the mount/vehicle stamping path (RideService.summon feeds the
## mount's resolved profile). ONE derivation: _limits_from_profile
## owns the multipliers, exactly like the humanoid stamping path.
## Returns false when the profile is unknown (the caller keeps its
## previous limits).
func set_profile_limits(player_id: String, profile_id: String) -> bool:
	var profile = null
	if _r_dataservice():
		profile = _r_dataservice().get_movement_profile(profile_id)
	if profile == null:
		return false
	var lim: Dictionary = _limits_from_profile(profile)
	set_movement_limits(player_id, float(lim["max_speed"]), float(lim["max_jump"]), float(lim["max_fall"]))
	return true


## Stamp the current a body is floating in (server truth from
## OceanService.current_at). While stamped, the horizontal validator
## forgives displacement along the current vector -- not across it.
func set_current_drift(player_id: String, current: Vector3) -> void:
	if current == Vector3.ZERO:
		_current_drift.erase(player_id)
	else:
		_current_drift[player_id] = current


## Stamp a dive ticket: legalizes the DOWNWARD plunge after a boat
## fall / dive entry (negative vertical beyond the swim terminal).
## Refused above the ceiling (no caller can legalize an absurd dive).
func grant_dive_grace(player_id: String, speed: float = 18.0, duration: float = DIVE_GRACE_SECONDS) -> bool:
	if speed <= 0.0 or speed > DIVE_SPEED_CEILING:
		return false
	_dive_grants[player_id] = Time.get_ticks_msec() + int(duration * 1000.0)
	return true


func _dive_ticket_live(player_id: String) -> bool:
	var until: int = int(_dive_grants.get(player_id, 0))
	if until == 0:
		return false
	if Time.get_ticks_msec() > until:
		_dive_grants.erase(player_id)
		return false
	return true


func has_dive_ticket(player_id: String) -> bool:
	return _dive_ticket_live(player_id)


## Is this horizontal velocity legal under a stamped current? The
## drift exemption forgives displacement ALONG the stamped vector:
## resolve the body's horizontal velocity onto the current direction;
## the parallel component is passive water, the perpendicular
## component is the swimmer's own effort and stays hard-checked.
func _legal_under_current(player_id: String, velocity: Vector3, max_speed: float) -> bool:
	if not _current_drift.has(player_id):
		return false
	var drift: Vector3 = _current_drift[player_id]
	var dir := Vector2(drift.x, drift.z)
	if dir.length() < 0.001:
		return false
	dir = dir.normalized()
	var v := Vector2(velocity.x, velocity.z)
	var parallel: float = v.dot(dir)
	if parallel <= 0.0:
		return false  # moving against or across the current: no forgiveness
	# Perpendicular (the swimmer's own effort) must be within limits.
	var perp: Vector2 = v - dir * parallel
	return perp.length() <= max_speed


## == Movement hard limits (Movement Design System) ==========================

## Stamp the hard limits for a player from their MovementProfile. Called
## by the player body at spawn (GlobeWorldPlayer._call_deferred_stamp) and
## available to any authoritative spawner (enemies/mounts use their own).
## Values are the LIMITS (legal max x multipliers), not the feel values.
func set_movement_limits(player_id: String, max_speed: float, max_jump: float, max_fall: float, max_glide_speed: float = GLIDE_MAX_SPEED, max_glide_fall: float = GLIDE_MAX_FALL) -> void:
	_movement_limits[player_id] = {
		"max_speed": maxf(max_speed, 1.0),
		"max_jump": maxf(max_jump, 1.0),
		"max_fall": maxf(max_fall, 10.0),
		"max_glide_speed": maxf(max_glide_speed, 1.0),
		"max_glide_fall": maxf(max_glide_fall, 1.0),
		"gliding": false,
	}


## Wing deployed/stowed. While true, get_movement_limits swaps the
## speed/fall maxima for the glide bounds (BotW-style flight rules).
func set_glide_active(player_id: String, gliding: bool) -> void:
	if _movement_limits.has(player_id):
		_movement_limits[player_id]["gliding"] = gliding

## Resolve the hard limits for a player. Falls back to the standard
## humanoid profile bounds when nothing was stamped (_r_dataservice() may be
## absent in tool contexts; the constants then stand alone).
func get_movement_limits(player_id: String) -> Dictionary:
	if _movement_limits.has(player_id):
		var limits: Dictionary = _movement_limits[player_id]
		if bool(limits.get("gliding", false)):
			return {
				"max_speed": limits["max_glide_speed"],
				"max_jump": limits["max_jump"],
				"max_fall": limits["max_glide_fall"],
			}
		return limits
	var fallback := {"max_speed": 25.0, "max_jump": 25.0, "max_fall": 110.0, "max_glide_speed": GLIDE_MAX_SPEED, "max_glide_fall": GLIDE_MAX_FALL, "gliding": false}
	if _r_dataservice():
		var profile = _r_dataservice().get_movement_profile("movement_standard")
		if profile != null:
			fallback = _limits_from_profile(profile)
	return fallback


## Profile -> limit dictionary (single place so stamping and fallback
## agree).
func _limits_from_profile(profile) -> Dictionary:
	var fastest_legal: float = maxf(profile.sprint_speed, profile.walk_speed * 1.9)  # 1.9 = slide entry peak
	return {
		"max_speed": fastest_legal * SPEED_LIMIT_MULTIPLIER,
		"max_jump": profile.jump_force * JUMP_LIMIT_MULTIPLIER,
		"max_fall": profile.terminal_fall_speed * FALL_LIMIT_MULTIPLIER,
	}


## Feed one frame of movement telemetry from an authoritative mover
## (the player body's _physics_process). Returns true when the sample
## (or a sustained streak of samples) violates a hard limit -- callers
## may use the return to clamp velocity server-side.
##
## Detection logic:
##   - horizontal speed  > max_speed  -> speed_hack streak
##   - upward velocity   > max_jump   -> jump_power streak (launch hack)
##   - downward velocity > max_fall   -> fast-fall streak (tunneling)
##   - |vy| > VERTICAL_HARD_CLAMP     -> instant report (absurd)
## Streaks report ONCE at SUSTAINED_FRAME_LIMIT frames, then every
## further multiple (escalating count for AutoResponseService).
func validate_movement(player_id: String, position: Vector3, velocity: Vector3, delta: float) -> bool:
	if delta <= 0.0 or _exempt_players.has(player_id):
		return false
	if not _player_profiles.has(player_id):
		register_player(player_id)
	var profile: PlayerProfile = _player_profiles[player_id]
	var limits := get_movement_limits(player_id)
	# Aquatic stamp overrides the land maxima while the body swims
	# (set_aquatic_limits stamped the swim maxima -- a swimming body
	# is judged by the swim profile, not the humanoid's).
	var aquatic: Dictionary = _aquatic_limits.get(player_id, {})
	if not aquatic.is_empty():
		limits["max_speed"] = aquatic["max_speed"]
		limits["max_fall"] = aquatic["max_fall"]

	# Telemetry feeds the statistical bot checks too (path repetition,
	# action rates) -- same data, one recorder.
	if position != Vector3.ZERO:
		profile.last_position = position
		profile.movement_paths.append({"pos": position, "time": Time.get_ticks_msec()})

	var horizontal := Vector2(velocity.x, velocity.z).length()
	# The current exemption: displacement ALONG the stamped current is
	# passive water (server truth), not the swimmer's effort. Across
	# the current, the swimmer's own effort stays hard-checked.
	var over_speed: bool = horizontal > float(limits["max_speed"]) \
		and not _legal_under_current(player_id, velocity, float(limits["max_speed"]))
	# A live launch ticket forgives ONLY the upward vector (launcher
	# ride / bout throw); horizontal and absurd-vertical checks still run.
	var launch_ticket: bool = velocity.y > 0.0 and _launch_ticket_live(player_id)
	# A live dive ticket forgives ONLY the downward plunge (boat-fall
	# entry); horizontal, upward, and absurd checks still run.
	var over_fall: bool
	if velocity.y < -float(limits["max_fall"]):
		over_fall = not (velocity.y < 0.0 and _dive_ticket_live(player_id))
	else:
		over_fall = false
	var over_launch: bool = velocity.y > float(limits["max_jump"]) and not launch_ticket
	var absurd_vertical: bool = absf(velocity.y) > VERTICAL_HARD_CLAMP

	if over_speed or over_launch or over_fall or absurd_vertical:
		profile.speed_violation_streak += 1
		# Escalating reports: first at the streak threshold, then every
		# further SUSTAINED_FRAME_LIMIT frames (count keeps rising so
		# AutoResponseService's confirmation threshold accumulates).
		if profile.speed_violation_streak % SUSTAINED_FRAME_LIMIT == 0:
			var details := {
				"horizontal_speed": horizontal,
				"max_speed": limits["max_speed"],
				"vertical_speed": velocity.y,
				"max_jump": limits["max_jump"],
				"max_fall": limits["max_fall"],
				"streak_frames": profile.speed_violation_streak,
				"sustained_seconds": profile.speed_violation_streak * delta,
				"position": {"x": position.x, "y": position.y, "z": position.z},
			}
			if over_speed:
				details["vector"] = "horizontal"
			elif over_launch:
				details["vector"] = "launch"
			elif over_fall:
				details["vector"] = "fast_fall"
			else:
				details["vector"] = "absurd_vertical"
			_suspicion_scores[player_id] = clampf(_suspicion_scores.get(player_id, 0.0) + 0.15, 0.0, 1.0)
			_persist_suspicion(player_id)
			_r_gamelog().warn("AntiCheatService: %s movement violation (%s) streak=%d %.1f m/s" % [player_id, details["vector"], profile.speed_violation_streak, horizontal])
			cheat_detected.emit(player_id, "speed_hack", 0.6 + 0.1 * float(profile.speed_violation_streak / SUSTAINED_FRAME_LIMIT), details)
			return true
	else:
		profile.speed_violation_streak = 0
	return false


## Whether a player's movement is exempt from hard-limit checks (GM
## characters fly/teleport by design).
func is_exempt(player_id: String) -> bool:
	return _exempt_players.has(player_id)

var _exempt_players: Dictionary = {}  # player_id -> true (GM bypass)

func set_movement_exempt(player_id: String, exempt: bool) -> void:
	if exempt:
		_exempt_players[player_id] = true
	else:
		_exempt_players.erase(player_id)

## Record an action with timing
func record_action(player_id: String, action_type: String, position: Vector3 = Vector3.ZERO,
					response_time_ms: int = -1) -> void:
	if not _player_profiles.has(player_id):
		register_player(player_id)

	var profile: PlayerProfile = _player_profiles[player_id]
	var now := Time.get_ticks_msec()

	profile.action_timestamps.append(now)
	profile.last_action_time = now

	if position != Vector3.ZERO:
		profile.last_position = position
		profile.movement_paths.append({
			"pos": position,
			"time": now
		})

	if response_time_ms >= 0:
		profile.response_times.append(response_time_ms)

	# Periodic analysis
	if profile.action_timestamps.size() % 50 == 0:
		_analyze_player(player_id)

## Record idle period
func record_idle(player_id: String, duration_ms: int) -> void:
	if not _player_profiles.has(player_id):
		return

	var profile: PlayerProfile = _player_profiles[player_id]
	var now := Time.get_ticks_msec()
	profile.idle_periods.append({
		"start": now - duration_ms,
		"end": now,
		"duration": duration_ms
	})

## Analyze player for suspicious patterns
func _analyze_player(player_id: String) -> void:
	var profile: PlayerProfile = _player_profiles.get(player_id)
	if not profile:
		return

	var suspicion := 0.0
	var evidence: Dictionary = {}

	# Agent players get a "fairness pass" for some patterns
	var agent_penalty_modifier: float = 0.5 if profile.is_agent else 1.0

	# Check 1: Perfect timing detection (macro/keyboard)
	suspicion += _check_perfect_timing(profile) * agent_penalty_modifier
	if suspicion > 0:
		evidence["perfect_timing"] = true

	# Check 2: Movement prediction (bot pathing)
	suspicion += _check_movement_prediction(profile) * agent_penalty_modifier
	if suspicion > 0:
		evidence["predictable_movement"] = true

	# Check 3: Response time variance (humans are inconsistent)
	suspicion += _check_response_variance(profile) * agent_penalty_modifier
	if suspicion > 0:
		evidence["consistent_response"] = true

	# Check 4: Idle patterns (humans take breaks)
	suspicion += _check_idle_patterns(profile) * agent_penalty_modifier
	if suspicion > 0:
		evidence["no_idle_time"] = true

	# Check 5: Action rate (bots are consistent)
	suspicion += _check_action_rate(profile) * agent_penalty_modifier
	if suspicion > 0:
		evidence["consistent_action_rate"] = true

	# Update suspicion score
	_suspicion_scores[player_id] = clamp(_suspicion_scores[player_id] + suspicion * 0.1, 0.0, 1.0)
	_persist_suspicion(player_id)

	if suspicion > 0.3:
		cheat_detected.emit(player_id, "pattern_anomaly", suspicion, evidence)

	if _suspicion_scores[player_id] > 0.8:
		_flag_player(player_id, "high_suspicion")
	elif _suspicion_scores[player_id] > 0.5:
		_flag_player(player_id, "moderate_suspicion")

## Check for perfect timing (indicates macro)
func _check_perfect_timing(profile: PlayerProfile) -> float:
	if profile.action_timestamps.size() < 10:
		return 0.0

	# Calculate variance in time between actions
	var intervals: Array = []
	for i in range(1, min(profile.action_timestamps.size(), 20)):
		intervals.append(profile.action_timestamps[i] - profile.action_timestamps[i-1])

	if intervals.is_empty():
		return 0.0

	# Calculate variance
	var mean := 0.0
	for t in intervals:
		mean += t
	mean /= intervals.size()

	var variance := 0.0
	for t in intervals:
		var diff: float = float(t) - float(mean)
		variance += diff * diff
	variance /= intervals.size()

	# Low variance = suspicious
	var std_dev := sqrt(variance)
	var coefficient_of_variation: float = std_dev / mean if mean > 0 else 1.0

	if coefficient_of_variation < PERFECT_TIMING_THRESHOLD:
		return 0.5  # Very suspicious

	return 0.0

## Check for predictable movement (indicates bot)
func _check_movement_prediction(profile: PlayerProfile) -> float:
	if profile.movement_paths.size() < 20:
		return 0.0

	# Check if same path is repeated
	var path_count: Dictionary = {}
	for path_data in profile.movement_paths:
		var pos: Vector3 = path_data["pos"]
		var key := "%d,%d,%d" % [int(pos.x), int(pos.y), int(pos.z)]
		path_count[key] = path_count.get(key, 0) + 1

	var total := profile.movement_paths.size()
	var max_repetition := 0.0

	for key in path_count:
		max_repetition = max(max_repetition, float(path_count[key]) / float(total))

	if max_repetition > PATH_REPETITION_THRESHOLD:
		return 0.6  # Very suspicious - same spot repeatedly

	return 0.0

## Check response time variance (bots are consistent)
func _check_response_variance(profile: PlayerProfile) -> float:
	if profile.response_times.size() < 10:
		return 0.0

	var mean := 0.0
	for t in profile.response_times:
		mean += t
	mean /= profile.response_times.size()

	var variance := 0.0
	for t in profile.response_times:
		var diff: float = float(t) - float(mean)
		variance += diff * diff
	variance /= profile.response_times.size()

	var std_dev := sqrt(variance)
	var coefficient_of_variation: float = std_dev / mean if mean > 0 else 1.0

	# Humans have high variance, bots have low
	if coefficient_of_variation < RESPONSE_TIME_VARIANCE_HUMAN:
		return 0.3

	return 0.0

## Check idle patterns (humans idle)
func _check_idle_patterns(profile: PlayerProfile) -> float:
	var session_duration_ms := Time.get_ticks_msec() - profile.session_start
	var session_hours := session_duration_ms / 3600000.0

	# Expected idle: at least one break per hour
	var expected_breaks := session_hours * BREAK_FREQUENCY_HUMAN
	var actual_breaks := float(profile.idle_periods.size())

	if actual_breaks < expected_breaks * 0.5:  # Less than half expected
		return 0.2

	return 0.0

## Check action rate consistency (bots are mechanical)
func _check_action_rate(profile: PlayerProfile) -> float:
	var session_duration_ms := Time.get_ticks_msec() - profile.session_start
	if session_duration_ms < 60000:  # Need at least 1 minute
		return 0.0

	var actions_per_minute := float(profile.action_timestamps.size()) / (session_duration_ms / 60000.0)

	# Humans average 10-60 actions per minute depending on playstyle
	# Bots often have very consistent rates
	if actions_per_minute > 100:
		return 0.4  # Extremely high

	return 0.0

## Flag a player for review
func _flag_player(player_id: String, flag_type: String) -> void:
	player_flagged.emit(player_id, flag_type)
	_r_gamelog().warn("AntiCheatService: Player %s flagged: %s" % [player_id, flag_type])

## Check if player is banned
func is_banned(player_id: String) -> bool:
	return _banned_players.has(player_id)

## Ban a player
func ban_player(player_id: String, reason: String) -> void:
	_banned_players[player_id] = {
		"reason": reason,
		"timestamp": Time.get_ticks_msec()
	}
	player_banned.emit(player_id, reason)
	_r_gamelog().info("AntiCheatService: Player %s banned: %s" % [player_id, reason])

## Unban a player
func unban_player(player_id: String) -> void:
	_banned_players.erase(player_id)
	_suspicion_scores[player_id] = 0.0
	player_unbanned.emit(player_id)
	_r_gamelog().info("AntiCheatService: Player %s unbanned" % player_id)

## Get suspicion score
func get_suspicion(player_id: String) -> float:
	return _suspicion_scores.get(player_id, 0.0)

## Get player report
func get_player_report(player_id: String) -> Dictionary:
	var profile: PlayerProfile = _player_profiles.get(player_id)
	if not profile:
		return {}

	return {
		"player_id": player_id,
		"is_agent": profile.is_agent,
		"suspicion_score": get_suspicion(player_id),
		"is_banned": is_banned(player_id),
		"action_count": profile.action_timestamps.size(),
		"session_duration_hours": (Time.get_ticks_msec() - profile.session_start) / 3600000.0,
		"idle_periods": profile.idle_periods.size(),
		"avg_response_time_ms": _calculate_avg_response_time(profile)
	}

func _calculate_avg_response_time(profile: PlayerProfile) -> float:
	if profile.response_times.is_empty():
		return -1.0
	var sum := 0.0
	for t in profile.response_times:
		sum += t
	return sum / profile.response_times.size()

## Periodic cleanup
func _process(delta: float) -> void:
	# Clean up old movement data (keep last 5 minutes)
	var cutoff := Time.get_ticks_msec() - 300000

	for player_id in _player_profiles:
		var profile: PlayerProfile = _player_profiles[player_id]
		profile.movement_paths = profile.movement_paths.filter(func(p): return p["time"] > cutoff)

## == Persistence ============================================================

func _load_state() -> void:
	var store := DictStore.new()
	_suspicion_scores = {}
	_banned_players = {}
	var keys: Array = store.all_keys()
	var suspicion_keys: Array = []
	var ban_keys: Array = []
	for key in keys:
		if key.begins_with(_kv_prefix + "suspicion:"):
			suspicion_keys.append(key)
		elif key.begins_with(_kv_prefix + "ban:"):
			ban_keys.append(key)

	if not suspicion_keys.is_empty():
		var suspicion_results: Dictionary = store.get_many(suspicion_keys)
		for key in suspicion_keys:
			var player_id = key.substr(_kv_prefix.length() + 10)
			_suspicion_scores[player_id] = suspicion_results.get(key, {})

	if not ban_keys.is_empty():
		var ban_results: Dictionary = store.get_many(ban_keys)
		for key in ban_keys:
			var player_id = key.substr(_kv_prefix.length() + 4)
			_banned_players[player_id] = ban_results.get(key, {})

func _persist_suspicion(player_id: String) -> void:
	var store := DictStore.new()
	if _suspicion_scores.has(player_id):
		store.set_kv(_kv_prefix + "suspicion:" + player_id, {"score": _suspicion_scores[player_id]})
	else:
		store.erase(_kv_prefix + "suspicion:" + player_id)

func _persist_ban(player_id: String) -> void:
	var store := DictStore.new()
	if _banned_players.has(player_id):
		store.set_kv(_kv_prefix + "ban:" + player_id, _banned_players[player_id])
	else:
		store.erase(_kv_prefix + "ban:" + player_id)


func persist_all() -> void:
	var store := DictStore.new()
	var entries: Dictionary = {}
	for player_id in _suspicion_scores.keys():
		entries[_kv_prefix + "suspicion:" + player_id] = {"score": _suspicion_scores[player_id]}
	for player_id in _banned_players.keys():
		entries[_kv_prefix + "ban:" + player_id] = _banned_players[player_id]
	if not entries.is_empty():
		store.set_batch(entries)
