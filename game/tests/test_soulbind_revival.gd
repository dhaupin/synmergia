extends SceneTree

## test_soulbind_revival.gd -- THE SOULBIND RESURRECTION RECEIPT.
## The Soulbinder's Ticket (data/items/item_soulbind_ticket.tres) rides the
## Concord sink's RESPAWN grant leg (real sigils; the catalog receipt owns
## the purchase law); RespawnService is its ONE consumer pair:
##   * THE STAND-UP (self): the death screen's SELF_REVIVE -- instantly,
##     at the death spot, or the zone spawn when the fall was sea/rock.
##     DEBIT BEFORE GRANT: the ticket leaves the bag before the cycle
##     schedules; the count reads the bag's honest stack truth.
##   * THE LIFELINE (others): start_revival pays through the clergy gate
##     at a fallen ally -- behind every other gate, never wasted on a
##     ranged or refused attempt.
## Run: cd game && godot --headless --path . --script res://tests/test_soulbind_revival.gd

const InventoryCompPath = "res://core/components/inventory_component.gd"
const TICKET_ID := "item_soulbind_ticket"
const CURRENCY_ID := "currency_concord_sigil"

var _fails := 0
var _passes := 0

func _ok(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("PASS: ", label)
	else:
		_fails += 1
		push_error("FAIL: %s" % label)

func _seed_wallet(id: String, sigils: int, tickets: int) -> Node:
	var comp = load(InventoryCompPath).new()
	root.get_node_or_null("InventoryService").call("register_inventory", id, comp)
	comp.call("add_currency", CURRENCY_ID, sigils)
	if tickets > 0:
		var ds = root.get_node_or_null("DataService")
		comp.call("add_item", ds.call("get_item", TICKET_ID), tickets)
	return comp

## The player stub: exactly the fields the death cycle ducks for.
class StubPlayer extends Node:
	var entity_id := "soul_link_2"
	var display_name := "Soulprobe"
	var health_component = null
	var _pending_respawn_mode_int = null
	var _pending_respawn_position = null
	var _pending_respawn_choice = {}
	var global_position := Vector3(17, 2, 9)

## The book parametrization: a Node3D-shaped duck the revival gates read.
class StubBody extends Node3D:
	var entity_id := ""
	var display_name := ""
	var health_component = null

class DeadHealth extends RefCounted:
	func is_dead() -> bool:
		return true

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var rs = root.get_node_or_null("RespawnService")
	_ok(rs != null, "RespawnService autoload reachable")
	if rs == null:
		print("SOULBIND-REVIVAL: server door missing")
		quit(1)
		return

	# ---- THE BOOK (count from stack truth, consume = debit) ------------
	var stranger := {"entity_id": "no_seat_here"}
	_ok(rs.soulbind_count(stranger) == 0, "an unseated body counts zero tickets, never invented")
	var book = _seed_wallet("soul_link_1", 0, 3)
	_ok(rs.soulbind_count({"entity_id": "soul_link_1"}) == 3, "the ticket count reads the bag's stack truth (3)")
	_ok(rs._consume_soulbind({"entity_id": "soul_link_1"}) == true, "the consume door pays the debit")
	_ok(rs.soulbind_count({"entity_id": "soul_link_1"}) == 2, "one ticket out, the book reads 2")
	_book_drain(rs, {"entity_id": "soul_link_1"})
	_ok(rs.soulbind_count({"entity_id": "soul_link_1"}) == 0, "a drained wallet counts zero and the consume door refuses")
	_ok(rs._consume_soulbind({"entity_id": "soul_link_1"}) == false, "an empty purse refuses the debit by name")

	# ---- THE MODE MAPPING ----------------------------------------------
	_ok(rs._mode_for_choice({"mode": "soulbind"}) == rs.RespawnMode.SELF_REVIVE,
		"the death screen's soulbind choice resolves to the SELF_REVIVE seat")
	_ok(rs._mode_for_choice({"mode": "leaf_on_the_wind"}) == rs.RespawnMode.TIMED,
		"an unknown choice still falls through to the honest timed rail")

	# ---- AVAILABILITY (the death screen reads the bag's truth) ----------
	var stub := StubPlayer.new()
	root.add_child(stub)
	var no_ticket: Array = rs.get_available_respawn_modes(stub, "")
	_ok(not (rs.RespawnMode.SELF_REVIVE in no_ticket), "no ticket, no soulbind row: the free rails stay free")
	_seed_wallet("soul_link_2", 0, 4)
	var ticketed: Array = rs.get_available_respawn_modes(stub, "")
	_ok(rs.RespawnMode.SELF_REVIVE in ticketed, "a ticket in the bag offers the stand-up seat")
	_ok(rs.RespawnMode.TIMED in ticketed, "the timed rail rides beside the paid one")

	# ---- THE STAND-UP LAW (the cycle consumes + sites it right) ---------
	# Sea-owned fall: a safe ground nearby; DEBIT BEFORE GRANT.
	rs._depth_resolver = func(_pos): return 2.4
	stub._pending_respawn_choice = {"mode": "soulbind", "position": Vector3(17, 2, 9)}
	var sea_rise: bool = rs.initiate_respawn(stub, "")
	_ok(sea_rise, "the sea-owned fall initiated a cycle")
	_ok(rs.soulbind_count({"entity_id": "soul_link_2"}) == 3, "the cycle consumed exactly one ticket before scheduling (4 -> 3)")
	_ok(stub._pending_respawn_mode_int == int(rs.RespawnMode.SELF_REVIVE), "the pending seat carries SELF_REVIVE")
	_ok(stub._pending_respawn_position != Vector3(17, 2, 9), "a sea-owned fall buys back a safe ground, not the death spot")
	_ok(stub._pending_respawn_position != null, "the safe ground is parked, the executor reads it late")
	# Honest dry fall: stand in place, priced the same one ticket.
	stub._pending_respawn_mode_int = null
	stub._pending_respawn_position = null
	rs._depth_resolver = func(_pos): return -0.5
	stub._pending_respawn_choice = {"mode": "soulbind", "position": Vector3(23, 4, 11)}
	var dry_rise: bool = rs.initiate_respawn(stub, "")
	_ok(dry_rise, "the dry fall initiated a cycle")
	_ok(rs.soulbind_count({"entity_id": "soul_link_2"}) == 2, "the dry stand-up priced exactly one ticket (3 -> 2)")
	_ok(stub._pending_respawn_position == Vector3(23, 4, 11), "an honest dry fall stands in place")
	# Rock inside: the site law sends it near, same as the sea.
	stub._pending_respawn_mode_int = null
	stub._pending_respawn_position = null
	rs._depth_resolver = func(_pos): return -1
	stub._pending_respawn_choice = {"mode": "soulbind", "position": Vector3(5, -3, 7)}
	var rock_rise: bool = rs.initiate_respawn(stub, "")
	_ok(rock_rise and rs.soulbind_count({"entity_id": "soul_link_2"}) == 1, "the rock fall priced one ticket")
	_ok(stub._pending_respawn_position != Vector3(5, -3, 7), "a rock-owned fall ignores the death spot: a safe ground nearby")
	# The real ocean door's own verdict: an UNCLAIMED column is not a
	# guess -- the door refuses it as rock (conservative: never drown a
	# second body, never stand a body inside stone), so the seat buys a
	# safe ground nearby instead. The fail-dry property is the seam's
	# law (the dry leg above), not the real door's guess.
	rs._depth_resolver = null
	stub._pending_respawn_mode_int = null
	stub._pending_respawn_position = null
	stub._pending_respawn_choice = {"mode": "soulbind", "position": Vector3(300000, 0, 0)}
	var dry_fallback: bool = rs.initiate_respawn(stub, "")
	_ok(dry_fallback and rs.soulbind_count({"entity_id": "soul_link_2"}) == 0 and stub._pending_respawn_position != Vector3(300000, 0, 0),
		"the real door refuses unclaimed columns as rock and buys a safe ground nearby; the ticket spent honestly")

	# ---- THE LIFELINE LAW (past the clergy gate, paid at the book) ------
	var healer := StubBody.new()
	healer.entity_id = "soul_link_healer"
	healer.display_name = "Soulprobe Healer"
	root.add_child(healer)
	var fall := StubBody.new()
	fall.entity_id = "soul_link_fall"
	fall.display_name = "Souprobe Fallen"
	fall.health_component = DeadHealth.new()
	root.add_child(fall)
	# The poor lay helper: refused BY NAME, paid nothing.
	_ok(rs.start_revival(healer, fall, "contested") == false, "a lay helper with no ticket is refused by the clergy gate")
	_ok(not rs._active_revives.has("soul_link_fall"), "a refused lifeline booked nothing")
	# The ticketed lifeline: paid one ticket AFTER every other gate held.
	_seed_wallet(healer.entity_id, 0, 1)
	var booked: bool = rs.start_revival(healer, fall, "contested")
	_ok(booked, "a ticket holder pays a lifeline through the contested context")
	_ok(rs.soulbind_count({"entity_id": "soul_link_healer"}) == 0, "the lifeline spent exactly one ticket at the book")
	_ok(rs._active_revives.has("soul_link_fall"), "the paid lifeline holds the cast book")
	rs._active_revives.erase("soul_link_fall")

	# ---- THE UI LAW (source strings, the naming-lint must) --------------
	var mgr_src := FileAccess.open("res://ui/respawn/respawn_ui_manager.gd", FileAccess.READ).get_as_text()
	var ui_src := FileAccess.open("res://ui/respawn/respawn_ui.gd", FileAccess.READ).get_as_text()
	_ok(mgr_src.contains("\"mode\": \"soulbind\"") and mgr_src.contains("Soulbind at the Fall"),
		"the death screen offers the paid stand-up when the service does")
	_ok(ui_src.contains("[SOULBIND]") and ui_src.contains("one Soulbinder's Ticket is spent"),
		"the row names its price and a11y states the ticket spent")

	print("--- SOULBIND REVIVAL: %d passed, %d failed ---" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)

func _book_drain(rs, book_id: Dictionary) -> void:
	while rs._consume_soulbind(book_id):
		pass
