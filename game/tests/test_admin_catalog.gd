## test_admin_catalog - the admin catalog + player shell are real and wired.
##
## Two files were deleted in the B1 sweep as "no live references" but are
## real features:
##  - AdminCatalog was a MOCK (invented ids like eny_goblin, spawn legs that
##    only emitted an event) and never compiled. It is rebuilt to browse the
##    LIVE DataService catalog and route every action through the owning
##    service, and is now mounted as an AdminDashboard tab.
##  - PlayerShell (per-player aliases/macros/settings/stats) never compiled
##    (8 parse errors) and had zero callers. It is fixed, autoloaded, and
##    wired as ChatService's command fallback for the commands ChatService
##    does not own.
##
## Run: godot --headless --path game --script res://tests/test_admin_catalog.gd
extends SceneTree

var _passed := 0
var _failed := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("   PASS  %s" % msg)
	else:
		_failed += 1
		print("   FAIL  %s" % msg)


func _finish() -> void:
	print("=== ADMIN CATALOG RECEIPT: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ds = root.get_node_or_null("DataService")
	if ds != null and not ds._loaded and ds.has_method("load_all_data"):
		ds.load_all_data()
	await process_frame

	# --- AdminCatalog: real catalog, real dispatch -----------------------
	var CatalogScript: GDScript = load("res://core/admin/admin_catalog.gd")
	_check(CatalogScript != null, "admin_catalog.gd loads (no parse errors)")
	if CatalogScript == null:
		_finish()
		return
	var catalog = CatalogScript.new()
	root.add_child(catalog)
	await process_frame
	_check(catalog._catalog_entries.size() > 0,
		"the catalog populated from the live DataService (%d entries)" % catalog._catalog_entries.size())
	var by_type: Dictionary = {}
	for e in catalog._catalog_entries:
		by_type[e.type] = int(by_type.get(e.type, 0)) + 1
	_check(by_type.get("ENEMY", 0) > 0, "enemies are listed (%d)" % by_type.get("ENEMY", 0))
	_check(by_type.get("ITEM", 0) > 0, "items are listed (%d)" % by_type.get("ITEM", 0))
	_check(by_type.get("NPC", 0) > 0, "npcs are listed (%d)" % by_type.get("NPC", 0))

	# Every listed id resolves in the live data (no phantom SKUs).
	var phantom := 0
	for e in catalog._catalog_entries:
		var ok := false
		match e.type:
			"ENEMY": ok = ds.get_enemy(e.id) != null
			"NPC": ok = ds.get_npc(e.id) != null
			"ITEM": ok = ds.get_item(e.id) != null
			"ZONE": ok = ds.get_zone(e.id) != null
			"QUEST": ok = ds.get_quest(e.id) != null
			"SKILL": ok = ds.get_skill(e.id) != null
		if not ok:
			phantom += 1
	_check(phantom == 0, "every catalog id resolves in the live data (0 phantom)")

	# The dispatch refuses an unknown id honestly.
	_check(not catalog._spawn_by_id("eny_goblin_not_real", 1),
		"the invented-id dispatch is refused (no phantom spawn)")

	# --- PlayerShell: compiles, autoloaded, executes --------------------
	var ps = root.get_node_or_null("PlayerShell")
	_check(ps != null, "PlayerShell is autoloaded (registered on /root)")
	if ps != null:
		_check(ps.get_help("").contains("Player Commands"), "help renders the command board")
		var res = ps.execute("alias foo stats", "tester")
		_check(res != null and res.success, "a real command executes (/alias foo stats)")
		var res2 = ps.execute("settings", "tester")
		_check(res2 != null and res2.success and res2.output.contains("foo"),
			"the alias persisted into /settings")
		var res3 = ps.execute("no_such_cmd_xyz", "tester")
		_check(res3 != null and not res3.success, "an unknown command is refused honestly")

	# --- The chat fallback reaches PlayerShell --------------------------
	var chat = root.get_node_or_null("ChatService")
	_check(chat != null and chat.has_method("_player_shell"),
		"ChatService carries the PlayerShell fallback hook")
	if chat != null and chat.has_method("_player_shell"):
		_check(chat._player_shell() == ps, "the fallback resolves the PlayerShell autoload")

	catalog.queue_free()
	_finish()
