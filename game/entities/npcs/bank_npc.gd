## BankNPC - Bank NPC controller
extends CharacterBody3D
class_name BankNPC

@export var npc_id: String = "bank_npc"
@export var npc_name: String = "Banker"
@export var welcome_message: String = "Welcome to the bank."
var _interacting_players: Array = []

func _ready() -> void:
	set_physics_layer_mask(0)
	GameLog.debug("BankNPC: Initialized")

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

func interact(player_id: String) -> void:
	if _interacting_players.has(player_id):
		return
	_interacting_players.append(player_id)
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotifKind.CUSTOM,
			welcome_message,
			"BankNPC",
			"bank_greet:%s" % player_id,
			{},
			player_id
		)
	if MenuManager:
		MenuManager.open_menu("bank", global_position)

func stop_interact(player_id: String) -> void:
	if _interacting_players.has(player_id):
		_interacting_players.erase(player_id)
		if MenuManager:
			MenuManager.close_menu("bank")

func get_interaction_options() -> Array:
	return [{"id": "bank", "text": "Access Bank"}]
