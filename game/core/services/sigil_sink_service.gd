## SigilSinkService - THE CONCORD SINK CATALOG: real prices on real services.
##
## The processor SKUs (sigil_100/280/650 through the webhook armor) are how
## Concord Sigils ENTER a wallet; this catalog is where they LEAVE it -- spent
## on things that already exist behind real service doors:
##   - Mounts: RideService's ownership book (KV persisted, soulbound-by-posture
##     duplicates refused at grant). Every sink id must resolve
##     DataService.get_mount truth; the GM Skywarden mount is NOT for sale
##     (grant_mount itself refuses it for non-wardens and this catalog
##     refuses it one gate earlier).
##   - Titles: TitleService.unlock (data/titles/ defs; the two premium
##     editions declare UnlockMethod.PURCHASE -- a schema value that existed
##     at birth and now earns its emit-leg).
##   - Resurrection: the Soulbinder's Ticket. The RESPAWN kind's grant leg
##     stamps `item_soulbind_ticket` copies into the rider's BAG (InventoryService
##     -- the one purse law holds; ticket stacks are stamped as per-slot
##     duplicates like every bag add). The ticket itself is a PREPAID permit:
##     it is consumed by RespawnService's death cycle (SELF_REVIVE at the
##     death screen, or the party lifeline in start_revival), never by
##     hand at the bag's use door -- an inert book is honest for a permit.
##     RESPAWN rows are stackable permits, so the ALREADY-OWNED law does
##     not gate them: a raider buys charges, not a duplicate prize.
##
## Book law (the economy audit talks): every purchase is GATE BEFORE BOOKS
## (availability, unknown id, already owned, exact-need affordability, QoS
## rate limit) and DEBIT BEFORE GRANT with a REFUND on any failed grant leg --
## the books never keep a sigil without paying the prize, and a refund that
## cannot pay is a hard GameLog.error. Every sale is a GL.info audit line and
## one purchase_granted emit for the panel.
##
## Wallet law: sigils ride the ONE purse (InventoryComponent via
## InventoryService); no sink ever touches gold.
##
## Panel law: PremiumShopUI's sink rows read get_catalog() (which stamps
## owned state off the real books at read time) and refresh on
## purchase_granted. A sink the rider already owns stays visible as OWNED --
## it tells the truth about where the money went.
extends Node

## Singleton instance (the PremiumShopService dialect: one instance per
## process, lazily built, no _ready state).
static var _instance = null
static func singleton():
	if _instance == null:
		_instance = load("res://core/services/sigil_sink_service.gd").new()
	return _instance

const PremiumShopServiceScript = preload("res://core/services/premium_shop_service.gd")
const CURRENCY_ID := "currency_concord_sigil"
const SOULBIND_ITEM_ID := "item_soulbind_ticket"
const RATE_LIMIT_ACTION := "sigil_sink_purchase"

## The kinds a catalog row can ride. "mount" and "title" are the only
## grant legs implemented; anything else must not ship until its grant
## leg ships WITH it (no fake sinks).
enum SinkKind { MOUNT, TITLE, RESPAWN }

## THE CATALOG: priced against the processor SKUs (sigil_100 is the $4.99
## floor, 650 is the $24.99 pack). Ladder: the honest entry ride sits at
## ~$7.50 equivalent water-level for a starter game, deep-sea and sky
## tiers climb from there. Only mounts whose datum declares
## source == MountSource.VENDOR are sold here; DROP/QUEST/EVENT/FACTION/GM
## sources keep their earn paths.
const SINKS := [
	{"sink_id": "respawn_soulbind_ticket", "kind": SinkKind.RESPAWN, "sigils": 25,
	"quantity": 1,
	"display_name": "Soulbinder's Ticket",
	"detail": "One in-place resurrection: stand up where you fell (the sea's spot pays back a safe ground nearby), or pay it at a fallen ally when no healer reaches."},
	{"sink_id": "respawn_soulbind_eight", "kind": SinkKind.RESPAWN, "sigils": 150,
	"quantity": 8,
	"display_name": "Soulbinder's Slice (x8)",
	"detail": "Eight Soulbinder's Tickets for the price of six -- the raider's pocket set."},
	{"sink_id": "mount_meadow_pacer", "kind": SinkKind.MOUNT, "sigils": 150,
	"display_name": "Meadow Pacer",
	"detail": "Every rider's first horse -- bought at the pillar shrine of the Concord."},
	{"sink_id": "mount_plains_runner", "kind": SinkKind.MOUNT, "sigils": 250,
	"display_name": "Plains Runner",
	"detail": "The long-stride courier's horse of the plains roads."},
	{"sink_id": "mount_reef_glider", "kind": SinkKind.MOUNT, "sigils": 400,
	"display_name": "Reef Glider",
	"detail": "A reef swimmer bred for the shiplanes; prefers a warm shallow."},
	{"sink_id": "mount_trench_wyrm", "kind": SinkKind.MOUNT, "sigils": 650,
	"display_name": "Trench Wyrm",
	"detail": "Pressure-hardened deep swimmer; the underworld aquifers will still try to burn your boots."},
	{"sink_id": "mount_storm_lancer", "kind": SinkKind.MOUNT, "sigils": 900,
	"display_name": "Storm Lancer",
	"detail": "The sky lancer of the storm roads -- fly over the storm, not into it."},
	{"sink_id": "title_pillarsworn", "kind": SinkKind.TITLE, "sigils": 200,
	"display_name": "Title: Pillarsworn",
	"detail": "Equips as a prefix or suffix; the Concord's sworn pillar attendee."},
	{"sink_id": "title_deepseabaron", "kind": SinkKind.TITLE, "sigils": 500,
	"display_name": "Title: Deep Sea Baron",
	"detail": "Equips as a prefix or suffix; a tallow-crown merchant of the Sundered Sea."},
]

signal sink_purchased(player_id: String, sink_id: String, sigils: int)

## Injectable grant resolvers (the transport-receipt seam): a script-mode
## receipt injects a refusing stub to exercise the REFUND leg honestly.
## Default resolution goes through the real doors at call time.
var _ride_resolver: Callable = Callable()
var _title_resolver: Callable = Callable()

func _inv_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("InventoryService")) if tree and tree.root else null

func _data_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("DataService")) if tree and tree.root else null

func _glog():
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameLog")) if tree and tree.root else null

func _inventory_of(player_id: String) -> InventoryComponent:
	var svc := _inv_svc()
	if svc == null or not svc.has_method("get_inventory"):
		return null
	var inv = svc.get_inventory(player_id)
	if inv == null or not is_instance_valid(inv):
		return null
	return inv

func get_catalog(player_id: String = "") -> Array:
	var rows: Array = []
	for sink in SINKS:
		var row: Dictionary = {
			"sink_id": str(sink.get("sink_id")),
			"kind": sink.get("kind"),
			"kind_name": "mount" if sink.get("kind") == SinkKind.MOUNT else ("respawn" if sink.get("kind") == SinkKind.RESPAWN else "title"),
			"sigils": int(sink.get("sigils", 0)),
			"display_name": str(sink.get("display_name", "")),
			"detail": str(sink.get("detail", "")),
			"owned": false,
		}
		if player_id != "":
			row["owned"] = _owned(player_id, row)
		rows.append(row)
	return rows

func get_sink(sink_id: String) -> Dictionary:
	for sink in SINKS:
		if str(sink.get("sink_id")) == sink_id:
			return sink
	return {}

func _owned(player_id: String, row: Dictionary) -> bool:
	match row.get("kind"):
		SinkKind.MOUNT:
			var rs = _ride_svc()
			if rs != null and rs.has_method("owns_mount"):
				return rs.call("owns_mount", player_id, row.get("sink_id"))
		SinkKind.TITLE:
			var hgw = _title_svc()
			if hgw != null:
				return bool(hgw.call("_has_title", player_id, _title_data_id(row.get("sink_id"))))
	return false

func _ride_svc() -> Node:
	if _ride_resolver.is_valid():
		return _ride_resolver.call()
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("RideService")) if tree and tree.root else null

func _title_svc() -> Node:
	# The TitleService autoload has NO class_name, so bare static calls
	# do not compile outside full-project context: resolve the node and
	# call the same instance impls the static facade wraps.
	if _title_resolver.is_valid():
		return null  # the injected lambda takes the title leg instead
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("TitleService")) if tree and tree.root else null

func _title_unlock(player_id: String, title_id: String) -> bool:
	if _title_resolver.is_valid():
		return bool(_title_resolver.call(player_id, title_id))
	var gw := _title_svc()
	if gw == null or not gw.has_method("_do_unlock"):
		return false
	return bool(gw.call("_do_unlock", player_id, title_id))

func _title_data_id(sink_id: String) -> String:
	# Catalog title rows ride the TitleData id with the "title_" file
	# convention stripped -- one name space, no aliasing.
	return sink_id.trim_prefix("title_")

## THE BUY LEG. Refuses (named) before any book moves, debits once, grants
## once, refunds on a failed grant, settles the audit line last. Returns
## {success, reason?, granted?} -- the panel toasts either way.
func buy_sink(player_id: String, sink_id: String) -> Dictionary:
	var refused: Dictionary = {"success": false}
	if player_id.is_empty():
		return refused.merged({"reason": "no rider"})

	var sink := get_sink(sink_id)
	if sink.is_empty():
		return refused.merged({"reason": "unknown sink '%s'" % sink_id})

	# GATE BEFORE BOOKS: the grant door must be available BEFORE the debit
	# leg moves (a wallet cannot afford a service that does not exist here).
	var rs = _ride_svc() if sink.get("kind") == SinkKind.MOUNT else null
	if sink.get("kind") == SinkKind.MOUNT and (rs == null or not rs.has_method("grant_mount")):
		return refused.merged({"reason": "the mounted-stable door is not available"})
	if sink.get("kind") == SinkKind.TITLE and _title_data_id(sink_id).is_empty():
		return refused.merged({"reason": "no such degree"})
	var ds := _data_svc()
	if sink.get("kind") == SinkKind.RESPAWN and (ds == null or not ds.has_method("get_item") or ds.call("get_item", SOULBIND_ITEM_ID) == null):
		return refused.merged({"reason": "the Soulbinder's Ticket has no datum"})
	# ALREADY OWNED: the truth exists and the dupe refuses BEFORE the
	# debit. Respawn permits are stackable charges, not one-per-rider
	# prizes -- a raider buys tickets three times and holds three.
	if sink.get("kind") != SinkKind.RESPAWN and _owned(player_id, {"kind": sink.get("kind"), "sink_id": sink_id}):
		return refused.merged({"reason": "already owned"})

	# The GM wyrd mount is never purchasable (one gate EARLIER than the
	# service's fail-closed -- the buyer never gets within a debit of it).
	if sink.get("kind") == SinkKind.MOUNT and ds != null and ds.has_method("get_mount"):
		var mount = ds.call("get_mount", sink_id)
		if mount == null:
			return refused.merged({"reason": "no such steed"})
		if int(mount.get("source")) == 5:  # MountSource.GM
			return refused.merged({"reason": "the Skywarden's mount is not for sale"})

	var cost: int = int(sink.get("sigils", 0))
	if cost <= 0:
		return refused.merged({"reason": "catalog row carries no price"})

	var inv: InventoryComponent = _inventory_of(player_id)
	if inv == null:
		return refused.merged({"reason": "no mounted wallet for %s" % player_id})

	var balance: int = int(inv.get_currency_amount(CURRENCY_ID))
	if balance < cost:
		return refused.merged({"reason": "need %d Concord Sigils (have %d)" % [cost, balance]})

	# QoS (named in the shop law) BEFORE the debit leg.
	var qos: Node = QoSService.singleton()
	if qos != null and not qos.call("_rate_limit_impl", player_id, RATE_LIMIT_ACTION):
		return refused.merged({"reason": "rate limited; slow down"})

	# THE DEBIT. An honest ledger remove; a refusal here moves nothing.
	if not inv.remove_currency(CURRENCY_ID, cost):
		return refused.merged({"reason": "the ledger refused the %d-sigil debit" % cost})

	# THE GRANT. A failed grant leg REFUNDS the debit in full.
	var granted := false
	var grant_detail := ""
	match sink.get("kind"):
		SinkKind.MOUNT:
			granted = bool(rs.call("grant_mount", player_id, sink_id))
			grant_detail = "stable"
		SinkKind.TITLE:
			granted = _title_unlock(player_id, _title_data_id(sink_id))
			grant_detail = "herald"
		SinkKind.RESPAWN:
			var ticket = ds.call("get_item", SOULBIND_ITEM_ID)
			granted = bool(inv.add_item(ticket, int(sink.get("quantity", 1))))
			grant_detail = "bag"
	if not granted:
		var balance_after: int = int(inv.get_currency_amount(CURRENCY_ID))
		var refund_ok: bool = inv.add_currency(CURRENCY_ID, cost)
		var after_retry: int = int(inv.get_currency_amount(CURRENCY_ID))
		var gl = _glog()
		if not refund_ok or after_retry != balance_after + cost:
			if gl:
				gl.error("SigilSinkService: the %s grant FAILED for %s and the %d-sigil REFUND DID NOT LAND (books owed: %d sigils). See SigilSinkService %s." % [grant_detail, player_id, cost, cost, sink_id])
		else:
			if gl:
				gl.info("SigilSinkService: the %s grant failed for %s; the %d-sigil debit was refunded in full (books whole)." % [grant_detail, player_id, cost])
		return refused.merged({"reason": "the %s door refused; %d sigils refunded" % [grant_detail, cost]})

	# THE AUDIT LINE + THE PANEL VOICE.
	var gl2 = _glog()
	if gl2:
		gl2.info("SigilSinkService: %s paid %d Concord Sigils for %s (%s)" % [player_id, cost, sink_id, grant_detail])
	sink_purchased.emit(player_id, sink_id, cost)
	return {"success": true, "sink_id": sink_id, "granted": grant_detail, "sigils": cost}
