## test_agent_web_hooks.gd - regression for the in-page agent wire
## (window.SynmergiaAgent) and the web opt-in that enables it.
##
## Why this exists: the wire shipped broken and untested. On wasm,
## JavaScriptBridge.create_callback has TWO marshalling limits that a native
## test cannot exercise directly:
##   1. a callback's RETURN VALUE never crosses back to JS (arrives as null),
##      so the hook must publish its JSON on window.__synAgentResult and the
##      JS facade reads it back in the same turn;
##   2. a JS OBJECT argument arrives as an opaque JavaScriptObject, not a
##      Dictionary, so the facade passes JSON STRINGS and the hook decodes them.
## Plus a Dictionary that merely CONTAINS callbacks does not marshal at all
## (window.SynmergiaAgent landed as undefined).
##
## The live browser probe (scripts/web_probe/probe_agent_wire.js) is the
## end-to-end oracle; this test pins the SOURCE contract and the pure decode
## logic so a regression is caught in CI without a browser.
##
## Run: cd game && godot --headless --path . --script res://tests/test_agent_web_hooks.gd
extends SceneTree

var _fails: int = 0

func _init() -> void:
	call_deferred("_run")

func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		printerr("FAIL  ", label)
		_fails += 1

func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()

func _run() -> void:
	var bridge_src := _read("res://core/autoload/web_input_bridge.gd")
	var driver_src := _read("res://core/services/agent_driver.gd")

	# --- Source contract: the broken Dictionary-of-callbacks install is gone ---
	_check(not bridge_src.contains("win.SynmergiaAgent = {"),
		"bridge does NOT assign a Dictionary of callbacks to window.SynmergiaAgent")
	_check(bridge_src.contains("__synAgentResult"),
		"bridge publishes results on window.__synAgentResult (return-value side-channel)")
	_check(bridge_src.contains("__synAgentObserve") and bridge_src.contains("__synAgentAct") \
		and bridge_src.contains("__synAgentEvents"),
		"bridge retains the three named callback globals")
	_check(bridge_src.contains("JSON.stringify(payload)"),
		"facade serializes the act payload to a JSON string (JS objects do not marshal)")

	# --- Source contract: the web opt-in exists and is fail-closed ---
	_check(driver_src.contains("_web_opt_in"),
		"driver has a web opt-in (SYN_AGENT has no browser equivalent)")
	_check(driver_src.contains("SynmergiaConfig") and driver_src.contains("agent"),
		"web opt-in reads window.SynmergiaConfig.agent")

	# --- Behaviour: the JSON-string decode the hook relies on ---
	var bridge = load("res://core/autoload/web_input_bridge.gd").new()
	_check(bridge.has_method("_json_arg"), "bridge exposes _json_arg")
	var decoded = bridge._json_arg(['{"id":"ui:X","args":{"verb":"set_value","value":"hi"}}'])
	_check(decoded is Dictionary, "a JSON object string decodes to a Dictionary")
	_check(decoded.get("id", "") == "ui:X", "decoded payload keeps the id")
	var inner = decoded.get("args", null)
	_check(inner is Dictionary and inner.get("verb", "") == "set_value" \
		and inner.get("value", "") == "hi",
		"decoded args keep the verb + value (the set_value fold)")
	_check(bridge._json_arg(["-1"]) == -1, "a JSON scalar string decodes (events cursor)")
	_check(bridge._json_arg([]) == null, "an empty arg list yields the fallback (null)")
	_check(bridge._json_arg(["not json"], "FB") == "FB", "a malformed string yields the fallback")

	# --- Behaviour: the web opt-in is fail-closed off the web platform ---
	# (native headless is not web, so this must be false without touching
	# JavaScriptBridge.eval, which is a no-op error off-web).
	var driver = load("res://core/services/agent_driver.gd").new()
	_check(driver.has_method("_web_opt_in"), "driver exposes _web_opt_in")
	_check(driver._web_opt_in() == false, "web opt-in is false on a non-web build (fail closed)")
	driver.free()

	# --- Behaviour: ONE act fold shared by both transports ---------------
	# The HTTP door and the in-page hook are the same protocol at two
	# distances. A private copy per transport is how the in-page set_value
	# silently became an activate: it sent flat {id,verb,value} into a
	# reader expecting {id,args}. Pin the fold on AgentDriver and pin that
	# BOTH transports call it rather than carrying their own.
	var driver_script = load("res://core/services/agent_driver.gd")
	_check(driver_script.has_method("fold_act_body"),
		"AgentDriver.fold_act_body exists (the ONE act-body fold)")
	var folded = driver_script.fold_act_body({"id": "ui:X", "verb": "set_value", "value": "hi"})
	_check(folded.get("id", "") == "ui:X", "fold keeps the id")
	_check(folded.get("args", {}).get("verb", "") == "set_value",
		"fold lifts a top-level verb into args (set_value survives)")
	_check(folded.get("args", {}).get("value", "") == "hi",
		"fold lifts a top-level scalar value into args")
	var nested = driver_script.fold_act_body({"id": "move", "args": {"forward": 1}})
	_check(nested.get("args", {}).get("forward", 0) == 1,
		"fold keeps a nested args object (companion act(id,{forward:1}))")
	var dict_value = driver_script.fold_act_body({"id": "ui:Y", "value": {"label": "go"}})
	_check(dict_value.get("args", {}).get("label", "") == "go",
		"fold merges a dictionary value into args")
	var principal = driver_script.fold_act_body({"id": "move", "principal": "agent-2"})
	_check(principal.get("args", {}).get("principal", "") == "agent-2",
		"fold carries a per-body principal")
	_check(driver_script.fold_act_body({}).get("id", "x") == "",
		"fold tolerates an empty body (id is empty, never a crash)")
	_check(bridge_src.contains("AgentDriver.fold_act_body"),
		"the in-page hook folds through AgentDriver.fold_act_body")
	var door_src := _read("res://core/services/agent_door.gd")
	_check(door_src.contains("AgentDriver.fold_act_body"),
		"the HTTP door folds through the SAME AgentDriver.fold_act_body")

	print("SUMMARY: 23 checks, %d failed" % _fails)
	if _fails == 0:
		print("ALL TESTS PASSED")
	quit(0 if _fails == 0 else 1)
