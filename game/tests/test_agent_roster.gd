## test_agent_roster.gd - LIVE receipt for the human<->agent pairing + the
## slot ladder (labs/prd-agent-play.md sec 12-13; labs/prd-monetization.md
## sec 43 "The Agent Ledger").
##
##   cd game && xvfb-run godot --path . --script res://tests/test_agent_roster.gd
##
## Legs:
##   1. the free floor: an account attaches FREE_SLOTS agents with no sigils.
##   2. the 1:1 law: a handle belongs to exactly one account; a second
##      attach is refused by name.
##   3. the cap: the (FREE_SLOTS+1)th attach is refused, naming the need.
##   4. the sigil ladder: unlock_next_slot debits the ONE purse and grants
##      exactly one slot; a short purse is refused and grants nothing.
##   5. the ladder ceiling: past MAX_SLOTS there is no priced slot.
##   6. detach frees a slot; the slot count is unchanged (the unlock stays).
##   7. persistence: a fresh roster instance hydrates the unlocked slots
##      (JSON-normalized) and the attachments from the KV door.
##   8. no account, no agent: an empty account id is refused.
extends SceneTree

var _pass := 0
var _fail := 0
var _globe: Node = null
var _boot = null
var _driver: Node = null
var _coord: Node = null
var _roster: Node = null
var _purse = null


func _initialize() -> void:
	print("=== AGENT ROSTER LIVE TEST ===")
	_boot = load("res://tests/support/globe_boot.gd")
	_boot_globe.call_deferred()


func _boot_globe() -> void:
	_globe = await _boot.boot(self)
	if _globe == null:
		print("  FAIL: could not load globe_world.tscn")
		quit(1)
		return
	current_scene = _globe
	_run.call_deferred()


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] " + msg)
	else:
		_fail += 1
		print("  [FAIL] " + msg)


func _run() -> void:
	_driver = root.get_node_or_null("AgentDriver")
	_coord = root.get_node_or_null("AgentCoordinator")
	_roster = root.get_node_or_null("AgentRoster")
	_assert(_roster != null, "AgentRoster autoload present")
	if _roster == null:
		return _finish()
	_driver.set_enabled(true)

	var acct := "acct_roster_%d" % Time.get_ticks_msec()

	# The dev/testing floor is law: the receipt drives the same knob an
	# operator sets (SYN_AGENT_DEV_SLOTS=5 -> the full 6-seat party free).
	OS.set_environment("SYN_AGENT_DEV_SLOTS", "5")

	# 1. The free floor.
	_assert(_roster.effective_slots(acct) == 5, "the dev floor grants the 5 free slots (a full party)")
	var handles: Array = []
	for i in 5:
		var h := "free_%d" % i
		handles.append(h)
		_assert(bool(_coord.register(h, {}).get("ok", false)), "register %s" % h)
		_assert(bool(_roster.attach(acct, h).get("ok", false)), "attach %s (free slot)" % h)
	_assert(_roster.agents_of(acct).size() == 5, "5 agents attached on the free floor")
	_assert(_roster.available_slots(acct) == 0, "no free slots remain")

	# 2. The 1:1 law.
	var other := "acct_other_%d" % Time.get_ticks_msec()
	var dup: Dictionary = _roster.attach(other, "free_0")
	_assert(not bool(dup.get("ok", true)) and String(dup.get("reason", "")).contains("already attached"), "a handle belongs to one account (1:1 refused)")

	# 3. The cap.
	_assert(bool(_coord.register("over", {}).get("ok", false)), "register over")
	var over: Dictionary = _roster.attach(acct, "over")
	_assert(not bool(over.get("ok", true)) and String(over.get("reason", "")).contains("no free agent slots"), "the 6th attach is refused by name")

	# 4. The sigil ladder.
	_purse = _purse_for(acct)
	_assert(_purse != null, "the account has a purse")
	var price: int = _roster.next_slot_price(acct)
	_assert(price == 320, "the next slot (6) is priced 320 sigils")
	var short: Dictionary = _roster.unlock_next_slot(acct)
	_assert(not bool(short.get("ok", true)) and String(short.get("reason", "")).contains("need 320"), "a short purse is refused naming the need")
	_assert(_roster.effective_slots(acct) == 5, "the refused purchase granted nothing")
	_purse.add_currency("currency_concord_sigil", 320)
	var bought: Dictionary = _roster.unlock_next_slot(acct)
	_assert(bool(bought.get("ok", false)), "the slot unlocks when the purse can pay")
	_assert(_roster.effective_slots(acct) == 6, "the unlock raised the cap to 6")
	_assert(int(_purse.get_currency_amount("currency_concord_sigil")) == 0, "the sigils were debited (0 left)")

	# 5. The ladder ceiling.
	for i in range(7, 11):
		_purse.add_currency("currency_concord_sigil", 2000)
		_roster.unlock_next_slot(acct)
	_assert(_roster.effective_slots(acct) == 10, "the ladder tops out at MAX_SLOTS (10)")
	_assert(_roster.next_slot_price(acct) == -1, "no priced slot remains")
	var full: Dictionary = _roster.unlock_next_slot(acct)
	_assert(not bool(full.get("ok", true)) and String(full.get("reason", "")).contains("full"), "the exhausted ladder refuses by name")

	# 6. Detach frees a slot, the unlock stays.
	_assert(bool(_roster.detach("free_0")), "detach free_0")
	_assert(_roster.agents_of(acct).size() == 4, "detach freed the used slot")
	_assert(_roster.effective_slots(acct) == 10, "detach did NOT refund the unlock")

	# 7. Persistence round-trip.
	var fresh = load("res://core/services/agent_roster.gd").new()
	root.add_child(fresh)
	await process_frame
	_assert(fresh.effective_slots(acct) == 10, "a fresh roster hydrates the unlocked slots")
	_assert(fresh.agents_of(acct).size() == 4, "a fresh roster hydrates the attachments")
	fresh.queue_free()

	# 8. No account, no agent.
	var noacct: Dictionary = _roster.attach("", "free_1")
	_assert(not bool(noacct.get("ok", true)) and String(noacct.get("reason", "")).contains("account is required"), "an empty account is refused (guest play retired)")

	_finish()


func _purse_for(account_id: String):
	var inv_svc := root.get_node_or_null("InventoryService")
	if inv_svc == null:
		return null
	var existing = inv_svc.get_inventory(account_id)
	if existing != null and is_instance_valid(existing):
		return existing
	var InvCompScript = load("res://core/components/inventory_component.gd")
	var comp = InvCompScript.new()
	comp.name = "RosterPurse"
	root.add_child(comp)
	inv_svc.register_inventory(account_id, comp)
	return inv_svc.get_inventory(account_id)


func _finish() -> void:
	print("--- AGENT ROSTER TEST: %d passed, %d failed ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
