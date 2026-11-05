## ShardBusRegistry - the plugin board for cross-shard transports.
##
## One board holds buses by id; the default bus answers the coordinator's
## cross-shard fan-out. Swapping transports is code at ONE seam:
##
##   CoordinatorService.bus_registry().register(MyBus.new(), true)
##
## Nothing else in the coordinator path names a concrete transport. The
## first board instantiation registers MemoryShardBus as the seed default,
## so the mesh always has an honest (process-local) transport until a real
## one re-registers with make_default.
extends RefCounted
class_name ShardBusRegistry

var _buses := {}   # bus_id -> ShardBus
var _default_id := ""

func _init() -> void:
	if _buses.is_empty():
		var mem_script: GDScript = load("res://core/mesh/memory_shard_bus.gd")
		if mem_script != null and mem_script.can_instantiate():
			register(mem_script.new(), true)

## idempotent registration by id: re-registering the same id replaces the
## bus (THE swap law). make_default also re-points the coordinator.
func register(bus, make_default: bool = false) -> void:
	var bid := str(bus.get_id())
	if bid.is_empty():
		return
	_buses[bid] = bus
	if make_default or _default_id == "":
		_default_id = bid

func get_bus(id: String):
	return _buses.get(id, null)

func get_default_bus():
	return _buses.get(_default_id, null)

func get_default_bus_id() -> String:
	return _default_id

func list_buses() -> Array:
	var out: Array = []
	for bid in _buses:
		out.append({"id": bid, "display_name": _buses[bid].get_display_name()})
	return out
