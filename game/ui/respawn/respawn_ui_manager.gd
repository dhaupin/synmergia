## RespawnUIManager - Manages the death/respawn UI
## Coordinates between HealthComponent death and RespawnService options
extends Node

var _ui = null
var _current_player = null
var _pending_respawn: Dictionary = {}

func _ready() -> void:
	# Listen for player death events specifically
	if EventHub:
		EventHub.player_died.connect(_on_player_died)
	# Close the respawn UI when respawn actually completes.
	# RespawnService may not be ready yet (autoload ordering), so guard
	# it -- accessing .respawn_completed on a null instance crashes.
	if RespawnService:
		RespawnService.respawn_completed.connect(_on_respawn_completed)
		RespawnService.respawn_canceled.connect(_on_respawn_canceled)
		RespawnService.revive_completed.connect(_on_respawn_completed)
	GameLog.info("RespawnUIManager: Initialized")

func _on_player_died(entity, killer) -> void:
	_show_respawn_ui(entity)

func _show_respawn_ui(player) -> void:
	_current_player = player

	# Create/instantiate UI if needed
	if not _ui:
		var scene = load("res://ui/respawn/respawn_ui.tscn")
		if scene:
			_ui = scene.instantiate()
			get_tree().root.add_child(_ui)
			_ui.respawn_selected.connect(_on_respawn_selected)

	if not _ui:
		# UI not available, fall back to immediate respawn
		RespawnService.initiate_respawn(player)
		return

	# Get available respawn options from RespawnService
	var options = _get_respawn_options(player)

	# Store pending respawn for later
	_pending_respawn = {"player": player, "options": options}

	# Show the UI with config-based settings
	_ui.auto_show_delay = GameConfig.Respawn.RESPAWN_UI_DELAY
	_ui.auto_respawn_timeout = GameConfig.Respawn.AUTO_RESPAWN_TIMEOUT
	_ui.show_respawn_options(options)

func _get_respawn_options(player) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var zone_id: String = player.current_zone if player.has("current_zone") else ""

	# Check what respawn modes are available
	var available_modes = RespawnService.get_available_respawn_modes(player, zone_id)
	var zone_config = RespawnService.get_zone_config(zone_id)

	for mode in available_modes:
		match mode:
			RespawnService.RespawnMode.ANKH:
				var ankh_data = RespawnService.get_bound_ankh(player)
				if not ankh_data.is_empty():
					options.append({
						"mode": "ankh",
						"name": ankh_data.get("display_name", "Ankh"),
						"ankh_id": ankh_data.get("ankh_id", ""),
						"position": ankh_data.get("position", {}),
						"respawn_modifier": ankh_data.get("respawn_time_modifier", 1.0)
					})
			RespawnService.RespawnMode.TIMED:
				options.append({
					"mode": "timed",
					"time": zone_config.get("timed_respawn_seconds", 30.0),
					"position": Vector3.ZERO
				})
			RespawnService.RespawnMode.GATEWAY:
				options.append({
					"mode": "gateway",
					"name": "Zone Gateway",
					"gateway_ids": zone_config.get("gateway_ids", [])
				})
			RespawnService.RespawnMode.SAFE_ZONE:
				options.append({
					"mode": "safe_zone",
					"name": "Arena Safe Zone",
					"invincibility": zone_config.get("invincibility_duration", 0.0)
				})
			RespawnService.RespawnMode.ARENA_TEAM:
				options.append({
					"mode": "arena",
					"name": "Team Respawn",
					"max_respawns": zone_config.get("max_arena_respawns_per_team", 5)
				})

	# Add corpse option if corpse exists
	if player.health_component and player.health_component._corpse:
		options.append({
			"mode": "near_corpse",
			"name": "Near Corpse (Faster)",
			"position": player.global_position
		})

	return options

func _on_respawn_selected(mode: String, location_data: Dictionary) -> void:
	if not _pending_respawn.has("player"):
		return

	var player = _pending_respawn["player"]
	_pending_respawn = {}

	# Store selected respawn info
	player._pending_respawn_mode = mode
	player._pending_respawn_data = location_data

	# Trigger respawn via RespawnService
	RespawnService.initiate_respawn(player)


func _on_respawn_completed(player, _position) -> void:
	_hide_ui()


func _on_respawn_canceled(player, _reason: String) -> void:
	_hide_ui()


func _hide_ui() -> void:
	if _ui:
		_ui._hide()
