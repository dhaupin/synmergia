## ConnectorService - Manages agent connectors
## Handles connecting/disconnecting AI agents to the game
class_name ConnectorService
extends Node
const AgentConnector = preload("res://core/schemas/agent_connector.gd")
const Skill = preload("res://core/combat/skill.gd")
const AgentAction = preload("res://core/schemas/agent_action.gd")


signal connector_registered(connector: AgentConnector)
signal connector_status_changed(connector_name: String, status: AgentConnector.ConnectorStatus)
signal agent_connected(agent_id: String, connector_type: AgentConnector.AgentType)
signal agent_disconnected(agent_id: String)

var _connectors: Dictionary = {}  # connector_name -> AgentConnector
var _connected_agents: Dictionary = {}  # agent_id -> {connector, entity}

func _ready() -> void:
	GameLog.info("ConnectorService: Ready")
	_register_default_connectors()

## Register a connector
func register_connector(connector: AgentConnector) -> void:
	var name := connector.connector_name
	_connectors[name] = connector
	connector.status_changed.connect(_on_connector_status_changed)
	connector.action_received.connect(_on_connector_action_received)
	connector.error_occurred.connect(_on_connector_error)
	connector_registered.emit(connector)
	GameLog.info("ConnectorService: Registered connector '%s'" % name)

## Unregister a connector
func unregister_connector(connector_name: String) -> void:
	if _connectors.has(connector_name):
		var connector: AgentConnector = _connectors[connector_name]
		connector.disconnect()
		_connectors.erase(connector_name)
		GameLog.info("ConnectorService: Unregistered connector '%s'" % connector_name)

## Connect an agent using a specific connector
func connect_agent(agent_id: String, connector_name: String, config: Dictionary, entity) -> bool:
	if not _connectors.has(connector_name):
		GameLog.error("ConnectorService: Unknown connector '%s'" % connector_name)
		return false
	
	var connector: AgentConnector = _connectors[connector_name]
	
	if not connector.connect(config):
		return false
	
	_connected_agents[agent_id] = {
		"connector": connector,
		"entity": entity
	}
	
	agent_connected.emit(agent_id, connector.agent_type)
	GameLog.info("ConnectorService: Agent '%s' connected via '%s'" % [agent_id, connector_name])
	return true

## Disconnect an agent
func disconnect_agent(agent_id: String) -> void:
	if _connected_agents.has(agent_id):
		var data: Dictionary = _connected_agents[agent_id]
		var connector: AgentConnector = data["connector"]
		connector.disconnect()
		_connected_agents.erase(agent_id)
		agent_disconnected.emit(agent_id)
		GameLog.info("ConnectorService: Agent '%s' disconnected" % agent_id)

## Send observation to agent
func send_observation(agent_id: String, observation: Dictionary) -> void:
	if _connected_agents.has(agent_id):
		var connector: AgentConnector = _connected_agents[agent_id]["connector"]
		connector.send_observation(observation)

## Register default connectors
func _register_default_connectors() -> void:
	# These would be autoloaded or added via plugin system
	# For now, we'll scan the connectors/ directory
	
	var connector_paths := [
		"res://connectors/vant/vant_connector.gd",
		"res://connectors/mcp/mcp_connector.gd",
		"res://connectors/claude/claude_connector.gd",
		"res://connectors/openai/openai_connector.gd",
		"res://connectors/gemini/gemini_connector.gd"
	]
	
	for path in connector_paths:
		var script: GDScript = load(path)
		if script:
			var connector: AgentConnector = Node.new()
			connector.set_script(script)
			connector.name = path.get_file().replace(".gd", "")
			add_child(connector)
			register_connector(connector)

## Handle action from connector
func _on_connector_action_received(action: AgentAction) -> void:
	var connector: AgentConnector = get_parent()
	# Find which agent this connector belongs to
	for agent_id in _connected_agents:
		var data: Dictionary = _connected_agents[agent_id]
		if data["connector"] == connector:
			_execute_action(agent_id, action)
			return

func _execute_action(agent_id: String, action: AgentAction) -> void:
	if not _connected_agents.has(agent_id):
		return
	
	var entity = _connected_agents[agent_id]["entity"]
	if not is_instance_valid(entity):
		return
	
	match action.action_type:
		AgentAction.ActionType.MOVEMENT:
			entity.move_direction = action.movement_direction
			entity.is_sprinting = action.is_sprinting
			if action.is_jumping:
				entity.jump()
		
		AgentAction.ActionType.COMBAT:
			if action.action_name == "attack":
				entity.combat_component.auto_attack(entity.target, entity.attack_power)
			elif action.action_name == "dodge":
				entity.dodge()
		
		AgentAction.ActionType.SKILL:
			var skill: Skill = DataService.get_skill(action.skill_id)
			if skill:
				entity.combat_component.execute_skill(skill, entity.target)
		
		AgentAction.ActionType.TARGETING:
			match action.parameters.get("mode", ""):
				"nearest_enemy":
					var nearest := EntityService.get_closest_entity(
						entity.global_position,
						Entity.EntityType.ENEMY,
						50.0
					)
					entity.target = nearest
				"clear":
					entity.target = null
		
		AgentAction.ActionType.INTERACTION:
			if action.action_name == "interact":
				_interact_with_target(entity, action.interact_target_id)
			elif action.action_name == "pickup":
				_pickup_nearby(entity)
		
		AgentAction.ActionType.CHAT:
			ChatService.send_message(entity, action.chat_message, action.chat_channel)

func _interact_with_target(entity, target_id: String) -> void:
	var target = EntityService.get_entity(target_id)
	if target and entity.global_position.distance_to(target.global_position) < 3.0:
		if target.has_method("on_interact"):
			target.on_interact(entity)

func _pickup_nearby(entity) -> void:
	# Find nearby items
	var nearby := EntityService.get_entities_in_radius(entity.global_position, 3.0)
	for e in nearby:
		if e.entity_type == Entity.EntityType.ITEM_DROP:
			if e.has_method("on_pickup"):
				e.on_pickup(entity)
				return

func _on_connector_status_changed(status: AgentConnector.ConnectorStatus) -> void:
	var connector: AgentConnector = get_parent()
	connector_status_changed.emit(connector.connector_name, status)

func _on_connector_error(error_message: String) -> void:
	var connector: AgentConnector = get_parent()
	GameLog.error("ConnectorService: Connector '%s' error: %s" % [connector.connector_name, error_message])

## Get all registered connectors
func get_connectors() -> Dictionary:
	return _connectors

## Get all connected agents
func get_connected_agents() -> Dictionary:
	return _connected_agents

## Get connector by name
func get_connector(name: String) -> AgentConnector:
	return _connectors.get(name)
