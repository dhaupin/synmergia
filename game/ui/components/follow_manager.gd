## FollowManager - UI for showing follow status and controls
## Displays who you're following and offers cancel option
extends Control

# NOTE: FollowService is an autoload. The old `const FollowService = preload(...)`
# here shadowed the autoload with the script resource, so signal connections
# targeted the script (where signals don't exist) instead of the instance.

@onready var container: VBoxContainer = get_node_or_null("Panel/VBox")
@onready var target_label: Label = get_node_or_null("Panel/VBox/TargetLabel")
@onready var distance_label: Label = get_node_or_null("Panel/VBox/DistanceLabel")
@onready var state_label: Label = get_node_or_null("Panel/VBox/StateLabel")
@onready var cancel_btn: Button = get_node_or_null("Panel/VBox/CancelButton")

var _is_visible: bool = false
var _is_following: bool = false

func _ready() -> void:
	visible = false
	if cancel_btn != null:
		cancel_btn.pressed.connect(_on_cancel_pressed)

	# Connect to FollowService signals
	if FollowService:
		FollowService.follow_started.connect(_on_follow_started)
		FollowService.follow_cancelled.connect(_on_follow_cancelled)
		FollowService.follow_state_changed.connect(_on_follow_state_changed)
		FollowService.follow_target_moved.connect(_on_target_moved)

func _input(event: InputEvent) -> void:
	# Handle keyboard shortcuts for following/stopping
	if not _is_following:
		return

	# Only handle if visible and no modal dialogs are open
	if not visible:
		return

	if event is InputEventKey and event.pressed:
		# 'F' key toggles/stops follow
		if event.keycode == KEY_F:
			_stop_follow()
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	# Clean up signals when removed from tree
	if what == NOTIFICATION_PREDELETE:
		if FollowService:
			if FollowService.follow_started.is_connected(_on_follow_started):
				FollowService.follow_started.disconnect(_on_follow_started)
			if FollowService.follow_cancelled.is_connected(_on_follow_cancelled):
				FollowService.follow_cancelled.disconnect(_on_follow_cancelled)
			if FollowService.follow_state_changed.is_connected(_on_follow_state_changed):
				FollowService.follow_state_changed.disconnect(_on_follow_state_changed)
			if FollowService.follow_target_moved.is_connected(_on_target_moved):
				FollowService.follow_target_moved.disconnect(_on_target_moved)

func _process(delta: float) -> void:
	if not _is_visible:
		return

	# Update distance display
	if FollowService and PlayerManager:
		var my_id := str(PlayerManager.get_local_player_id())
		var distance := FollowService.get_distance_to_target(my_id)
		var range_limit := FollowService.DEFAULT_FOLLOW_RANGE

		if distance >= 0:
			distance_label.text = "Distance: %.1f / %.1f" % [distance, range_limit]

			# Warning color if getting close to limit
			if distance > range_limit * 0.8:
				distance_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.0))  # Orange
			else:
				distance_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))  # Gray
		else:
			distance_label.text = "Distance: --"

func _on_follow_started(follower_id: String, target_id: String) -> void:
	if not PlayerManager:
		return

	var my_id := str(PlayerManager.get_local_player_id())
	if follower_id != my_id:
		return

	# Show UI
	target_label.text = "Following: %s" % target_id
	_update_state_label(FollowService.FollowState.IDLE)
	visible = true
	_is_visible = true
	_is_following = true

func _on_follow_cancelled(follower_id: String, target_id: String, reason: String) -> void:
	if not PlayerManager:
		return

	var my_id := str(PlayerManager.get_local_player_id())
	if follower_id != my_id:
		return

	# Hide UI
	visible = false
	_is_visible = false
	_is_following = false

	# Show notification
	if NotificationService:
		NotificationService.notify(
			NotificationService.NotificationType.INFO,
			"Stopped following: %s (%s)" % [target_id, reason],
			"FollowService",
			"follow_cancelled:%s" % follower_id,
			{"reason": reason}
		)

func _on_follow_state_changed(follower_id: String, old_state: int, new_state: int) -> void:
	if not PlayerManager:
		return

	var my_id := str(PlayerManager.get_local_player_id())
	if follower_id != my_id:
		return

	_update_state_label(new_state)

func _on_target_moved(follower_id: String, target_position: Vector3) -> void:
	# Could add visual indicator here
	pass

func _update_state_label(state: int) -> void:
	match state:
		FollowService.FollowState.IDLE:
			state_label.text = "Status: Following"
			state_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))  # Green
		FollowService.FollowState.CATCHING_UP:
			state_label.text = "Status: Catching up..."
			state_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))  # Yellow
		_:
			state_label.text = "Status: Unknown"
			state_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))  # Gray

func _on_cancel_pressed() -> void:
	_stop_follow()

func _stop_follow() -> void:
	if FollowService and PlayerManager:
		var my_id := str(PlayerManager.get_local_player_id())
		FollowService.stop_follow(my_id, "cancelled_by_player")

## Check if player is currently following someone
func is_following() -> bool:
	return _is_following
