## Round-6 receipt: party-member death notifications.
##
## Bug: health_component._on_health_depleted gated its party-notify leg on
## entity.has_method("get_party_id") -- a method declared NOWHERE in the
## repo. The guard was always false, so no party member ever learned a
## teammate had died. Fix: resolve the party through
## PartyService.get_player_party (the same call kill_rewards / loot_rules
## use) and notify the OTHER members.
##
## Legs:
##   1. A party of two: when one dies, the OTHER member gets the
##      "has died" line.
##   2. The dead member does not receive a party-death line about itself
##      (no self-spam).
##   3. Solo death: no party -> only the owner death line, no party line.
##   4. REGRESSION LOCK: the source no longer probes the phantom
##      get_party_id and does route through get_player_party.
##
## Run:
##   godot --headless --path game/ --script res://tests/test_party_death_notify.gd
extends SceneTree

var _sent: Array = []          # [{entity_id, notification}]
var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ns: Node = root.get_node_or_null("NotificationService")
	var ps: Node = root.get_node_or_null("PartyService")
	if ns == null or ps == null:
		push_error("FAIL: NotificationService/PartyService autoload missing")
		quit(1)
		return
	ns.notification_sent.connect(_on_notification)

	_test_party_member_death(ps)
	_test_solo_death()
	_test_source_regression()

	print("--- RESULT: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _on_notification(entity_id: String, notification: Dictionary) -> void:
	_sent.append({"entity_id": entity_id, "message": str(notification.get("message", ""))})


func _test_party_member_death(ps: Node) -> void:
	var pid: String = ps.create_party("r6_leader")
	if pid.is_empty():
		_fail("create_party returned empty")
		return
	if not ps.invite_player("r6_leader", "r6_member"):
		_fail("invite_player failed")
		return
	if not ps.accept_invite("r6_member"):
		_fail("accept_invite failed")
		return

	_sent.clear()
	var dead := _make_entity("r6_member", "R6Member")
	_kill(dead)

	var member_notified := false
	var self_spam := false
	for row in _sent:
		if row.entity_id == "r6_leader" and row.message.contains("R6Member") and row.message.contains("died"):
			member_notified = true
		if row.entity_id == "r6_member" and row.message.contains("has died"):
			self_spam = true

	_assert(member_notified, "the OTHER party member is told R6Member died")
	_assert(not self_spam, "the dead member gets no party-death line about itself")

	ps.disband_party(pid)


func _test_solo_death() -> void:
	_sent.clear()
	var dead := _make_entity("r6_solo", "R6Solo")
	_kill(dead)

	var party_line := false
	for row in _sent:
		if row.message.contains("R6Solo") and row.message.contains("died"):
			party_line = true
	_assert(not party_line, "a solo death produces no party-death line")


## The guard that killed this leg: no entity declares get_party_id.
func _test_source_regression() -> void:
	var f := FileAccess.open("res://core/components/health_component.gd", FileAccess.READ)
	if f == null:
		_fail("cannot read health_component.gd")
		return
	var src := f.get_as_text()
	_assert(not src.contains('has_method("get_party_id")'), "source no longer probes phantom get_party_id")
	_assert(src.contains("get_player_party"), "source resolves the party via PartyService.get_player_party")


func _make_entity(entity_id: String, display_name: String) -> Node3D:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar entity_id: String = \"\"\nvar display_name: String = \"\"\n"
	script.reload()
	var e := Node3D.new()
	e.set_script(script)
	e.entity_id = entity_id
	e.display_name = display_name
	root.add_child(e)
	return e


## Attach a real HealthComponent and drive the death leg the world drives.
func _kill(entity: Node3D) -> void:
	var hc: Node = load("res://core/components/health_component.gd").new()
	hc.name = "HealthComponent"
	hc.max_health = 1
	entity.add_child(hc)
	hc.current_health = 0
	hc.health_depleted.emit()


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  PASS: ", label)
	else:
		_failed += 1
		print("  FAIL: ", label)


func _fail(label: String) -> void:
	_failed += 1
	print("  FAIL: ", label)
