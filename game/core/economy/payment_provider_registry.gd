## PaymentProviderRegistry - the plugin board for payment processors.
##
## One board holds providers by id; the default provider answers the
## PremiumShop ledger. Swapping processors is code at ONE seam:
##
##   PremiumShopService.singleton().registry().register(MyAdapter.new(), true)
##
## Nothing else in the shop path names a concrete processor. The first
## board instantiation registers ManualPaymentProvider as the seed
## default, so the shop always has an honest (money-never-moves)
## processor until a real adapter re-registers with make_default.
extends RefCounted
class_name PaymentProviderRegistry

var _providers := {}   # provider_id -> PaymentProvider
var _default_id := ""

func _init() -> void:
	if _providers.is_empty():
		var manual_script: GDScript = load("res://core/economy/manual_payment_provider.gd")
		if manual_script != null and manual_script.can_instantiate():
			register(manual_script.new(), true)

## idempotent registration by id: re-registering the same id replaces
## the provider (THE swap law). make_default also re-points the ledger.
func register(provider, make_default: bool = false) -> void:
	var pid := str(provider.get_id())
	if pid.is_empty():
		return
	_providers[pid] = provider
	if make_default or _default_id == "":
		_default_id = pid

func get_provider(id: String):
	return _providers.get(id, null)

func get_default_provider():
	return _providers.get(_default_id, null)

func get_default_provider_id() -> String:
	return _default_id

func list_providers() -> Array:
	var out: Array = []
	for pid in _providers:
		out.append({"id": pid, "display_name": _providers[pid].get_display_name()})
	return out
