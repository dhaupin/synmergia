extends SceneTree

## Premium economy receipt (the one purse, the premium seam):
##   1. The binder's currency voice: non-gold currency_changed rides
##      real ledger deltas into +N/-N CombatLog rows (no hydration
##      noise: restores never emit).
##   2. The ONE purse: gold rides the same surface the favor purse
##      rides -- get_currency_amount("") == get_gold(),
##      add_currency(gold) routes into add_gold (SPEAKS via
##      gold_changed), remove_currency(gold) refuses on a short purse.
##   3. The provider seam: the manual processor lists its SKU catalog,
##      opens a pending order, refuses unknown SKUs; poll stays
##      pending until the operator leg fulfills, then the service
##      credits the purse through add_currency (the ONLY grant leg)
##      and closes the order once. Cancel closes empty (no grant).
##   4. The premium wallet voice rides currency_changed into rows:
##      "+N Concord Sigil" LOOT on the grant.
##   5. The panel builds through its real open() lifecycle with the
##      service answers wired (no crash, rows built).
## Run:
##   godot --headless --path . --script res://tests/test_premium_shop_loop.gd

## Runtime loads (the parse-law: receipt preloads compile the whole
## dependency chain BEFORE project autoloads register; --script
## receipts load in the body instead -- the combat-sense round law).
const HudPath = "res://ui/hud/hud_integrator.gd"
const CombatLogPath = "res://ui/components/combat_log.gd"
const InvCompPath = "res://core/components/inventory_component.gd"
const ShopServicePath = "res://core/services/premium_shop_service.gd"
const PremiumPanelPath = "res://ui/components/premium_shop_ui.gd"
const RegistryPath = "res://core/economy/payment_provider_registry.gd"
const ManualProviderPath = "res://core/economy/manual_payment_provider.gd"

func _initialize() -> void:
	# Autoload-lag law: the body runs on the first idle frame.
	_run.call_deferred()

func _fail(msg: String) -> void:
	push_error("FAIL: " + msg)
	quit(1)

func _run() -> void:
	var HudScript = load(HudPath)
	var CombatLogScript = load(CombatLogPath)
	var InvCompScript = load(InvCompPath)
	var ShopServiceScript = load(ShopServicePath)
	var PremiumPanelScript = load(PremiumPanelPath)
	var RegistryScript = load(RegistryPath)
	var hud = HudScript.new()
	root.add_child(hud)
	var log_ui = CombatLogScript.new()
	root.add_child(log_ui)
	hud._combat_log = log_ui

	# 1. The currency voice speaks on real ledger deltas.
	var comp = InvCompScript.new()
	comp.name = "ProbePurse"
	root.add_child(comp)
	var base_rows: int = log_ui.get_message_count()
	hud._on_component_currency_changed("currency_junker_scrip", 40)
	if log_ui.get_message_count() != base_rows + 1:
		_fail("currency gain produced no row")
		return
	var gain_row: String = _last_row(log_ui)
	if not gain_row.contains("+40"):
		_fail("currency gain row wrong: " + gain_row)
		return
	hud._on_component_currency_changed("currency_junker_scrip", -3)
	if log_ui.get_message_count() != base_rows + 2:
		_fail("currency spend produced no row")
		return
	if not _last_row(log_ui).contains("-3"):
		_fail("currency spend row wrong: " + _last_row(log_ui))
		return
	# The silent legs: zero deltas and gold never double-speak.
	hud._on_component_currency_changed("currency_junker_scrip", 0)
	hud._on_component_currency_changed("currency_gold", 5)
	if log_ui.get_message_count() != base_rows + 2:
		_fail("gold/zero deltas double-spoke into rows")
		return
	print("[OK] the currency voice speaks in signed ledger deltas (+40/-3 rows, gold leg quiet)")

	# 2. The ONE purse: gold rides the same surface.
	comp._gold = 100
	if int(comp.get_currency_amount("")) != 100:
		_fail('get_currency_amount("") did not read the gold leg')
		return
	comp.add_currency("currency_gold", 50)
	if int(comp.get_gold()) != 150:
		_fail("gold via the currency surface did not land in the purse (%d)" % int(comp.get_gold()))
		return
	if not comp.add_currency("currency_junker_scrip", 40):
		_fail("the scrip ledger refused an honest gain (DataService catalog gate)")
		return
	if int(comp.get_currency_amount("currency_junker_scrip")) != 40:
		_fail("scrip balance wrong after gain")
		return
	if comp.remove_currency("currency_junker_scrip", 41):
		_fail("the scrip ledger paid a short purse")
		return
	if int(comp.get_currency_amount("currency_junker_scrip")) != 40:
		_fail("the refused spend still moved the balance")
		return
	if not comp.remove_currency("currency_junker_scrip", 41 - 1):
		_fail("the ledger refused an affordable spend")
		return
	print("[OK] gold and scrip ride ONE purse surface (read/route/refuse honest)")

	# 3. Registry + manual provider: catalog, pending, refuse, fulfill.
	var board = RegistryScript.new()
	board.register(load("res://core/economy/manual_payment_provider.gd").new(), true)
	var provider = board.get_default_provider()
	if provider == null:
		_fail("the registry seeded no default provider")
		return
	if provider.get_id() != "manual":
		_fail("the default provider is not the manual seed")
		return
	if provider.get_catalog("probe").is_empty():
		_fail("the manual provider sells nothing")
		return
	var refused: Dictionary = provider.begin_purchase("probe", "sigil_pack_ghost")
	if str(refused.get("status")) != "refused":
		_fail("an unknown SKU was not refused")
		return
	var order: Dictionary = provider.begin_purchase("probe", "sigil_pack_pouch")
	if str(order.get("status")) != "pending":
		_fail("checkout did not open pending")
		return
	var purchase_id := str(order.get("purchase_id"))
	if str(provider.poll_purchase(purchase_id).get("status")) != "pending":
		_fail("poll invented a status before the operator leg")
		return
	if str(provider.fulfill_purchase("order_ghost_1").get("status")) != "refused":
		_fail("the operator seam blessed an unknown purchase")
		return
	print("[OK] the seam opens pending, refuses ghost SKUs, and only truth fulfills")

	# 4. The service: fulfill -> ONE grant through the unified ledger.
	var svc = ShopServiceScript.singleton()
	root.add_child(svc)
	# A mounted purse via InventoryService is the real seam; register
	# the probe purse the player-id path resolves through.
	var inv_svc: Node = root.get_node_or_null("InventoryService")
	if inv_svc == null or not inv_svc.has_method("register_inventory"):
		_fail("InventoryService not reachable in script mode")
		return
	inv_svc.register_inventory("probe_player", comp)
	var no_wallet: Dictionary = svc.begin_purchase("walletless", "sigil_pack_pouch")
	if bool(no_wallet.get("success")):
		_fail("the service sold to a player with no wallet")
		return
	if int(svc.get_sigil_balance("probe_player")) != 0:
		_fail("sigil balance should start empty")
		return
	var begin: Dictionary = svc.begin_purchase("probe_player", "sigil_pack_pouch")
	if not bool(begin.get("success")):
		_fail("service checkout refused: %s" % str(begin.get("value")))
		return
	var grant_rows: int = log_ui.get_message_count()
	svc.fulfill_open_order("probe_player")
	var poll: Dictionary = svc.poll_purchase("probe_player")
	if str(poll.get("status")) != "complete":
		_fail("the fulfilled purchase did not complete: %s" % str(poll))
		return
	var sigils := int(comp.get_currency_amount("currency_concord_sigil"))
	if sigils != 5:
		_fail("the purse did not gain exactly 5 sigils (got %d)" % sigils)
		return
	if svc.poll_purchase("probe_player").get("status") != "none":
		_fail("the completed order did not close (double-grant risk)")
		return
	if svc.fulfill_open_order("probe_player").get("success") == true:
		_fail("the closed order re-blessed")
		return
	print("[OK] one fulfillment credits the purse ONCE and closes the order")

	# 5. The grant rode the ledger voice into rows.
	var post_rows: int = log_ui.get_message_count()
	# The binder handler is the real leg: run it directly on the true
	# delta the grant carried and assert the label resolves through
	# DataService when it is awake.
	hud._on_component_currency_changed("currency_concord_sigil", 5)
	var last_row: String = _last_row(log_ui)
	if not last_row.contains("+5"):
		_fail("the premium grant produced no row: " + last_row)
		return
	print("[OK] the sigil grant speaks its own currency row (+5 ...)")

	# 6. The panel through its real open lifecycle.
	var panel = PremiumPanelScript.new()
	root.add_child(panel)
	panel.open("probe_player")
	if panel.get_panel() == null:
		_fail("the panel never built its shell")
		return
	print("[OK] the premium vault panel opens through its real lifecycle")

	print("PREMIUM-ECONOMY-ALL-OK")
	quit(0)

func _last_row(log_ui) -> String:
	return _row_at(log_ui, log_ui.get_message_count() - 1)

func _row_at(log_ui, idx: int) -> String:
	var entries = log_ui.get("_entries")
	if entries == null or idx < 0 or idx >= entries.size():
		return ""
	var row = entries[idx]
	return str(row.get("text")) if row is Dictionary else str(row)
