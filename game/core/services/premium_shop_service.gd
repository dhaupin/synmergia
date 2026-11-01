## PremiumShopService - the real-money front door for Concord Sigils.
##
## The seam law: no real-money talk ever lives in gameplay code. This
## service renders the payment provider REGISTRY's catalog, opens and
## cancels checkout through the provider, and grants the wallet ONLY on
## a provider-reported "complete". The provider is swappable at the
## registry seam; this file never names a concrete processor.
##
## Wallet law: sigils ride the ONE purse (the player's mounted
## InventoryComponent, via InventoryService) through
## comp.add_currency(CURRENCY_ID, N) -- the unified ledger emits
## currency_changed, which is the ONE speak lane the HUD rows ride.
extends Node

## Runtime autoload lookups (script-mode-safe; the bare identifiers
## fail compile when autoloads are absent -- test_islands).
func _inv_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("InventoryService")) if tree and tree.root else null

func _data_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("DataService")) if tree and tree.root else null

## Script-mode-safe GameLog voice.
func _glog():
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameLog")) if tree and tree.root else null

## Singleton instance (the VendorService dialect: one instance per
## process, lazily built, no _ready state).
static var _instance = null
static func singleton():
	if _instance == null:
		_instance = load("res://core/services/premium_shop_service.gd").new()
	return _instance

const CURRENCY_ID := "currency_concord_sigil"

## Fired when a purchase completes and the purse is credited.
signal purchase_completed(player_id: String, sku_id: String, sigils: int)
## Fired when a purchase is refused/cancelled by the buyer or provider.
signal purchase_failed(player_id: String, sku_id: String, reason: String)
## Fired on every honest state change of an open order (pending ->
## complete/cancelled), so the panel refreshes on truth.
signal purchase_state_changed(player_id: String, purchase_id: String, status: String)

## player_id -> {purchase_id, sku_id, provider_id}. REBOOT LAW: open
## orders ride the DictStore KV door (chat book pattern), so a reboot
## hydrates them back -- a checkout mid-flight survives the process
## and can still be fulfilled honestly after.
var _open_orders := {}
const KV_ORDER_PREFIX := "premium:order:"

func _init() -> void:
	_hydrate_orders()

func _hydrate_orders() -> void:
	var store := DictStore.new()
	for key in store.all_keys():
		if not key.begins_with(KV_ORDER_PREFIX):
			continue
		var order = store.get_value(key)
		if order is Dictionary and not order.is_empty():
			_open_orders[key.substr(KV_ORDER_PREFIX.length())] = order

func _persist_open_order(player_id: String) -> void:
	var store := DictStore.new()
	var order: Dictionary = _open_orders.get(player_id, {})
	if order.is_empty():
		store.erase(KV_ORDER_PREFIX + player_id)
	else:
		store.set_value(KV_ORDER_PREFIX + player_id, order)

## The plugin board (lazy; seeded with the manual processor).
var _board = null

func _provider():
	var board = registry()
	if board == null:
		return null
	return board.get_default_provider()

## The plugin board (the ONE seam callers register processors on).
## Owned by this service instance so the shop path never depends on
## statics or the global class cache -- script-mode receipts and
## swappable adapters reach the same board through here.
func registry():
	if _board == null:
		var reg_script: GDScript = load("res://core/economy/payment_provider_registry.gd")
		if reg_script == null or not reg_script.can_instantiate():
			return null
		_board = reg_script.new()
	return _board

## The SKU rows the default provider sells (rendered by the panel).
func get_skus(player_id: String) -> Array:
	var provider = _provider()
	if provider == null:
		return []
	return provider.get_catalog(player_id)

## Which processor currently answers (shown by the panel; the swap seam).
func get_provider_id() -> String:
	var provider = _provider()
	return provider.get_id() if provider != null else ""

func get_provider_display_name() -> String:
	var provider = _provider()
	return provider.get_display_name() if provider != null else ""

## THE current sigil balance of a player (0 when the purse is asleep).
func get_sigil_balance(player_id: String) -> int:
	var inv: InventoryComponent = _inventory_of(player_id)
	if inv == null:
		return 0
	return inv.get_currency_amount(CURRENCY_ID)

## The buyer's open order ({} when none) -- the panel's honest read.
func get_open_order(player_id: String) -> Dictionary:
	var order: Dictionary = _open_orders.get(player_id, {})
	return order.duplicate(true)

## Open checkout: opens a provider order; opening NEVER grants. The
## returned Dictionary carries {success, value/message}.
func begin_purchase(player_id: String, sku_id: String) -> Dictionary:
	var provider = _provider()
	if provider == null:
		return {"success": false, "value": "No payment provider is registered."}
	if _inventory_of(player_id) == null:
		return {"success": false, "value": "No wallet is mounted for that player."}
	var result: Dictionary = provider.begin_purchase(player_id, sku_id)
	var status := str(result.get("status", "refused"))
	if status == "refused":
		var reason := str(result.get("reason", "provider refused"))
		purchase_failed.emit(player_id, sku_id, reason)
		return {"success": false, "value": reason}
	if status == "pending":
		_open_orders[player_id] = {
			"purchase_id": str(result.get("purchase_id", "")),
			"sku_id": sku_id,
			"provider_id": provider.get_id(),
		}
		_persist_open_order(player_id)
		purchase_state_changed.emit(player_id, str(result.get("purchase_id", "")), "pending")
		return {"success": true, "value": str(result.get("message", "Checkout opened."))}
	# Any other provider status is an honest refusal to place on record.
	var fallback_reason := str(result.get("reason", "unexpected provider status"))
	purchase_failed.emit(player_id, sku_id, fallback_reason)
	return {"success": false, "value": fallback_reason}

## Poll the buyer's open order. On provider "complete" the purse is
## credited ONCE and the order closes; on "cancelled" the order closes
## empty. The grant is the only place sigils enter gameplay here.
func poll_purchase(player_id: String) -> Dictionary:
	var order: Dictionary = _open_orders.get(player_id, {})
	if order.is_empty():
		return {"status": "none", "message": "No open order."}
	var provider = _provider()
	if provider == null:
		return {"status": "none", "message": "No payment provider is registered."}
	var purchase_id := str(order.get("purchase_id", ""))
	var provider_result: Dictionary = provider.poll_purchase(purchase_id, player_id)
	var status := str(provider_result.get("status", "refused"))
	match status:
		"complete":
			_close_order(player_id)
			var sigils := _grant_sigils(player_id, str(order.get("sku_id", "")))
			if sigils <= 0:
				return {"status": "failed", "message": "Grant refused; the purse kept the books."}
			purchase_completed.emit(player_id, str(order.get("sku_id", "")), sigils)
			return {"status": "complete", "sigils": sigils}
		"cancelled":
			_close_order(player_id)
			purchase_failed.emit(player_id, str(order.get("sku_id", "")), "Cancelled at checkout.")
			return {"status": "cancelled"}
		"pending":
			return {"status": "pending", "purchase_id": purchase_id}
		_:
			var strange_status := str(provider_result.get("reason", "provider reported %s" % status))
			_close_order(player_id)
			purchase_failed.emit(player_id, str(order.get("sku_id", "")), strange_status)
			return {"status": "cancelled", "message": strange_status}

## Cancel checkout through the provider (buyer's own seam).
func cancel_purchase(player_id: String) -> Dictionary:
	var order: Dictionary = _open_orders.get(player_id, {})
	if order.is_empty():
		return {"success": false, "value": "No open order to cancel."}
	var provider = _provider()
	if provider != null:
		provider.cancel_purchase(str(order.get("purchase_id", "")), player_id)
	_close_order(player_id)
	purchase_failed.emit(player_id, str(order.get("sku_id", "")), "Cancelled at checkout.")
	return {"success": true, "value": "Order cancelled."}

## The operator-with-provider fulfilment path stays at the SEAM
## (provider.fulfill_purchase); the service only ever reloads truth
## after poll. Exposed so an admin tool can bless the manual seed
## without reaching into provider internals.
func fulfill_open_order(player_id: String) -> Dictionary:
	var order: Dictionary = _open_orders.get(player_id, {})
	if order.is_empty():
		return {"success": false, "value": "No open order to bless."}
	var provider = _provider()
	if provider == null:
		return {"success": false, "value": "No payment provider is registered."}
	return provider.fulfill_purchase(str(order.get("purchase_id", "")))

## ---------------------------------------------------------------------------

func _close_order(player_id: String) -> void:
	var order: Dictionary = _open_orders.get(player_id, {})
	if not order.is_empty():
		purchase_state_changed.emit(player_id, str(order.get("purchase_id", "")), "closed")
	_open_orders.erase(player_id)
	_persist_open_order(player_id)

## The ONE grant leg. Validates the currency (kind PREMIUM in
## DataService truth), the SKU's sigil figure, then credits through the
## unified ledger. Returns the granted amount (0 when refused).
func _grant_sigils(player_id: String, sku_id: String) -> int:
	var sigils := _sigils_for_sku(player_id, sku_id)
	if sigils <= 0:
		var gl = _glog()
		if gl:
			gl.warn("PremiumShopService: SKU %s carries no sigils; grant refused" % sku_id)
		return 0
	var inv: InventoryComponent = _inventory_of(player_id)
	if inv == null:
		var gl = _glog()
		if gl:
			gl.warn("PremiumShopService: no mounted wallet for %s; grant refused" % player_id)
		return 0
	var ds := _data_svc()
	if ds != null and ds.has_method("get_currency"):
		var cd = ds.get_currency(CURRENCY_ID)
		if cd != null and int(cd.kind) != CurrencyData.CurrencyKind.PREMIUM:
			var gl = _glog()
			if gl:
				gl.warn("PremiumShopService: %s is not a PREMIUM currency; grant refused" % CURRENCY_ID)
			return 0
	if not inv.add_currency(CURRENCY_ID, sigils):
		var gl = _glog()
		if gl:
			gl.warn("PremiumShopService: the ledger refused the %s grant for %s" % [sku_id, player_id])
		return 0
	var gl = _glog()
	if gl:
		gl.info("PremiumShopService: %s credited %d Concord Sigils (%s)" % [player_id, sigils, sku_id])
	return sigils

func _sigils_for_sku(player_id: String, sku_id: String) -> int:
	for sku in get_skus(player_id):
		if str(sku.get("sku_id")) == sku_id:
			return int(sku.get("sigils", 0))
	return 0

## Script-mode-safe wallet resolution through InventoryService.
func _inventory_of(player_id: String) -> InventoryComponent:
	var svc := _inv_svc()
	if svc == null or not svc.has_method("get_inventory"):
		return null
	var inv = svc.get_inventory(player_id)
	if inv == null or not is_instance_valid(inv):
		return null
	return inv
