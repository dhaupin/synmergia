extends SceneTree

## Fresh-confirm kit receipt (the cheap-pair round, starter-kit leg):
##   CharacterSelect declares character_confirmed and ACTUALLY emits it
##   on Enter World -> StarterKitService's tree relay connects the
##   handler -> the fresh mark gates the grant gate law: kit for a
##   confirmed-fresh character, kit for a never-saved character, and
##   the returning-with-saved-bag leg stops collecting a second kit.
## Run:
##   godot --headless --path . --script res://tests/test_character_fresh_kit.gd

func _initialize() -> void:
	# Autoload-lag law (test_slot_container_open): the autoload set
	# goes live AFTER _initialize -- body runs on the first idle frame,
	# never from _init() and never inline here.
	_run.call_deferred()

func _run() -> void:
	# 1. The declared signal exists on the scene script, and the emit
	# leg is real (static source check: the full-boot flows that run
	# _on_play_pressed exercise it at runtime).
	var cs_script: GDScript = load("res://ui/menus/character_select.gd")
	if cs_script == null or not cs_script.can_instantiate():
		push_error("FAIL: character_select.gd did not load")
		quit(1)
		return
	var has_signal_declared := false
	for sig in cs_script.get_script_signal_list():
		if str(sig.get("name", "")) == "character_confirmed":
			has_signal_declared = true
	if not has_signal_declared:
		push_error("FAIL: character_confirmed is not declared on the selection script")
		quit(1)
		return
	if not cs_script.source_code.contains("character_confirmed.emit(data)"):
		push_error("FAIL: Enter World does not emit character_confirmed")
		quit(1)
		return
	print("[OK] character_confirmed is declared AND emitted on Enter World")

	# 2. The tree relay: the autoload's handler connects the declared
	# signal off a node carrying the selection script. A bare
	# cs_script.new() instance (not the loaded scene) carries the
	# signal without running _ready's UI build.
	var starter: Node = root.get_node_or_null("StarterKitService")
	if starter == null:
		push_error("FAIL: StarterKitService autoload not live in script mode")
		quit(1)
		return
	var probe_node: Control = cs_script.new()
	starter._on_tree_node_added(probe_node)
	if not probe_node.character_confirmed.is_connected(starter._on_character_confirmed):
		push_error("FAIL: the relay did not connect character_confirmed")
		quit(1)
		return
	print("[OK] the tree relay connects character_confirmed -> _on_character_confirmed")

	# 3. A confirmed character earns the kit gate.
	var cd_script: GDScript = load("res://core/schemas/character_data.gd")
	var data = cd_script.new("human", "human_warrior", "Probe")
	var char_id := str(data.character_id)
	probe_node.character_confirmed.emit(data)
	if not bool(starter._fresh_confirmed.get(char_id, false)):
		push_error("FAIL: character_confirmed did not mark %s fresh" % char_id)
		quit(1)
		return
	if not bool(starter._should_grant_kit(char_id)):
		push_error("FAIL: a fresh-confirmed character was denied the kit gate")
		quit(1)
		return
	print("[OK] the confirmed character passes the grant gate (fresh leg)")

	# 4. A character with no fresh mark and no saved progress still
	# earns the kit (the never-completed-a-session leg; the
	# saved-progress negative leg runs on full-boot flows).
	if not bool(starter._should_grant_kit("probe_never_confirmed")):
		push_error("FAIL: a never-seen character was denied the kit gate")
		quit(1)
		return
	print("[OK] the never-saved character passes the grant gate")
	print("--- CHARACTER FRESH KIT: ok=true ---")
	quit(0)
