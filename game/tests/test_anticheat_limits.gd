extends SceneTree

## AntiCheatService movement hard limits: limits resolve from stamped
## MovementProfile bounds, sustained over-limit streaks report through
## cheat_detected (-> SecurityService -> AutoResponseService), legal
## play never trips, streaks reset on recovery, GMs pass exempt.
## Run: godot --headless --path . --script res://tests/test_anticheat_limits.gd
##
## NOTE: _initialize(), not _init() -- autoloads attach after _init.

const FPS_60 := 1.0 / 60.0

var _acs = null
var _findings: Array = []


func _initialize() -> void:
	var ok := true
	_acs = root.get_node_or_null("AntiCheatService")
	if _acs == null:
		push_error("FAIL: AntiCheatService autoload missing")
		quit(1)
		return
	_acs.cheat_detected.connect(_on_finding)

	# 1. Limits resolve from the standard profile when nothing stamped.
	var limits: Dictionary = _acs.get_movement_limits("ghost_player")
	var expected_speed: float = 10.0 * _acs.SPEED_LIMIT_MULTIPLIER  # standard sprint=10
	var expected_jump: float = 10.0 * _acs.JUMP_LIMIT_MULTIPLIER    # standard jump=10
	if not is_equal_approx(float(limits["max_speed"]), expected_speed):
		push_error("FAIL: fallback max_speed %s != %s" % [limits["max_speed"], expected_speed])
		ok = false
	else:
		print("[OK] fallback limits resolve from movement_standard (%.0f m/s)" % float(limits["max_speed"]))

	# 2. Stamping overrides the fallback (quadruped sprint=13.5).
	_acs.set_movement_limits("wolf_rider", 13.5 * 2.5, 5.0 * 2.5, 55.0 * 2.0)
	var stamped: Dictionary = _acs.get_movement_limits("wolf_rider")
	if not is_equal_approx(float(stamped["max_speed"]), 33.75):
		push_error("FAIL: stamped max_speed %s != 33.75" % stamped["max_speed"])
		ok = false
	else:
		print("[OK] stamped limits override the profile fallback")

	# 3. Legal play NEVER trips: 3 seconds of sprinting, sliding, jump
	#    launch, and terminal fall, frame by frame at 60fps.
	_acs.set_movement_limits("legal_pete", 25.0, 25.0, 110.0)
	var legal := true
	for i in 180:
		var v := Vector3.ZERO
		if i < 120:
			v = Vector3(9.5, 0, 9.5)   # slide peak (13.4 m/s diag < 25)
		elif i < 130:
			v = Vector3(0, 10.0, 0)    # jump launch == legal jump_force
		elif i < 150:
			v = Vector3(0, -55.0, 0)   # terminal fall == profile cap
		if _acs.validate_movement("legal_pete", Vector3(i * 0.1, 0, 0), v, FPS_60):
			legal = false
	if legal:
		print("[OK] 3s of legal sprint/slide/jump/fall = zero violations")
	else:
		push_error("FAIL: legal movement flagged")
		ok = false

	# 4. Sustained speedhack: 2x limit for 1s -> exactly one report at
	#    frame 30, count escalates at 60.
	var reported := 0
	for i in 60:
		if _acs.validate_movement("speedy", Vector3(50.0 * i * FPS_60, 0, 0), Vector3(50.0, 0, 0), FPS_60):
			reported += 1
	if reported == 2:
		print("[OK] sustained speedhack reported at frame 30 and 60 (escalating)")
	else:
		push_error("FAIL: expected 2 reports over 60 over-limit frames, got %d" % reported)
		ok = false

	# 5. Single-frame spikes never report (lag, not hacks).
	var spikes := 0
	for i in 10:
		if _acs.validate_movement("laggy_larry", Vector3(i * 0.05, 0, 0), Vector3(90.0, 0, 0), FPS_60):
			spikes += 1
		if _acs.validate_movement("laggy_larry", Vector3(i * 0.05, 0, 0), Vector3(5.0, 0, 0), FPS_60):
			spikes += 1
	if spikes == 0:
		print("[OK] alternating spike/clean frames (lag pattern) = zero reports")
	else:
		push_error("FAIL: single-frame spikes reported %d times" % spikes)
		ok = false

	# 6. Launch + fast-fall vectors are separately detected.
	var launch := 0
	for i in 30:
		if _acs.validate_movement("jump_hacker", Vector3(0, 0, 0), Vector3(0, 60.0, 0), FPS_60):
			launch += 1
	var fall := 0
	for i in 30:
		if _acs.validate_movement("fall_hacker", Vector3(0, 0, 0), Vector3(0, -250.0, 0), FPS_60):
			fall += 1
	if launch == 1 and fall == 1:
		print("[OK] launch (+60 vy) and fast-fall (-250 vy) both detected")
	else:
		push_error("FAIL: launch=%d fall=%d" % [launch, fall])
		ok = false

	# 7. GM exemption passes through untouched.
	_acs.set_movement_exempt("gm_wizard", true)
	var gm_flagged := false
	for i in 40:
		gm_flagged = _acs.validate_movement("gm_wizard", Vector3(0, 0, 0), Vector3(999.0, 0, 0), FPS_60) or gm_flagged
	if not gm_flagged and _acs.is_exempt("gm_wizard"):
		print("[OK] GM exemption: 40 frames at 999 m/s pass silently")
		if _acs.get_suspicion("gm_wizard") != 0.0:
			push_error("FAIL: exempt player accrued suspicion")
			ok = false
	else:
		push_error("FAIL: GM was flagged")
		ok = false

	# 8. Findings emitted with evidence and reached this test through
	#    the cheat_detected signal (same signal SecurityService bridges).
	if _findings.size() >= 4:
		var ev: Dictionary = _findings[0]["evidence"]
		if ev.has("horizontal_speed") and ev.has("streak_frames") and _findings[0]["type"] == "speed_hack":
			print("[OK] %d findings carried speed_hack evidence (bridge target: SecurityService.report_anticheat_finding)" % _findings.size())
		else:
			push_error("FAIL: finding evidence incomplete: %s" % str(ev.keys()))
			ok = false
	else:
		push_error("FAIL: expected >=4 findings, got %d" % _findings.size())
		ok = false

	# 9. Unregister cleans everything.
	_acs.unregister_player("speedy")
	if not _acs._movement_limits.has("speedy"):
		print("[OK] unregister_player clears movement state")
	else:
		push_error("FAIL: movement state leaked after unregister")
		ok = false

	# == S14.3: the aquatic layer (swim maxima, current truth, dive
	#    tickets). Currents are SERVER TRUTH -- the validator forgives
	#    displacement ALONG the stamped vector only; across it, and
	#    every other vector, the swimmer's own effort is judged.

	# 10. The aquatic stamp overrides the land maxima while swimming.
	_acs.set_aquatic_limits("swim_legal", 3.4, 18.0, 3.0)
	var aqua: Dictionary = _acs._aquatic_limits["swim_legal"]
	if is_equal_approx(float(aqua["max_speed"]), 3.4 * _acs.SPEED_LIMIT_MULTIPLIER):
		print("[OK] aquatic stamp: swim maxima x the same multipliers (8.5 m/s)")
	else:
		push_error("FAIL: aquatic max_speed %s != 8.5" % aqua["max_speed"])
		ok = false
	var swim_ok := true
	for i in 40:
		if _acs.validate_movement("swim_legal", Vector3(i * 0.05, -1.0, 0), Vector3(8.0, 0, 0), FPS_60):
			swim_ok = false
	if swim_ok:
		print("[OK] a swimmer at 8.0 m/s is legal under the swim maxima")
	else:
		push_error("FAIL: legal swim speed flagged")
		ok = false
	var swim_hack := 0
	_acs.set_aquatic_limits("swim_hack", 3.4, 18.0, 3.0)
	for i in 35:
		if _acs.validate_movement("swim_hack", Vector3(i * 0.2, -1.0, 0), Vector3(20.0, 0, 0), FPS_60):
			swim_hack += 1
	if swim_hack == 1:
		print("[OK] 20 m/s in water is a speedhack (the swim maxima bind)")
	else:
		push_error("FAIL: expected 1 swim-speedhack report, got %d" % swim_hack)
		ok = false

	# 11. The current exemption: drift ALONG the stamped vector is
	#     passive water; across it the effort is hard-checked.
	_acs.set_aquatic_limits("drifter", 3.4, 18.0, 3.0)
	_acs.set_current_drift("drifter", Vector3(1, 0, 0) * 4.0)  # the shelf's current
	var drift_ok := true
	for i in 40:
		if _acs.validate_movement("drifter", Vector3(i * 0.17, -1.0, 0), Vector3(10.0, 0, 0), FPS_60):
			drift_ok = false
	if drift_ok:
		print("[OK] riding the current at 10 m/s (parallel, perp 0) = no violation")
	else:
		push_error("FAIL: current-parallel drift flagged")
		ok = false
	var cross := 0
	for i in 35:
		if _acs.validate_movement("drifter", Vector3(i * 0.2, -1.0, 0), Vector3(0, 0, 10.0), FPS_60):
			cross += 1
	if cross == 1:
		print("[OK] 10 m/s ACROSS the current is still a speedhack (perp hard-checked)")
	else:
		push_error("FAIL: expected 1 cross-current report, got %d" % cross)
		ok = false
	var upstream := 0
	for i in 35:
		if _acs.validate_movement("drifter", Vector3(-i * 0.2, -1.0, 0), Vector3(-10.0, 0, 0), FPS_60):
			upstream += 1
	if upstream == 1:
		print("[OK] swimming UPSTREAM at 10 m/s is the swimmer's own effort (flagged)")
	else:
		push_error("FAIL: expected 1 upstream report, got %d" % upstream)
		ok = false
	_acs.set_current_drift("drifter", Vector3.ZERO)
	var after_zero := 0
	for i in 35:
		if _acs.validate_movement("drifter", Vector3(i * 0.2, -1.0, 0), Vector3(10.0, 0, 0), FPS_60):
			after_zero += 1
	if after_zero == 1:
		print("[OK] a zero current erases the stamp (still water is judged again)")
	else:
		push_error("FAIL: expected 1 post-zero report, got %d" % after_zero)
		ok = false

	# 12. Dive tickets: the boat-fall plunge is forgiven DOWNWARD only.
	if _acs.grant_dive_grace("diver", 50.0) == false and not _acs.has_dive_ticket("diver"):
		print("[OK] a 50 m/s dive ticket is refused at the ceiling")
	else:
		push_error("FAIL: 50 m/s dive ticket granted")
		ok = false
	_acs.set_aquatic_limits("diver", 3.4, 18.0, 3.0)
	if _acs.grant_dive_grace("diver", 18.0) and _acs.has_dive_ticket("diver"):
		print("[OK] an 18 m/s dive ticket is granted")
	else:
		push_error("FAIL: legal dive ticket refused")
		ok = false
	var plunge_ok := true
	for i in 40:
		if _acs.validate_movement("diver", Vector3(0, -2.0 * float(i), 0), Vector3(0, -20.0, 0), FPS_60):
			plunge_ok = false
	if plunge_ok:
		print("[OK] the -20 m/s plunge past the swim terminal is forgiven by the ticket")
	else:
		push_error("FAIL: ticketed plunge flagged")
		ok = false
	var dive_h := 0
	for i in 35:
		if _acs.validate_movement("diver", Vector3(i * 0.2, -1.0, 0), Vector3(20.0, 0, 0), FPS_60):
			dive_h += 1
	if dive_h == 1:
		print("[OK] the dive ticket never forgives horizontal (still a speedhack)")
	else:
		push_error("FAIL: expected 1 horizontal report under ticket, got %d" % dive_h)
		ok = false

	# 13. Unregister clears the whole aquatic layer.
	_acs.set_aquatic_limits("aqua_full", 3.4, 18.0, 3.0)
	_acs.set_current_drift("aqua_full", Vector3(1, 0, 0) * 4.0)
	_acs.grant_dive_grace("aqua_full", 18.0)
	_acs.unregister_player("aqua_full")
	if not _acs._aquatic_limits.has("aqua_full") and not _acs._current_drift.has("aqua_full") and not _acs._dive_grants.has("aqua_full"):
		print("[OK] unregister clears aquatic limits, current drift, and dive grants")
	else:
		push_error("FAIL: aquatic book leaked after unregister")
		ok = false

	print("--- ANTICHEAT LIMITS TEST: ok=%s ---" % str(ok))
	quit(0 if ok else 1)


func _on_finding(player_id: String, cheat_type: String, confidence: float, evidence: Dictionary) -> void:
	_findings.append({"player": player_id, "type": cheat_type, "confidence": confidence, "evidence": evidence})
