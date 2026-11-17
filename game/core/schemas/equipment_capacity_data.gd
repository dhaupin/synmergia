## EquipmentCapacityData - the data-authored accessory capacity table.
##
## The component owns equip legality; this record owns how many lanes each
## accessory family has. Designers can raise or lower a count without adding
## code: ten rings, three amulets, two belts, and so on. The appended equip
## slots are the available ceiling; a count above the authored ceiling is
## rejected by is_valid() rather than silently clamped.
extends Resource
class_name EquipmentCapacityData

const MAX_RING_SLOTS: int = 10
const MAX_AMULET_SLOTS: int = 3
const MAX_BELT_SLOTS: int = 3
const MAX_CLOAK_SLOTS: int = 3

@export var id: String = "equipment_capacity"
@export var ring_slots: int = 2
@export var amulet_slots: int = 1
@export var belt_slots: int = 1
@export var cloak_slots: int = 1


## Count for one capacity family ("ring", "amulet", "belt", "cloak").
func capacity_for_family(family: String) -> int:
	match family:
		"ring":
			return ring_slots
		"amulet":
			return amulet_slots
		"belt":
			return belt_slots
		"cloak":
			return cloak_slots
		_:
			return 0


func is_valid() -> bool:
	if id.is_empty():
		return false
	return ring_slots >= 0 and ring_slots <= MAX_RING_SLOTS \
		and amulet_slots >= 0 and amulet_slots <= MAX_AMULET_SLOTS \
		and belt_slots >= 0 and belt_slots <= MAX_BELT_SLOTS \
		and cloak_slots >= 0 and cloak_slots <= MAX_CLOAK_SLOTS
