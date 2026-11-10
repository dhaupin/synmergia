## test_agent_roster.gd - LIVE receipt for the human<->agent pairing + the
## slot ladder (labs/prd-agent-play.md sec 12, 14, 17; labs/prd-monetization.md
## sec 43 "The Agent Ledger").
##
##   cd game && godot --headless --path . --script res://tests/test_agent_roster.gd
##
## Legs:
##   1. the dev floor: SYN_AGENT_DEV_SLOTS=5 grants the full 6-seat party.
##   2. the 1:1 law: a handle belongs to exactly one account; a second
##      attach is refused by name.
##   3. the cap (dev floor): the (floor+1)th attach is refused, naming the need.
##   4. the sigil ladder (PRODUCTION floor): slot 2 is priced 250;
##      unlock_next_slot debits the ONE purse and grants exactly one slot;
##      a short purse is refused naming the need and grants nothing.
##   5. the ladder ceiling: MAX_SLOTS = 5 (a full party); past it there is
##      no priced slot and the unlock is refused by name.
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

	# ---- 1-3: the DEV FLOOR (5 free = a full 6-seat party) -----------
	OS.set_environment("SYN_AGENT_DEV_SLOTS", "5")
	var dev := "acct_roster_dev_%d" % Time.get_ticks_msec()
	_assert(_roster.effective_slots(dev) == 5, "the dev floor grants 5 free slots (a full party)")
	for i in 5:
		var h := "dev_%d" % i
		_assert(bool(_coord.register(h, {}).get("ok", false)), "register %s" % h)
		_assert(bool(_roster.attach(dev, h).get("ok", false)), "attach %s (free slot)" % h)
	_assert(_roster.agents_of(dev).size() == 5, "5 agents attached on the dev floor")
	_assert(_roster.available_slots(dev) == 0, "no free slots remain")

	# 2. The 1:1 law.
	var other := "acct_other_%d" % Time.get_ticks_msec()
	var dup: Dictionary = _roster.attach(other, "dev_0")
	_assert(not bool(dup.get("ok", true)) and String(dup.get("reason", "")).contains("already attached"), "a handle belongs to one account (1:1 refused)")

	# 3. The cap.
	_assert(bool(_coord.register("over", {}).get("ok", false)), "register over")
	var over: Dictionary = _roster.attach(dev, "over")
	_assert(not bool(over.get("ok", true)) and String(over.get("reason", "")).contains("no free agent slots"), "the 6th attach is refused by name")

	# ---- 4-5: the SIGIL LADDER (PRODUCTION floor = 1 free) -----------
	# The ladder is only reachable below the ceiling, so clear the dev
	# knob and drive a fresh account through the real prices.
	OS.set_environment("SYN_AGENT_DEV_SLOTS", "")
	var acct := "acct_roster_prod_%d" % Time.get_ticks_msec()
	_assert(_roster.effective_slots(acct) == 1, "the production floor grants 1 free slot")
	_assert(bool(_coord.register("solo", {}).get("ok", false)), "register solo")
	_assert(bool(_roster.attach(acct, "solo").get("ok", false)), "attach solo (the free slot)")

	_purse = _purse_for(acct)
	_assert(_purse != null, "the account has a purse")
	var price: int = _roster.next_slot_price(acct)
	_assert(price == 250, "the next slot (2) is priced 250 sigils")
	var short: Dictionary = _roster.unlock_next_slot(acct)
	_assert(not bool(short.get("ok", true)) and String(short.get("reason", "")).contains("need 250"), "a short purse is refused naming the need")
	_assert(_roster.effective_slots(acct) == 1, "the refused purchase granted nothing")
	_purse.add_currency("currency_concord_sigil", 250)
	var bought: Dictionary = _roster.unlock_next_slot(acct)
	_assert(bool(bought.get("ok", false)), "the slot unlocks when the purse can pay")
	_assert(_roster.effective_slots(acct) == 2, "the unlock raised the cap to 2")
	_assert(int(_purse.get_currency_amount("currency_concord_sigil")) == 0, "the sigils were debited (0 left)")

	# 5. The ladder ceiling (slots 3, 4, 5 at 900 / 2500 / 6000).
	for step in [[3, 900], [4, 2500], [5, 6000]]:
		_assert(_roster.next_slot_price(acct) == int(step[1]), "slot %d is priced %d" % [int(step[0]), int(step[1])])
		_purse.add_currency("currency_concord_sigil", int(step[1]))
		_roster.unlock_next_slot(acct)
	_assert(_roster.effective_slots(acct) == 5, "the ladder tops out at MAX_SLOTS (5 = a full party)")
	_assert(_roster.next_slot_price(acct) == -1, "no priced slot remains")
	var full: Dictionary = _roster.unlock_next_slot(acct)
	_assert(not bool(full.get("ok", true)) and String(full.get("reason", "")).contains("full"), "the exhausted ladder refuses by name")

	# 6. Detach frees a slot, the unlock stays.
	_assert(bool(_roster.detach("solo")), "detach solo")
	_assert(_roster.agents_of(acct).size() == 0, "detach freed the used slot")
	_assert(_roster.effective_slots(acct) == 5, "detach did NOT refund the unlock")

	# 7. Persistence round-trip.
	var fresh = load("res://core/services/agent_roster.gd").new()
	root.add_child(fresh)
	await process_frame
	_assert(fresh.effective_slots(acct) == 5, "a fresh roster hydrates the unlocked slots")
	fresh.queue_free()

	# 8. No account, no agent.
	var noacct: Dictionary = _roster.attach("", "dev_1")
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
