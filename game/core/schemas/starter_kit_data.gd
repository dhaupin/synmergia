## StarterKitData - the new-character grant tables.
## The service owns the fresh-confirm gate and the grant/ledger behavior;
## this record owns which items and how much gold each role receives.
extends Resource
class_name StarterKitData

@export var id: String = "starter_kits"
@export var items_by_role: Dictionary = {}
## Universal grant appended to every role (the soulbound starter tablet).
## Kept separate from items_by_role so one record can never leave a role
## without the interaction-layer tool.
@export var guaranteed_items: Array = []
@export var gold_by_role: Dictionary = {}


## Item ids for a role. A missing role is an empty kit, not a fallback to
## another role's contents.
func items_for(role: int) -> Array:
	var value = items_by_role.get(role, [])
	return value if value is Array else []


## Universal item ids every role receives.
func guaranteed_for_all() -> Array:
	return guaranteed_items.duplicate()


## Starting gold for a role. A missing role grants none.
func gold_for(role: int) -> int:
	return int(gold_by_role.get(role, 0))


func is_valid() -> bool:
	if id.is_empty() or items_by_role.is_empty() or gold_by_role.is_empty():
		return false
	for role in items_by_role.keys():
		if not gold_by_role.has(role):
			return false
	return true
