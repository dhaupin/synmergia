## Receipt: the minimap vendor marker reads REAL vendor truth.
##
## Regression: minimap.gd classified NPCs by npc_data.get("services") -- a
## field NPCData never declared (a phantom the K3 round removed). Godot drops
## undeclared fields on load, so the read always returned [] and MARKER_VENDOR
## was unreachable via NPCData. The fix resolves vendor-ness from the offering
## model (NPCEntity.is_vendor) and the minimap calls that.
##
## Pure classification receipt: no UI tree (the minimap's _ready build blocks
## in --script mode); _npc_marker_type needs only the entity.
extends SceneTree

const MinimapScript := "res://ui/components/minimap.gd"
const NpcEntityScript := "res://core/entities/npc_entity.gd"

func _init() -> void:
	call_deferred("_run")

func _npc(path: String):
	var e = load(NpcEntityScript).new()
	e.npc_data = load(path)
	return e

func _run() -> void:
	var ok := true
	var mm = load(MinimapScript).new()

	# 1. A plain node is a plain NPC -- never assume a vendor.
	if mm._npc_marker_type(Node.new()) != mm.MARKER_NPC:
		push_error("FAIL: plain node classified as vendor")
		ok = false

	# 2. Real vendor NPC (ref-based offering type "vendor") -> MARKER_VENDOR.
	var vendor = _npc("res://data/npc/npc_armory_capital.tres")
	if not vendor.is_vendor():
		push_error("FAIL: armory NPC is_vendor() false")
		ok = false
	if mm._npc_marker_type(vendor) != mm.MARKER_VENDOR:
		push_error("FAIL: armory NPC not classified MARKER_VENDOR")
		ok = false

	# 3. Service NPC (offering type "service") -> MARKER_NPC.
	if mm._npc_marker_type(_npc("res://data/npc/npc_blacksmith_capital.tres")) != mm.MARKER_NPC:
		push_error("FAIL: blacksmith service NPC misclassified as vendor")
		ok = false

	# 4. Bank NPC -> MARKER_NPC.
	if mm._npc_marker_type(_npc("res://data/npc/npc_banker_capital.tres")) != mm.MARKER_NPC:
		push_error("FAIL: bank NPC misclassified as vendor")
		ok = false

	# 5. Inline vendor include ({type: "vendor"}) -> MARKER_VENDOR.
	var inline = _npc("res://data/npc/npc_armory_capital.tres")
	inline.npc_data = inline.npc_data.duplicate()
	var inline_includes: Array[Dictionary] = [{"type": "vendor", "ref_id": "armory"}]
	inline.npc_data.includes = inline_includes
	if mm._npc_marker_type(inline) != mm.MARKER_VENDOR:
		push_error("FAIL: inline vendor include not classified MARKER_VENDOR")
		ok = false

	# 6. The spawn router routes NPCs through the classifier.
	var src := FileAccess.get_file_as_string(MinimapScript)
	if not src.contains("_npc_marker_type(entity)"):
		push_error("FAIL: NPC spawn branch does not use _npc_marker_type")
		ok = false

	# 7. The phantom read is gone from the source.
	if src.contains("services"):
		push_error("FAIL: minimap still references the phantom 'services' field")
		ok = false

	print("--- MINIMAP VENDOR MARKER: ", "ALL PASS" if ok else "FAILED", " ---")
	quit(0 if ok else 1)
