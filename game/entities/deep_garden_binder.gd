## DeepGardenBinder -- S14.7.3: one world-side listener that joins the
## S14.7.2 harvest truth (HarvestService's depletion book) to the
## S14.7.2 paint (the streamer's deep_garden groves).
##
## THE LAW: an entity registration and its visual half are ONE
## placement; the same register call that mints `deep_kelp_<f>_<b>_<k>`
## nodes also stamps each grove with meta `harvest_ids` = the ids of
## the three plants that bed owns. This binder subscribes to
## HarvestService's harvest_completed + node_respawned and re-evaluates
## the cove's paint PER PLANT (S14.7.4): a taken plant shears to its
## own stump until THAT plant's respawn comes back; the cove stands
## through it (the reef, the stones -- furniture is not loot). Leaf-empty
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


## A plant changed: re-judge the paint from the service's own book.
static func _on_harvest(_player_id: String, node_id: String,
		_item_id: String, _qty: int, root: Node) -> void:
	refresh(root)


static func _on_respawn(_node_id: String, root: Node) -> void:
	refresh(root)


## The paint law (S14.7.4, per-plant): the grove is the cove's own
## furniture and STAYS -- reef boulders, drowned stones; the cove does
## not vanish. A TAKEN PLANT shears to a stump: the strands/spires
## standing on that plant (their `plant_k` meta, stamped at derive
## time) stand down and that plant's Stump<k> shows; a respawn brings
## the plant back and hides the stump. A plant whose service id says
## nothing about depletion is a live plant -- never a hidden one
## (fail-open on paint is honest: paint never invents a depletion).
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
		# One read of the service per PLANT (ids[k] owns plant k).
		var gone: Dictionary = {}
		for k in range(ids.size()):
			gone[k] = bool(svc.call("is_depleted", str(ids[k])))
		for child in grove.get_children():
			var mesh := child as MeshInstance3D
			if mesh == null or not mesh.has_meta("plant_k"):
				continue
			var k: int = int(mesh.get_meta("plant_k"))
			if k < 0 or not gone.has(k):
				continue
			if str(mesh.name).begins_with("Stump"):
				mesh.visible = gone[k]
			else:
				mesh.visible = not gone[k]
