## PremiumShopUI - the Concord Sigil vault panel (MenuManager "premium").
##
## The premium-interaction surface: shows the wallet's sigil balance
## (read live from the ONE purse through InventoryService), renders the
## payment provider's SKU catalog, and opens/cancels checkout through
## PremiumShopService. The panel never names a processor; it reads
## the registry truth the service hands it, so a swap is invisible to
## this file. Sigils land ONLY through the provider-reported "complete"
## leg -- the war-law: nothing here and nothing in the service mints
## without the processor's say.
extends "res://ui/components/ui_panel.gd"

class_name PremiumShopUI

const PremiumShopServiceScript = preload("res://core/services/premium_shop_service.gd")
const BlackMarketServiceScript = preload("res://core/services/black_market_service.gd")
const NotifKindScript = preload("res://core/notifications/notification_kind.gd")

## Build-once content refs (inside the base Panel/Main shell).
var _rows_box: VBoxContainer
var _status_label: Label
var _sigil_label: Label
var _rolls_box: VBoxContainer

func _setup_panel() -> void:
	set_panel_size(Vector2(460, 520))
	set_title("Concord Sigil Vault")

func _setup_content() -> void:
	# Deliberate no-op: content builds lazily in _ensure_content (the
	# ContainerUI law: the shell is deferred behind _ready, so a
	# synchronous open right after add_child would hit a half-built
	# panel; idempotent one-shot build on first use instead).
	pass

func _ensure_content() -> void:
	if _rows_box != null:
		return
	if not has_node("Panel/Main"):
		_setup_base_panel()
	var main := get_node("Panel/Main") as VBoxContainer
	if main.get_node_or_null("Sigils") == null:
		_sigil_label = Label.new()
		_sigil_label.name = "Sigils"
		_sigil_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
		main.add_child(_sigil_label)
		_status_label = Label.new()
		_status_label.name = "Status"
		_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		main.add_child(_status_label)
		_rows_box = VBoxContainer.new()
		_rows_box.name = "Rows"
		main.add_child(_rows_box)
		_rolls_box = VBoxContainer.new()
		_rolls_box.name = "RollsBox"
		main.add_child(_rolls_box)
	else:
		_sigil_label = main.get_node("Sigils") as Label
		_status_label = main.get_node("Status") as Label
		_rows_box = main.get_node("Rows") as VBoxContainer
		_rolls_box = main.get_node("RollsBox") as VBoxContainer
	_watch_service()

## The service is a runtime singleton (not an autoload): refresh rides
## its own state-change signal so a fulfillment done elsewhere (admin
## tool, webhook) updates the open panel with no private re-reads.
func _watch_service() -> void:
	var svc = PremiumShopServiceScript.singleton()
	if svc == null or not is_instance_valid(svc):
		return
	if not svc.purchase_state_changed.is_connected(_on_purchase_state_changed):
		svc.purchase_state_changed.connect(_on_purchase_state_changed)

func _on_purchase_state_changed(_player_id: String, _purchase_id: String, _status: String) -> void:
	_refresh()

## UIPanel open path (menu_manager's _open_panel calls open(pid)).
func _on_open() -> void:
	_ensure_content()
	_refresh()

func _refresh() -> void:
	if _rows_box == null:
		return
	for child in _rows_box.get_children():
		child.queue_free()
	var shop = PremiumShopServiceScript.singleton()
	if shop == null:
		if _status_label:
			_status_label.text = "The vault ledger is closed (service unavailable)."
		return
	var pm := get_node_or_null("/root/PlayerManager")
	var player_id := ""
	if pm != null and pm.has_method("get_local_player_id"):
		player_id = str(pm.get_local_player_id())
	if player_id == "" and pm != null:
		var lp = pm.get("local_player")
		if lp != null and is_instance_valid(lp) and "entity_id" in lp:
			player_id = str(lp.get("entity_id"))
	# The balance lives in the ONE purse (InventoryService wallet).
	_sigil_label.text = "Concord Sigils: %d" % int(shop.get_sigil_balance(player_id))
	var order = _open_order_for(shop, player_id)
	if not order.is_empty():
		_refresh_pending(shop, player_id, order)
		return
	_status_label.text = "Checkout answers to: %s" % shop.get_provider_display_name()
	for sku in shop.get_skus(player_id):
		_add_sku_row(shop, player_id, sku)
	_refresh_rolls(player_id)

func _unused(_x) -> void:
	pass

func _open_order_for(shop, player_id: String) -> Dictionary:
	if shop == null or not shop.has_method("get_open_order"):
		return {}
	var order: Variant = shop.call("get_open_order", player_id)
	return order if order is Dictionary else {}

func _refresh_pending(shop, player_id: String, order: Dictionary) -> void:
	if _status_label:
		_status_label.text = "Order %s is with the processor (%s). Fulfill it from the operator seam, or cancel here.\nNothing has been granted yet." \
			% [str(order.get("purchase_id", "")), shop.get_provider_display_name()]
	var row := HBoxContainer.new()
	var cancel := Button.new()
	cancel.text = "Cancel order"
	cancel.pressed.connect(func(): shop.cancel_purchase(player_id); _refresh())
	row.add_child(cancel)
	_rows_box.add_child(row)

func _add_sku_row(shop, player_id: String, sku: Dictionary) -> void:
	var row := PanelContainer.new()
	var hbox := HBoxContainer.new()
	row.add_child(hbox)
	var name_label := Label.new()
	name_label.text = str(sku.get("display_name", sku.get("sku_id", "?")))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_label)
	var price_label := Label.new()
	price_label.text = "%d sigils - %s" % [int(sku.get("sigils", 0)), str(sku.get("price_label", ""))]
	hbox.add_child(price_label)
	var buy := Button.new()
	buy.text = "Purchase"
	buy.pressed.connect(func():
		var result: Dictionary = shop.begin_purchase(player_id, str(sku.get("sku_id", "")))
		_notify_checkout(result)
		_refresh())
	hbox.add_child(buy)
	_rows_box.add_child(row)

func _notify_checkout(result: Dictionary) -> void:
	var ns := get_node_or_null("/root/NotificationService")
	if ns == null:
		return
	var NotifKind = NotifKindScript.NotifKind
	var ok := bool(result.get("success", false))
	ns.notify(
		NotifKind.CUSTOM,
		str(result.get("value", "Checkout opened.")),
		"PremiumShopUI",
		"premium_checkout",
		{},
		_player_id_for_toast()
	)

## THE DEEP ROLLS: the fixer's gamble surface rides into the same
## panel (sigils in, one weighted draw out of a real LootTable). The
## client sends only a roll_id; weights, item ids and amounts all stay
## server truth in BlackMarketService.
func _refresh_rolls(player_id: String) -> void:
	if _rolls_box == null:
		return
	for child in _rolls_box.get_children():
		child.queue_free()
	var market = BlackMarketServiceScript.singleton()
	if market == null or not is_instance_valid(market):
		var absent := Label.new()
		absent.text = "The deep rolls are closed (market unavailable)."
		_rolls_box.add_child(absent)
		return
	if not market.roll_granted.is_connected(_on_roll_refresh):
		market.roll_granted.connect(_on_roll_refresh)
	for option in market.get_roll_options():
		_add_roll_row(market, player_id, option)

func _add_roll_row(market, player_id: String, option: Dictionary) -> void:
	var row := PanelContainer.new()
	var hbox := HBoxContainer.new()
	row.add_child(hbox)
	var name_label := Label.new()
	name_label.text = "%s - %d sigils" % [str(option.get("label", "?")), int(option.get("sigils", 0))]
	name_label.tooltip_text = str(option.get("description", ""))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_label)
	var roll := Button.new()
	roll.text = "Roll"
	roll.pressed.connect(func():
		var result: Dictionary = market.roll_deep(player_id, str(option.get("roll_id", "")))
		_notify_roll(result)
		var shop = PremiumShopServiceScript.singleton()
		if shop != null:
			_refresh())
	hbox.add_child(roll)
	_rolls_box.add_child(row)

func _on_roll_refresh(_player_id: String, _roll_id: String, _item_id: String, _rarity: String) -> void:
	var shop = PremiumShopServiceScript.singleton()
	if shop != null:
		_refresh()

func _notify_roll(result: Dictionary) -> void:
	var ns := get_node_or_null("/root/NotificationService")
	if ns == null:
		return
	var NotifKind = NotifKindScript.NotifKind
	ns.notify(
		NotifKind.CUSTOM,
		str(result.get("message", "")),
		"BlackMarketUI",
		"black_market_roll",
		{},
		_player_id_for_toast()
	)

func _player_id_for_toast() -> String:
	var pm := get_node_or_null("/root/PlayerManager")
	if pm == null or not pm.has_method("get_local_player_id"):
		return ""
	return str(pm.get_local_player_id())
