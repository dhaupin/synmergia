## AgentConnector - Base interface for AI agent connectors
## Allows AI agents (Vant, Claude, GPT, Gemini, etc.) to connect and play
class_name AgentConnector
extends Node

enum ConnectorStatus {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	ERROR,
	RECONNECTING
}

enum AgentType {
	VANT,          # Vant OS / runtime
	CLAUDE,        # Anthropic Claude
	OPENAI,        # OpenAI GPT
	GEMINI,        # Google Gemini
	CUSTOM,        # Custom implementation
	PLAYER         # Human player (fallback)
}

signal status_changed(status: ConnectorStatus)
signal action_received(action: AgentAction)
signal observation_ready(observation: Dictionary)
signal error_occurred(error_message: String)

@export var connector_name: String = "Connector"
@export var agent_type: AgentType = AgentType.CUSTOM
@export var is_enabled: bool = true

var _status: ConnectorStatus = ConnectorStatus.DISCONNECTED
var _agent_id: String = ""
var _config: Dictionary = {}

## Required: Connect to the agent
func connect(config: Dictionary) -> bool:
	_config = config
	_set_status(ConnectorStatus.CONNECTING)
	return false  # Override in subclass

## Required: Disconnect from the agent
func disconnect() -> void:
	_set_status(ConnectorStatus.DISCONNECTED)

## Required: Send observation/state to agent
func send_observation(observation: Dictionary) -> void:
	# Override in subclass to send via MCP/API/etc.
	pass

## Required: Get action space (what agent can do)
func get_action_space() -> Dictionary:
	return {
		"movement": {
			"type": "discrete",
			"actions": ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint"]
		},
		"combat": {
			"type": "discrete",
			"actions": ["attack", "cast_skill_1", "cast_skill_2", "cast_skill_3", "cast_skill_4", "dodge"]
		},
		"interaction": {
			"type": "discrete",
			"actions": ["interact", "pickup", "drop", "use_item"]
		},
		"targeting": {
			"type": "continuous",
			"range": [-180, 180]  # Camera rotation in degrees
		},
		"target_selection": {
			"type": "discrete", 
			"actions": ["target_nearest_enemy", "target_next_enemy", "target_previous_enemy", "clear_target"]
		}
	}

## Required: Get observation space (what agent sees)
func get_observation_space() -> Dictionary:
	return {
		"position": {"type": "continuous", "shape": [3]},  # Vector3
		"health_percent": {"type": "continuous", "range": [0, 1]},
		"mana_percent": {"type": "continuous", "range": [0, 1]},
		"nearby_entities": {"type": "list", "max_size": 50},
		"target_info": {"type": "dict"},
		"active_buffs": {"type": "list", "max_size": 32},
		"cooldowns": {"type": "dict"}
	}

## Required: Parse action from agent
func parse_action(action_data: Dictionary) -> AgentAction:
	var action := AgentAction.new()
	action.action_type = action_data.get("type", "unknown")
	action.parameters = action_data.get("parameters", {})
	action.timestamp = Time.get_ticks_msec()
	return action

## Get current status
func get_status() -> ConnectorStatus:
	return _status

## Check if connected
func is_connected() -> bool:
	return _status == ConnectorStatus.CONNECTED

func _set_status(new_status: ConnectorStatus) -> void:
	if _status != new_status:
		_status = new_status
		status_changed.emit(new_status)

## Build observation from entity state
func build_observation(entity: SynmergiaEntity) -> Dictionary:
	var obs: Dictionary = {
		"timestamp": Time.get_ticks_msec(),
		"entity_id": entity.entity_id,
		"position": {
			"x": entity.global_position.x,
			"y": entity.global_position.y,
			"z": entity.global_position.z
		}
	}
	
	# Health/Mana/Stamina
	if entity.health_component:
		obs["health_percent"] = entity.health_component.get_health_percent()
	
	obs["mana_percent"] = float(entity.current_mana) / float(entity.max_mana) if entity.max_mana > 0 else 1.0
	obs["stamina_percent"] = float(entity.current_stamina) / float(entity.max_stamina) if entity.max_stamina > 0 else 1.0
	
	# Level info
	obs["level"] = entity.level
	obs["xp_percent"] = entity.xp / entity.xp_to_next_level if entity.xp_to_next_level > 0 else 1.0
	
	# Nearby entities (simplified)
	var nearby: Array = []
	var nearby_entities = EntityService.get_entities_in_radius(entity.global_position, 30.0)
	for e in nearby_entities:
		if e == entity:
			continue
		nearby.append({
			"id": e.entity_id,
			"name": e.display_name,
"type": SynmergiaEntity.EntityType.keys()[e.entity_type],
			"distance": entity.global_position.distance_to(e.global_position),
			"is_enemy": EntityService.is_enemy(entity, e)
		})
	obs["nearby_entities"] = nearby
	
	# Target info
	if entity.target:
		var t = entity.target
		obs["target"] = {
			"id": t.entity_id,
			"name": t.display_name,
			"distance": entity.global_position.distance_to(t.global_position)
		}
		if t.health_component:
			obs["target"]["health_percent"] = t.health_component.get_health_percent()
	
	# Active buffs/debuffs
	if entity.aura_component:
		obs["active_buffs"] = []
		for buff in entity.aura_component.get_all_buffs():
			obs["active_buffs"].append(buff.buff_id)
		obs["active_debuffs"] = []
		for debuff in entity.aura_component.get_all_debuffs():
			obs["active_debuffs"].append(debuff.status_type)
	
	# Combat state
	if entity.combat_component:
		obs["is_casting"] = entity.combat_component.is_casting
		obs["gcd_remaining"] = entity.combat_component.get_gcd_remaining()
	
	return obs
