## DeepGardenBinder -- S14.7.3: one world-side listener that joins the
## S14.7.2 harvest truth (HarvestService's depletion book) to the
## S14.7.2 paint (the streamer's deep_garden groves).
##
## THE LAW: an entity registration and its visual half are ONE
## placement; the same register call that mints `deep_kelp_<f>_<b>_<k>`
## nodes also stamps each grove with meta `harvest_ids` = the ids of
## the three plants that bed owns. This binder subscribes to
## HarvestService's harvest_completed + node_respawned and re-evaluates
## the cove's paint: while ALL of a grove's plants are depleted the
## grove hides (the cove stands empty -- the kelp is taken, the
## pearls are pocketed), and any respawn reveals it again. Leaf-empty
## beds (a grove whose nodes were never registered, e.g. a bare host
## with terrain off) keep their paint: the binder never invents a
## depletion the service does not declare.
##
## The streamer may RE-apply a face (re-derive after a revisit). That
## can re-register nodes and rebuild the grove; the refresh is
## idempotent (it only reads the service's current book), and binding
## is guarded so double-connect is impossible. RefCounted with static
## functions, the HarborLights idiom: no autoload, no node. Declared
## signals are typed, connected callables stay untyped (the
## ChatService lesson: typed lambdas on typed signals receive
## nothing).
extends RefCounted

const BIND_META := "deep_garden_binder_bound"

static func _svc_from(root: Node):
	var tree := root.get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath("HarvestService"))


## Join the two halves once per world root.
static func bind(root: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	var svc = _svc_from(root)
	if svc == null or not svc.has_method("is_depleted"):
		return
	if root.has_meta(BIND_META) and bool(root.get_meta(BIND_META)):
		return
	root.set_meta(BIND_META, true)
	if svc.has_signal("harvest_completed"):
		svc.harvest_completed.connect(_on_harvest.bind(root))
	if svc.has_signal("node_respawned"):
		svc.node_respawned.connect(_on_respawn.bind(root))
	refresh(root)


## A cove changed: re-judge the paint from the service's own book.
static func _on_harvest(_player_id: String, node_id: String,
		_item_id: String, _qty: int, root: Node) -> void:
	refresh(root)


static func _on_respawn(_node_id: String, root: Node) -> void:
	refresh(root)


## The paint law: hide a grove exactly when the service says every
## plant it owns is depleted; reveal on any breath left in the bed.
static func refresh(root: Node) -> void:
	var svc = _svc_from(root)
	if svc == null or not svc.has_method("is_depleted"):
		return
	for grove in root.get_tree().get_nodes_in_group("deep_garden"):
		if grove == null or not is_instance_valid(grove) \
				or not grove.has_meta("harvest_ids"):
			continue
		var ids: Array = grove.get_meta("harvest_ids")
		if ids.is_empty():
			continue
		var all_taken := true
		for nid in ids:
			var seen: bool = svc.call("is_depleted", str(nid))
			if not seen:
				all_taken = false
				break
		grove.visible = not all_taken
