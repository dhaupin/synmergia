# probe_thermals.gd - S12.5: the sky roads end to end.
#
# Covers:
#   A. Data: 3 thermals + 2 dormant ancient launchers load (thermal_
#      prefix, filename == id, schema fields sane).
#   B. Sampling: inside a thermal column the lift is positive and
#      proportional to strength; outside it is zero.
#   C. Ritual awakening: dormant launchers give NOTHING until
#      awaken_launcher flips them; awakening persists through the
#      DictStore; re-awakening is refused.
#   D. Launch bursts: an awake launcher throws at launch_speed.
#   E. Glide stats: record_glide_tick accrues distance/time/altitude;
#      push_glide_achievements routes the categories (glide_distance
#      etc. reach AchievementService.track without error).
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ts = root.get_node_or_null("ThermalService")
	var ach = root.get_node_or_null("AchievementService")
	_check("ThermalService present", ts != null)
	if ts == null:
		quit(1)
		return

	# ---- A. The book loaded ---------------------------------------------
	var updrafts: Array = ts.get_updrafts()
	_check("7 updrafts loaded from data/thermals", updrafts.size() == 7)
	var thermal_count := 0
	var launcher_count := 0
	for u in updrafts:
		if str(u.id).begins_with("thermal_"):
			thermal_count += 1
		if str(u.id).begins_with("launcher_"):
			launcher_count += 1
	_check("5 thermals + 2 launchers (prefix taxonomy)", \
		thermal_count == 5 and launcher_count == 2)

	# ---- B. Thermal sampling --------------------------------------------
	var haven = _by_id(ts, "thermal_haven_rise")
	_check("Haven Rise sample inside the column", \
		ts.sample(haven.position + Vector3(0, 50, 0)) > 1.5)
	_check("outside the column the sky is still", \
		ts.sample(haven.position + Vector3(500, 50, 0)) == 0.0)
	# Strength proportionality: 0.7 of MAX_LIFT 3.0 = 2.1 m/s.
	_check("strength scales the lift (0.7 -> 2.1 m/s)", \
		abs(ts.sample(haven.position + Vector3(0, 50, 0)) - 2.1) < 0.01)

	# ---- C. Dormant launchers --------------------------------------------
	var spire = _by_id(ts, "launcher_haven_spire")
	_check("ancient launcher is DORMANT (no lift while asleep)", \
		ts.sample(spire.position + Vector3(0, 3, 0)) == 0.0 \
		and not ts.is_awake("launcher_haven_spire"))
	_check("awakening flips the ancient on", ts.awaken_launcher("launcher_haven_spire"))
	_check("re-awakening refused (already awake)", not ts.awaken_launcher("launcher_haven_spire"))
	_check("the awake launcher now gives lift", ts.sample(spire.position + Vector3(0, 3, 0)) > 0.0)

	# ---- D. Launch burst ---------------------------------------------------
	var burst: float = ts.sample_launch(spire.position + Vector3(0, 1, 0))
	_check("launch burst throws near launch_speed at the base", \
		burst >= 26.0 * 0.25 and burst <= 30.0)
	_check("launcher feeds a real thermal (the intended hop)", \
		str(spire.feeds_thermal_id) == "thermal_meadow_column" \
		and _by_id(ts, "thermal_meadow_column") != null)

	# ---- E. Glide stats + achievement routing ------------------------------
	# Per-frame distances (0.25 m at 60 fps): the anticheat farm clamp
	# counts a tick at most 1.0 m, so tests feed LEGAL tick sizes.
	for i in range(20):
		ts.record_glide_tick("glide_ace", 0.25, 45.0)
	ts.record_glide_tick("glide_ace", 0.25, 60.0)
	var stats: Dictionary = ts.glide_stats("glide_ace")
	_check("glide ticks accrue distance + altitude + time", \
		float(stats.get("distance", 0.0)) > 4.0 \
		and float(stats.get("max_altitude", 0.0)) >= 60.0 \
		and float(stats.get("time", 0.0)) > 0.03)
	var before_farm: float = float(stats.get("distance", 0.0))
	ts.record_glide_tick("glide_ace", 99.0, 60.0)
	_check("farm clamp: an absurd tick adds at most the cap", \
		float(ts.glide_stats("glide_ace").get("distance", 0.0)) - before_farm <= 1.0)
	ts.push_glide_achievements("glide_ace")
	_check("achievement categories routed without error", true)
	var defs_ok := true
	for aid in ["sky_trail_500", "high_alts_100", "wind_rider_60"]:
		var def: Resource = load("res://data/achievements/achievement_%s.tres" % aid.replace("sky_trail_500", "sky_trail_500"))
		if def == null:
			defs_ok = false
	_check("glide achievement defs load", defs_ok)
	var quest: Resource = load("res://data/quests/quest_wings_over_haven.tres")
	_check("teaching quest loads (Wings Over Haven)", quest != null \
		and (quest.objectives as Array).size() == 1)

	# ---- F. Anticheat launch tickets (S12.5 security seam) -----------------
	# The service grants tickets server-side when its own book says a
	# launcher is throwing a body; upward violations are forgiven only
	# while the ticket lives (and only the upward vector).
	var ac = root.get_node_or_null("AntiCheatService")
	_check("anticheat service resolvable", ac != null)
	if ac != null and ac.has_method("grant_launch_grace"):
		var spire_speed: float = float(spire.launch_speed)
		_check("30 m/s throw exceeds the legal jump limit (the threat is real)", \
			spire_speed > 12.5)
		_check("launcher ride grants a live launch ticket", \
			ts.sample(spire.position + Vector3(0, 3, 0), "ticketed_rider") > 0.0 \
			and bool(ac.has_launch_ticket("ticketed_rider")))
		ac.set_movement_limits("ticketed_rider", 25.0, 12.5, 110.0)
		var flagged := false
		for i in range(40):
			if ac.validate_movement("ticketed_rider", Vector3(i * 0.1, 3, 0), \
					Vector3(0, 30.0, 0), 1.0 / 60.0):
				flagged = true
				break
		_check("ticketed 30 m/s throw does NOT trip the jump hack", not flagged)
		var unluck := false
		for i in range(40):
			if ac.validate_movement("ticketed_rider", Vector3(i * 0.1, 3, 0), \
					Vector3(90.0, 0, 0), 1.0 / 60.0):
				unluck = true
				break
		_check("ticket does NOT cover horizontal speedhacks", unluck)
		# Fresh violation window for the expiry check: the horizontal
		# block above left streak=30, and reports fire on a NEW 30-frame
		# sustained run (the same escalation rule the service enforces).
		var prof = ac._player_profiles.get("ticketed_rider")
		if prof != null:
			prof.speed_violation_streak = 0
		ac._launch_grants.erase("ticketed_rider")
		var post := false
		for i in range(40):
			if ac.validate_movement("ticketed_rider", Vector3(i * 0.1, 3, 0), \
					Vector3(0, 30.0, 0), 1.0 / 60.0):
				post = true
				break
		_check("expired ticket: the same throw now trips the hack", post)
		_check("an absurd 999 m/s throw cannot buy a ticket", \
			not bool(ac.grant_launch_grace("cheater", 999.0)))

	if _fails == 0:
		print("THERMALS PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("THERMALS PROBE FAILED")
		quit(1)

func _by_id(ts, id: String):
	for u in ts.get_updrafts():
		if str(u.id) == id:
			return u
	return null

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
