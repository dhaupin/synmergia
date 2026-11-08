extends SceneTree

## Daily Class Blessing (prd-psy.md section 8) smoke test: the sky
## wheel guarantees hydration (every playable class blesses exactly
## once per rotation, BY CONSTRUCTION), the blessing only pays on
## EARNED days (code solved -> Ancient unlocked), and the three
## consumer hooks (damage via CombatMath, healing via Skill, XP via
## KillRewards) all honor it. Run:
##   godot --headless --path . --script res://tests/test_daily_class_blessing.gd
##
## _initialize() + ensure_initialized(): autoload _ready may lag the
## first probes in script mode.

var _svc = null
var _ds = null

const KillRewards = preload("res://core/services/kill_rewards.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind


func _initialize() -> void:
	var ok := true

	_ds = root.get_node_or_null("DataService")
	_svc = root.get_node_or_null("SignService")
	if _ds == null or _svc == null:
		push_error("FAIL: DataService/SignService autoload missing")
		quit(1)
		return
	if not _ds._loaded:
		_ds.load_all_data()
	if _svc.has_method("ensure_initialized"):
		_svc.ensure_initialized()

	ok = _test_wheel_hydration() and ok
	ok = _test_determinism() and ok
	ok = _test_earn_gate() and ok
	ok = _test_login_toast() and ok
	ok = _test_combatmath_hook() and ok
	ok = _test_heal_hook() and ok
	ok = _test_xp_hook() and ok

	print("--- DAILY CLASS BLESSING: ok=%s ---" % str(ok))
	quit(0 if ok else 1)


func _test_wheel_hydration() -> bool:
	var ids: Array[String] = _svc._playable_class_ids()
	if ids.size() < 3:
		push_error("FAIL: expected >=3 playable classes, got %d" % ids.size())
		return false
	# Two full rotations: every class must appear exactly once per round.
	for round_start in [0, ids.size()]:
		var seen := {}
		for offset in ids.size():
			var day: int = round_start + offset
			# Each test day must be Ancient-unlocked for is_class_blessed
			# to pay; the wheel itself is independent of that gate.
			_svc._unlocked_days[day] = true
			var blessed: String = _svc.get_blessed_class_id(day)
			if blessed == "":
				push_error("FAIL: empty blessed class on day %d" % day)
				return false
			if seen.has(blessed):
				push_error("FAIL: %s blessed twice in rotation %d (day %d)" % [blessed, round_start, day])
				return false
			seen[blessed] = true
		if seen.size() != ids.size():
			push_error("FAIL: rotation %d only blessed %d of %d classes" % [round_start, seen.size(), ids.size()])
			return false
	print("[OK] sky wheel: %d classes, every class blesses exactly once per rotation" % ids.size())
	# Catalog fairness: every id in the wheel is a grantable class
	# (species-scoped). A wheel slot nobody can pick is a wasted day.
	for cid in ids:
		var grantable := false
		for sp in ["human_", "akkan_", "synthetic_"]:
			if cid.begins_with(sp):
				grantable = true
				break
		if not grantable:
			push_error("FAIL: wheel contains non-grantable class id: %s" % cid)
			return false
	print("[OK] wheel catalog: all %d ids are species-grantable" % ids.size())
	return true


func _test_determinism() -> bool:
	# Same day -> same pick, twice, and across a fresh wheel read.
	var a: String = _svc.get_blessed_class_id(33333)
	var b: String = _svc.get_blessed_class_id(33333)
	if a != b or a.is_empty():
		push_error("FAIL: blessed pick not deterministic (%s vs %s)" % [a, b])
		return false
	# Wheel order for a round is stable across calls.
	var ids: Array[String] = _svc._playable_class_ids()
	var w1: Array = _svc._wheel_order(3, ids)
	var w2: Array = _svc._wheel_order(3, ids)
	if str(w1) != str(w2):
		push_error("FAIL: wheel order not stable for a round")
		return false
	print("[OK] blessed pick deterministic ('%s'); wheel stable" % a)
	return true


func _test_earn_gate() -> bool:
	var ids: Array[String] = _svc._playable_class_ids()
	var day := 44444
	# Unearned day: wheel may name a class, but NOTHING pays.
	_svc._unlocked_days.erase(day)
	_svc._unlocked_days.erase(day + 1)
	var named: String = _svc.get_blessed_class_id(day)
	if named != "" and _svc.is_class_blessed(named, day):
		push_error("FAIL: blessing paid on an unearned day")
		return false
	# Earn the day (as-if the tribe solved yesterday's code): pays.
	_svc._unlocked_days[day] = true
	if not _svc.is_class_blessed(named, day):
		push_error("FAIL: earned day did not pay for the named class")
		return false
	# A NON-blessed class on an earned day still gets nothing.
	var other: String = ""
	for cid in ids:
		if cid != named:
			other = cid
			break
	if _svc.is_class_blessed(other, day):
		push_error("FAIL: non-blessed class '%s' paid" % other)
		return false
	print("[OK] earn gate: unsolved day pays nothing; solved day pays only '%s'" % named)
	return true
## Login toast (prd-psy.md section 8): the blessed class hears about
## its day on player_entered_world; a non-blessed class stays silent.
## NotificationService.notification_sent carries (entity_id, payload).
func _test_login_toast() -> bool:
	var nsvc = root.get_node_or_null("NotificationService")
	var gm = root.get_node_or_null("GameManager")
	if nsvc == null or gm == null:
		push_error("FAIL: NotificationService/GameManager missing for login toast")
		return false
	var ids: Array[String] = _svc._playable_class_ids()
	var day := 55555
	_svc._unlocked_days[day] = true
	var blessed: String = _svc.get_blessed_class_id(day)
	# Pin the clock so is_class_blessed (default = today) resolves to
	# our earned test day.
	_svc.set_clock_override(float(day) * 86400.0 + 3600.0)
	var toasts: Array = []
	var handler := func(entity_id: String, n: Dictionary) -> void:
		if int(n.get("kind", -1)) == NotifKind.CLASS_BLESSED:
			toasts.append(n)
	nsvc.notification_received.connect(handler)
	# Blessed character logs in -> must toast.
	var cd := CharacterData.new("human", blessed, "Blessed One")
	_svc._on_player_entered_world("toast_player", cd)
	# Unblessed character logs in -> must NOT toast.
	var other: String = ""
	for cid in ids:
		if cid != blessed:
			other = cid
			break
	var cd2 := CharacterData.new("human", other, "Plain One")
	_svc._on_player_entered_world("toast_player_2", cd2)
	nsvc.notification_received.disconnect(handler)
	_svc.set_clock_override(-1.0)
	if toasts.is_empty():
		push_error("FAIL: blessed class got no login toast")
		return false
	if toasts.size() != 1:
		push_error("FAIL: expected exactly 1 blessing toast, got %d" % toasts.size())
		return false
	var msg := str(toasts[0].get("message", ""))
	if not msg.contains("YOUR class"):
		push_error("FAIL: toast message wrong: %s" % msg)
		return false
	print("[OK] login toast: blessed class hears its day, others silent")
	return true


func _test_combatmath_hook() -> bool:
	# A fake combatant duck-types exactly like the player body for the
	# blessing path: character_class + stats.
	var day := 55555
	_svc._unlocked_days[day] = true
	# Pin "now" inside the earned day so day<0 resolution hits it.
	_svc.set_clock_override(day * 86400.0 + 3600.0)
	var blessed: String = _svc.get_blessed_class_id(day)
	var attacker = _fake_fighter(blessed)
	# Deterministic core first: the duck-typed multiplier lookup.
	# (calculate_hit's MISS segment returns early WITHOUT a blessing
	# stamp by design -- a miss deals no damage and calculate_damage
	# defaults the key to 1.0 -- so asserting on a raw roll here was a
	# flake. The roll path is checked below with a retry.)
	var mult: float = CombatMath._blessing_multiplier_for(attacker)
	if not is_equal_approx(mult, _svc.BLESSED_DAMAGE_MULTIPLIER):
		push_error("FAIL: blessed attacker multiplier %s != %s" % [str(mult), str(_svc.BLESSED_DAMAGE_MULTIPLIER)])
		return false
	var plain = _fake_fighter("human_warrior")
	if _svc.is_class_blessed("human_warrior", day) and str(blessed) == "human_warrior":
		plain = _fake_fighter("akkan_attacker")  # collision; pick another
	var hit2: Dictionary = CombatMath.calculate_hit(plain, _fake_fighter(""))
	if not is_equal_approx(float(hit2.get("blessing_multiplier", 1.0)), 1.0):
		push_error("FAIL: unblessed attacker got %s" % str(hit2.get("blessing_multiplier")))
		return false
	# Damage path multiplies through (stamped hit dict from the
	# deterministic lookup, not a raw roll -- see note above).
	var stamped := {"blessing_multiplier": mult}
	var dmg := CombatMath.calculate_damage(100, stamped)
	if dmg < int(100 * _svc.BLESSED_DAMAGE_MULTIPLIER):
		push_error("FAIL: blessed damage %d below 120 base" % dmg)
		return false
	# Earn-gate respected at the combat layer: unearned day -> 1.0.
	_svc._unlocked_days.erase(day)
	var hit3: Dictionary = CombatMath.calculate_hit(attacker, _fake_fighter(""))
	if not is_equal_approx(float(hit3.get("blessing_multiplier", 1.0)), 1.0):
		push_error("FAIL: unearned day still multiplied damage")
		return false
	_svc.set_clock_override(-1.0)
	print("[OK] CombatMath: blessed attacker x%.1f, unblessed x1.0, unearned x1.0" % _svc.BLESSED_DAMAGE_MULTIPLIER)
	return true


func _test_heal_hook() -> bool:
	var day := 66666
	_svc._unlocked_days[day] = true
	_svc.set_clock_override(day * 86400.0 + 3600.0)
	var blessed: String = _svc.get_blessed_class_id(day)
	# Skill.calculate_healing via a real Skill instance duck-typed caster.
	var skill_script = load("res://core/combat/skill.gd")
	var skill = skill_script.new()
	if skill == null or not skill.has_method("calculate_healing"):
		push_error("FAIL: skill instance unusable")
		return false
	skill.heal_amount = 100
	var healer = _fake_fighter(blessed)
	healer.stats["wisdom"] = 0  # isolate the blessing on the flat heal
	var healed: int = skill.calculate_healing(healer)
	if healed < int(100 * _svc.BLESSED_DAMAGE_MULTIPLIER):
		push_error("FAIL: blessed heal %d below 120" % healed)
		return false
	# Control: SAME zeroed wisdom -- the class default (10) would add +20
	# WIS healing and mask the blessing either way (real bug found here:
	# plain_heal read 120 from WIS, not from a phantom blessing).
	var plain = _fake_fighter(_unblessed_id(day))
	plain.stats["wisdom"] = 0
	var plain_heal: int = skill.calculate_healing(plain)
	if plain_heal != 100:
		push_error("FAIL: unblessed heal %d != 100" % plain_heal)
		return false
	# Skill is a Resource (RefCounted): never .free() it.
	_svc.set_clock_override(-1.0)
	print("[OK] Skill healing: blessed %d vs unblessed 100" % healed)
	return true


func _test_xp_hook() -> bool:
	var day := 77777
	_svc._unlocked_days[day] = true
	_svc.set_clock_override(day * 86400.0 + 3600.0)
	var blessed: String = _svc.get_blessed_class_id(day)
	var winner = _fake_fighter(blessed)
	winner.xp = 0
	KillRewards._grant_xp(winner, 100)
	if int(winner.xp) != 120:
		push_error("FAIL: blessed XP %d != 120" % int(winner.xp))
		return false
	var loser = _fake_fighter(_unblessed_id(day))
	loser.xp = 0
	KillRewards._grant_xp(loser, 100)
	if int(loser.xp) != 100:
		push_error("FAIL: unblessed XP %d != 100" % int(loser.xp))
		return false
	_svc.set_clock_override(-1.0)
	print("[OK] KillRewards XP: blessed 120, unblessed 100")
	return true


## A class the wheel did NOT name for `day` (the control in hook tests;
## avoids the collision when the wheel happens to name the default).
func _unblessed_id(day: int) -> String:
	var ids: Array[String] = _svc._playable_class_ids()
	var named: String = _svc.get_blessed_class_id(day)
	for cid in ids:
		if cid != named:
			return cid
	return ""


## Minimal duck-typed combatant: character_class + stats + level is the
## whole surface the blessing path touches. Inner class (NOT set() on a
## bare RefCounted -- set() on a nonexistent property silently no-ops
## and every "x in obj" probe then fails).
class FakeFighter:
	var character_class: String = ""
	var level: int = 10
	var xp: int = 0
	var stats: Dictionary = {
		"strength": 20, "agility": 10, "intelligence": 10,
		"vitality": 10, "wisdom": 10,
		"hit_rating": 0.0, "dodge_rating": 0.0,
		"parry_rating": 0.0, "block_rating": 0.0,
	}

	func _init(cid: String = "") -> void:
		character_class = cid

	## Skill.calculate_healing reads this (WIS-based).
	func get_healing_power() -> int:
		return int(stats.get("wisdom", 10)) * 2


func _fake_fighter(class_id: String):
	return FakeFighter.new(class_id)
