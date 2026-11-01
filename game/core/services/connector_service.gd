## ConnectorService - Manages agent connectors
## Handles connecting/disconnecting AI agents to the game
extends Node
class_name ConnectorService

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
	_load_state()
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
		connector.disconnect_agent()
		_connectors.erase(connector_name)
		GameLog.info("ConnectorService: Unregistered connector '%s'" % connector_name)

## Connect an agent using a specific connector
func connect_agent(agent_id: String, connector_name: String, config: Dictionary, entity) -> bool:
	if not _connectors.has(connector_name):
		GameLog.error("ConnectorService: Unknown connector '%s'" % connector_name)
		return false

	var connector: AgentConnector = _connectors[connector_name]

	if not connector.connect_agent(config):
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
		connector.disconnect_agent()
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
			_queue_agent_action(agent_id, action)
			return

## Queue an agent action as a state command for atomic application in Phase 2
func _queue_agent_action(agent_id: String, action: AgentAction) -> void:
	if not _connected_agents.has(agent_id):
		return

	var entity = _connected_agents[agent_id]["entity"]
	if not is_instance_valid(entity):
		return

	var entity_id := entity.entity_id if ("entity_id" in entity) else agent_id
	var path := "entities/%s" % entity_id

	match action.action_type:
		AgentAction.ActionType.MOVEMENT:
			var payload := {
				"movement_direction": action.movement_direction,
				"is_sprinting": action.is_sprinting,
				"is_jumping": action.is_jumping
			}
			var command := {
				"type": "update",
				"path": path,
				"entity_id": entity_id,
				"state_type": "movement",
				"payload": payload
			}
			if TickService:
				TickService.queue_state_command(command)

		AgentAction.ActionType.COMBAT:
			var payload := {
				"action_name": action.action_name,
				"target_entity_id": action.target_entity_id,
				"ground_target_position": action.ground_target_position
			}
			var command := {
				"type": "update",
				"path": path,
				"entity_id": entity_id,
				"state_type": "combat",
				"payload": payload
			}
			if TickService:
				TickService.queue_state_command(command)

		AgentAction.ActionType.SKILL:
			var payload := {
				"skill_id": action.skill_id,
				"target_entity_id": action.target_entity_id,
				"ground_target_position": action.ground_target_position
			}
			var command := {
				"type": "update",
				"path": path,
				"entity_id": entity_id,
				"state_type": "skill",
				"payload": payload
			}
			if TickService:
				TickService.queue_state_command(command)

		AgentAction.ActionType.TARGETING:
			var payload := {
				"mode": action.parameters.get("mode", ""),
				"target_entity_id": action.target_entity_id
			}
			var command := {
				"type": "update",
				"path": path,
				"entity_id": entity_id,
				"state_type": "targeting",
				"payload": payload
			}
			if TickService:
				TickService.queue_state_command(command)

		AgentAction.ActionType.INTERACTION:
			var payload := {
				"action_name": action.action_name,
				"interact_target_id": action.interact_target_id,
				"use_item_slot": action.use_item_slot
			}
			var command := {
				"type": "update",
				"path": path,
				"entity_id": entity_id,
				"state_type": "interaction",
				"payload": payload
			}
			if TickService:
				TickService.queue_state_command(command)

		AgentAction.ActionType.CHAT:
			# Chat is not a state tree mutation; send directly via ChatService
			var entity = _connected_agents[agent_id]["entity"]
			if is_instance_valid(entity):
				ChatService.send_message(entity, action.chat_message, action.chat_channel)

		AgentAction.ActionType.ADMIN:
			# Admin actions handled separately
			pass

## Execute queued agent action (called from Phase 2 mutate or similar)
## This is kept for reference but actions should be executed via state commands
func _execute_action(agent_id: String, action: AgentAction) -> void:
	# Deprecated: use _queue_agent_action + state command processing
	pass

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

## == Persistence ============================================================

func _load_state() -> void:
	var store := DictStore.new()
	_connected_agents = {}
	for key in store.all_keys():
		if key.begins_with(_kv_prefix):
			var agent_id = key.substr(_kv_prefix.length())
			_connected_agents[agent_id] = store.get_kv(key)

func _persist_agent(agent_id: String) -> void:
	var store := DictStore.new()
	if _connected_agents.has(agent_id):
		store.set_kv(_kv_prefix + agent_id, _connected_agents[agent_id])
	else:
		store.erase(_kv_prefix + agent_id)
