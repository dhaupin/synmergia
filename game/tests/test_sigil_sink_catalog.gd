extends SceneTree

## Sigil sink catalog receipt: the Concord's MIRROR DOOR gets its own
## honest books. The vault panel's IN half is proven elsewhere (the
## premium loop, the gamble, the webhook receipts); this one proves the
## OUT half -- where sigils LEAVE the ONE purse for real engine prizes:
##   1. THE CATALOG IS REAL: every mount row deciphers to DataService
##      mount truth with a non-GM source; every title row deciphers to a
##      real TitleData unlocked by PURCHASE; every row positive-priced.
##   2. GATES BEFORE BOOKS: unknown ids, a wallet-less buyer, and a
##      broke rider are refused BY NAME with the books untouched.
##   3. THE BUY PAYS EXACTLY ONCE: the Meadow Pacer lands in
##      RideService's ownership book for exactly 150; the Pillarsworn
##      title lands in TitleService's register for exactly 200 and
##      equips through the real equip surface; both dupes refuse
##      without a second debit.
##   4. THE REFUND LAW: a grant door that refuses returns EVERY sigil
##      the debit moved -- stable and herald legs both -- and the
##      refused stub grants no real prize.
##   5. THE SALE SPEAKS: the purchase signal rides the buyer's price
##      (the panel refresh voice) and the panel surface renders the
##      catalog.
## Run:
##   godot --headless --path . --script res://tests/test_sigil_sink_catalog.gd

const SinkServicePath = "res://core/services/sigil_sink_service.gd"
const InventoryCompPath = "res://core/components/inventory_component.gd"
const CURRENCY_ID := "currency_concord_sigil"

## Stub stable: a door with the grant surface and an always-refused leg,
## used ONLY by the injected resolvers of the fresh sink instance to
## exercise the real refund path (the webhook-transport seam pattern).
class StubStable extends Node:
	func grant_mount(_player_id: String, _mount_id: String) -> bool:
		return false

func _initialize() -> void:
	_run.call_deferred()

func _fail(msg: String) -> void:
	push_error("FAIL: " + msg)
	quit(1)

func _run() -> void:
	# Wallets first: the ONE purse mounted under each buyer.
	var inv_svc: Node = root.get_node_or_null("InventoryService")
	if inv_svc == null or not inv_svc.has_method("register_inventory"):
		_fail("InventoryService.register_inventory not reachable in script mode")
		return
	var wallets := {}
	for buyer_id in ["sink_probe", "sink_probe_yak"]:
		var comp = load(InventoryCompPath).new()
		inv_svc.call("register_inventory", buyer_id, comp)
		wallets[buyer_id] = comp
	var purse = wallets["sink_probe"]
	var yak_purse = wallets["sink_probe_yak"]
	if not purse.call("add_currency", CURRENCY_ID, 1000):
		_fail("the purse refused its truth seed")
		return

	# 1. THE CATALOG IS REAL.
	var sinks = load(SinkServicePath).singleton()
	if sinks == null:
		_fail("SigilSinkService.singleton() unavailable")
		return
	var catalog: Array = sinks.get_catalog("sink_probe")
	if catalog.size() != 7:
		_fail("the catalog is not seven honest rows: %d" % catalog.size())
		return
	var ds: Node = root.get_node_or_null("DataService")
	if ds == null:
		_fail("DataService missing")
		return
	var title_svc: Node = root.get_node_or_null("TitleService")
	if title_svc == null:
		_fail("TitleService missing")
		return
	var ride: Node = root.get_node_or_null("RideService")
	if ride == null:
		_fail("RideService missing")
		return
	for row in catalog:
		var sid := str(row.get("sink_id"))
		if int(row.get("sigils", 0)) <= 0:
			_fail("row %s carries no price" % sid)
			return
		if str(row.get("kind_name")) == "mount":
			var mount = ds.call("get_mount", sid)
			if mount == null:
				_fail("a phantom steed rides the catalog: %s" % sid)
				return
			if int(mount.get("source")) == 5:
				_fail("the Skywarden's mount is priced: %s" % sid)
				return
		else:
			var title = title_svc.call("get_title", sinks._title_data_id(sid))
			if title == null:
				_fail("a phantom degree rides the catalog: %s" % sid)
				return
			if int(title.get("unlock_method")) != 6:
				_fail("%s is not a PURCHASE degree" % sid)
				return
	print("[OK] catalog truth: 7 rows, every steed and degree real, no GM mount priced")

	# 2. GATES BEFORE BOOKS.
	var ghost: Dictionary = sinks.buy_sink("sink_probe", "mount_ghost_x")
	if bool(ghost.get("success")) or not str(ghost.get("reason")).contains("unknown sink"):
		_fail("an unknown sink was taken seriously: " + str(ghost))
		return
	var unmounted: Dictionary = sinks.buy_sink("sink_probe_nowallet", "mount_meadow_pacer")
	if bool(unmounted.get("success")) or not str(unmounted.get("reason")).contains("no mounted wallet"):
		_fail("a wallet-less buyer got a sale: " + str(unmounted))
		return
	var broke: Dictionary = sinks.buy_sink("sink_probe_yak", "mount_storm_lancer")
	if bool(broke.get("success")) or not str(broke.get("reason")).contains("need 900"):
		_fail("the broke rider did not get an exact need: " + str(broke))
		return
	if int(purse.call("get_currency_amount", CURRENCY_ID)) != 1000 or int(yak_purse.call("get_currency_amount", CURRENCY_ID)) != 0:
		_fail("a refused gate moved the books")
		return
	print("[OK] gates: unknown, wallet-less and broke all refuse by name, books untouched")

	# The purchase voice (the panel refresh), joined before any buy.
	var heard := []
	sinks.sink_purchased.connect(func(pid, sid, price):
		heard.append({"player_id": pid, "sink_id": sid, "sigils": price}))

	# 3. THE BUY PAYS EXACTLY ONCE (the stable leg).
	var purchase: Dictionary = sinks.buy_sink("sink_probe", "mount_meadow_pacer")
	if not bool(purchase.get("success")):
		_fail("the honest purchase was refused: " + str(purchase.get("reason")))
		return
	if int(purse.call("get_currency_amount", CURRENCY_ID)) != 850:
		_fail("the stable debit moved %d, not 150" % (1000 - int(purse.call("get_currency_amount", CURRENCY_ID))))
		return
	if not bool(ride.call("owns_mount", "sink_probe", "mount_meadow_pacer")):
		_fail("the stable book denies the purchase it granted")
		return
	var dupe: Dictionary = sinks.buy_sink("sink_probe", "mount_meadow_pacer")
	if bool(dupe.get("success")) or not str(dupe.get("reason")).contains("already owned"):
		_fail("the second pacer was sold: " + str(dupe))
		return
	if int(purse.call("get_currency_amount", CURRENCY_ID)) != 850:
		_fail("a refused dupe moved the books")
		return
	print("[OK] the stable leg: one Pacer for exactly 150, dupe refused without a second debit")

	# The herald leg.
	var herald: Dictionary = sinks.buy_sink("sink_probe", "title_pillarsworn")
	if not bool(herald.get("success")):
		_fail("the honest degree was refused: " + str(herald.get("reason")))
		return
	if int(purse.call("get_currency_amount", CURRENCY_ID)) != 650:
		_fail("the herald debit moved wrong: %d" % int(purse.call("get_currency_amount", CURRENCY_ID)))
		return
	if not bool(title_svc.call("_has_title", "sink_probe", "pillarsworn")):
		_fail("TitleService's register denies the purchase it granted")
		return
	var dupe2: Dictionary = sinks.buy_sink("sink_probe", "title_pillarsworn")
	if bool(dupe2.get("success")) or not str(dupe2.get("reason")).contains("already owned"):
		_fail("the second degree was sold: " + str(dupe2))
		return
	if not bool(title_svc.call("_do_equip", "sink_probe", "pillarsworn", "suffix")):
		_fail("the purchased degree could not ride the real equip surface")
		return
	print("[OK] the herald leg: Pillarsworn for exactly 200, dupe refused, equips in the real surface")

	# 4. THE REFUND LAW (both grant legs, stub doors that refuse).
	var cold = load(SinkServicePath).new()
	var stable_stub := StubStable.new()
	root.add_child(stable_stub)
	cold._ride_resolver = func():
		return stable_stub
	var refund1: Dictionary = cold.buy_sink("sink_probe", "mount_plains_runner")
	if bool(refund1.get("success")) or not str(refund1.get("reason")).contains("refunded"):
		_fail("the refused stable leg did not name the refund: " + str(refund1))
		return
	if int(purse.call("get_currency_amount", CURRENCY_ID)) != 650:
		_fail("the stable refund left books owed: %d (need 650)" % int(purse.call("get_currency_amount", CURRENCY_ID)))
		return
	cold._title_resolver = func(_player_id: String, _title_id: String) -> bool:
		return false
	var refund2: Dictionary = cold.buy_sink("sink_probe", "title_deepseabaron")
	if bool(refund2.get("success")) or not str(refund2.get("reason")).contains("refunded"):
		_fail("the refused herald leg did not name the refund: " + str(refund2))
		return
	if int(purse.call("get_currency_amount", CURRENCY_ID)) != 650:
		_fail("the herald refund left books owed: %d" % int(purse.call("get_currency_amount", CURRENCY_ID)))
		return
	if bool(ride.call("owns_mount", "sink_probe", "mount_plains_runner")):
		_fail("a refused stub granted a real steed")
		return
	if bool(title_svc.call("_has_title", "sink_probe", "deepseabaron")):
		_fail("a refused stub granted a real degree")
		return
	print("[OK] the refund law: both refused doors rewound every sigil, books whole, no phantom prize")

	# 5. THE SALE SPEAKS (and the panel surface renders the truth rows).
	if heard.size() != 2:
		_fail("the purchase voice spoke %d times of two sales" % heard.size())
		return
	if str(heard[0].get("sink_id")) != "mount_meadow_pacer" or int(heard[0].get("sigils")) != 150:
		_fail("the voice mispriced the pacer: " + str(heard[0]))
		return
	if str(heard[1].get("sink_id")) != "title_pillarsworn" or int(heard[1].get("sigils")) != 200:
		_fail("the voice mispriced the degree: " + str(heard[1]))
		return
	var panel = load("res://ui/components/premium_shop_ui.gd").new()
	root.add_child(panel)
	panel.open("sink_probe")
	if panel.get_node_or_null("Panel/Main/SinksBox") == null:
		_fail("the sink surface never built inside the vault panel")
		return
	var sink_rows: int = panel.get_node("Panel/Main/SinksBox").get_child_count()
	if sink_rows < 8:
		_fail("the sink surface rendered %d rows, not the catalog" % sink_rows)
		return
	# An owned row tells the truth (the pacer's Buy is disabled).
	var with_owned: Array = sinks.get_catalog("sink_probe")
	var owned_rows: Array = with_owned.filter(func(r): return bool(r.get("owned")))
	if owned_rows.size() < 2:
		_fail("the books did not read as owned: %d rows" % owned_rows.size())
		return
	print("[OK] the sale speaks: exactly two priced pings, the surface renders, owned rows read true")

	# Cleanup.
	stable_stub.free()
	panel.free()
	inv_svc.call("unregister_inventory", "sink_probe")
	inv_svc.call("unregister_inventory", "sink_probe_yak")
	print("SIGIL-SINK-CATALOG-ALL-OK")
	quit(0)
