## BuffBar - Active effects display
## Shows buffs/debuffs with duration timers
class_name BuffBar
extends Control

## Buff types
enum BuffType { BUFF, DEBUFF }

## Max visible buffs
const MAX_BUFFS: int = 8
const MAX_DEBUFFS: int = 8

var _buffs: Array = []
var _debuffs: Array = []
var _timer: Timer

signal buff_added(buff_id: String)
signal buff_removed(buff_id: String)

func _ready() -> void:
	_setup_ui()
	_create_timer()

func _setup_ui() -> void:
	name = "BuffBar"

func _create_timer() -> void:
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(_on_timer_tick)
	add_child(_timer)
	_timer.start()

func _on_timer_tick() -> void:
	_update_buffs()
	_update_debuffs()

func add_buff(buff_id: String, icon: Texture2D, duration: float, stack_count: int = 1, is_debuff: bool = false) -> void:
	var buff := {
	"id": buff_id,
	"icon": icon,
	"duration": duration,
	"remaining": duration,
	"stack": stack_count,
	"is_debuff": is_debuff
	}

	if is_debuff:
		if _debuffs.size() < MAX_DEBUFFS:
			_debuffs.append(buff)
	else:
		if _buffs.size() < MAX_BUFFS:
			_buffs.append(buff)

	buff_added.emit(buff_id)

func remove_buff(buff_id: String) -> void:
	var removed := false
	for i in range(_buffs.size()):
		if _buffs[i].id == buff_id:
			_buffs.remove_at(i)
			removed = true
			break
	if not removed:
		for j in range(_debuffs.size()):
			if _debuffs[j].id == buff_id:
				_debuffs.remove_at(j)
				removed = true
				break
	if removed:
		buff_removed.emit(buff_id)

func update_buff_duration(buff_id: String, remaining: float) -> void:
	for buff in _buffs:
		if buff.id == buff_id:
			buff.remaining = remaining
			return
	for debuff in _debuffs:
		if debuff.id == buff_id:
			debuff.remaining = remaining
			return

func _update_buffs() -> void:
	var to_remove := []
	for buff in _buffs:
		buff.remaining -= 1.0
		if buff.remaining <= 0:
			to_remove.append(buff.id)
	for buff_id in to_remove:
		remove_buff(buff_id)

func _update_debuffs() -> void:
	var to_remove := []
	for buff in _debuffs:
		buff.remaining -= 1.0
		if buff.remaining <= 0:
			to_remove.append(buff.id)
	for buff_id in to_remove:
		remove_buff(buff_id)

func get_buffs() -> Array:
	return _buffs

func get_debuffs() -> Array:
	return _debuffs

func has_buff(buff_id: String) -> bool:
	for buff in _buffs:
		if buff.id == buff_id:
			return true
	for debuff in _debuffs:
		if debuff.id == buff_id:
			return true
	return false
