## Mesh signal consumers receipt (Phase 3.4, labs/prd-shard-mesh.md).
##
## CoordinatorService's shard_registered / shard_unregistered /
## cross_shard_event_emitted had emitters but ZERO listeners -- the mesh's
## own activity (a shard joining, a shard leaving, a cross-shard event
## routing) was invisible. This receipt proves the consumer ChatService
## now binds them:
##   1. ChatService bound all three coordinator signals at boot.
##   2. A shard registering lands a ledger entry.
##   3. A cross-shard event lands an "event:<type>" ledger entry.
##   4. A shard LEAVING the mesh lands a ledger entry AND raises an
##      ADMIN_ALERT toast (the one event an operator must not miss).
##   5. The /mesh report renders the recent-activity line.
##   6. The ledger is bounded (newest-first, capped).
##   7. /mesh stays read-only (the registry is unchanged after it).
##
## Run:
##   godot --headless --path . --script res://tests/test_mesh_signal_consumers.gd
extends SceneTree

var _passes := 0
var _fails := 0
var _cs: Node
var _coord: Node
var _ns: Node
var _fired: Array = []


func _initialize() -> void:
	await process_frame
	_cs = root.get_node_or_null("ChatService")
	_coord = root.get_node_or_null("CoordinatorService")
	_ns = root.get_node_or_null("NotificationService")
	if _cs == null or _coord == null or _ns == null:
		push_error("FAIL: required autoloads missing")
		quit(1)
		return
	print("--- MESH SIGNAL CONSUMERS ---")
	_ns.notification_sent.connect(func(_pid, n):
		_fired.append(str(n.get("message", "") if n is Dictionary else n)))
	await _run()
	print("--- RESULT: %d passed, %d failed ---" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("PASS: ", label)
	else:
		_fails += 1
		push_error("FAIL: %s" % label)


func _said(needle: String) -> bool:
	for m in _fired:
		if m.find(needle) != -1:
			return true
	return false


func _ledger_has(kind: String, shard_id: String) -> bool:
	for e in _cs._mesh_activity:
		if str(e.get("kind", "")) == kind and str(e.get("shard_id", "")) == shard_id:
			return true
	return false


func _run() -> void:
	# 1. The consumer bound all three signals at boot.
	_ok(_coord.shard_registered.is_connected(Callable(_cs, "_on_mesh_shard_registered")),
		"shard_registered is bound")
	_ok(_coord.shard_unregistered.is_connected(Callable(_cs, "_on_mesh_shard_unregistered")),
		"shard_unregistered is bound")
	_ok(_coord.cross_shard_event_emitted.is_connected(Callable(_cs, "_on_mesh_cross_shard_event")),
		"cross_shard_event_emitted is bound")

	# Clear any boot-time ledger so the assertions below are ours.
	_cs._mesh_activity.clear()

	# 2. A shard registering lands a ledger entry.
	_coord.register_shard("shard_probe", {"name": "Probe"})
	await process_frame
	_ok(_ledger_has("registered", "shard_probe"), "shard_registered lands a ledger entry")

	# 3. A cross-shard event lands an event:<type> entry.
	_coord.emit_cross_shard_event_auto("probe_ping", "shard_probe", {"k": 1})
	await process_frame
	_ok(_ledger_has("event:probe_ping", "shard_probe"),
		"cross_shard_event_emitted lands an event ledger entry")

	# 4. A shard leaving lands a ledger entry AND an admin alert.
	_fired.clear()
	_coord.unregister_shard("shard_probe")
	await process_frame
	await process_frame
	_ok(_ledger_has("unregistered", "shard_probe"), "shard_unregistered lands a ledger entry")
	_ok(_said("shard_probe") and _said("left the mesh"),
		"shard_unregistered raises an admin alert")

	# 5. The /mesh report renders the recent-activity line.
	var report: String = _cs._mesh_report()
	_ok(report.find("recent:") != -1, "/mesh renders the recent-activity line")
	_ok(report.find("unregistered@shard_probe") != -1, "the recent line names the leave event")

	# 6. The ledger is bounded (newest-first, capped).
	for i in range(_cs._MESH_LEDGER_CAP + 8):
		_cs._mesh_ledger_push("registered", "shard_%d" % i, "")
	_ok(_cs._mesh_activity.size() == _cs._MESH_LEDGER_CAP, "the ledger is capped")
	_ok(str(_cs._mesh_activity[0].get("shard_id", "")) == "shard_%d" % (_cs._MESH_LEDGER_CAP + 7),
		"the ledger is newest-first")

	# 7. /mesh is read-only: the registry is unchanged after it.
	var before: Array = _coord.get_all_shard_ids()
	before.sort()
	_cs._mesh_report()
	var after: Array = _coord.get_all_shard_ids()
	after.sort()
	_ok(before == after, "/mesh is read-only (registry unchanged)")
