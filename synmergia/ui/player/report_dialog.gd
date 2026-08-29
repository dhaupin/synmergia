## ReportDialog - Modal dialog for submitting player reports
class_name ReportDialog
extends Control

## Dialog type
enum ReportType {
	PLAYER_ABUSE = 0
	BUG = 1
	FEEDBACK = 2
	SUGGESTION = 3
	EXPLOIT = 4
}

## Current reporter
var _reporter_id: String = ""
var _target_player: String = ""
var _report_type: ReportType = ReportType.PLAYER_ABUSE

## Rate limiting (QoS integration)
var _submit_cooldown: float = 0.0
var _cooldown_duration: float = 60.0  # 60 seconds between submissions
var _max_reports_per_hour: int = 10

## UI Elements
var _panel: PanelContainer
var _title_label: Label
var _target_field: LineEdit
var _description_field: TextEdit
var _type_options: OptionButton
var _submit_btn: Button
var _cancel_btn: Button
var _cooldown_label: Label

## Signals
signal report_submitted(type: int, data: Dictionary)
signal closed()
signal rate_limited(remaining_seconds: float)

func _ready() -> void:
	_setup_ui()
	hide()

func _setup_ui() -> void:
	# Semi-transparent overlay
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.gui_input.connect(func(e): 
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			hide()
	)
	add_child(overlay)
	
	# Main panel
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(450, 400)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.16, 0.98)
	style.border_color = Color(0.4, 0.3, 0.2)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 20
	style.content_margin_top = 20
	style.content_margin_right = 20
	style.content_margin_bottom = 20
	_panel.add_theme_stylebox_override("panel", style)
	
	add_child(_panel)
	
	var main := VBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(main)
	
	# Header
	var header := HBoxContainer.new()
	main.add_child(header)
	
	_title_label = Label.new()
	_title_label.text = "🚩 Submit Report"
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(1, 1, 1))
	header.add_child(_title_label)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(hide)
	header.add_child(close_btn)
	
	# Type selector
	var type_label := Label.new()
	type_label.text = "Report Type:"
	type_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	main.add_child(type_label)
	
	_type_options = OptionButton.new()
	_type_options.add_item("Player Abuse / Harassment", ReportType.PLAYER_ABUSE)
	_type_options.add_item("Game Bug / Glitch", ReportType.BUG)
	_type_options.add_item("Feedback", ReportType.FEEDBACK)
	_type_options.add_item("Feature Suggestion", ReportType.SUGGESTION)
	_type_options.add_item("Suspected Exploit / Hack", ReportType.EXPLOIT)
	_type_options.item_selected.connect(_on_type_changed)
	main.add_child(_type_options)
	
	# Target field (for player abuse)
	var target_label := Label.new()
	target_label.name = "TargetLabel"
	target_label.text = "Player Name:"
	target_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	main.add_child(target_label)
	
	_target_field = LineEdit.new()
	_target_field.placeholder_text = "Enter player name..."
	_target_field.custom_minimum_size.y = 35
	main.add_child(_target_field)
	
	# Description field
	var desc_label := Label.new()
	desc_label.text = "Description:"
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	main.add_child(desc_label)
	
	_description_field = TextEdit.new()
	_description_field.custom_minimum_size.y = 150
	_description_field.placeholder_text = "Describe the issue in detail..."
	main.add_child(_description_field)
	
	# Help text
	var help_label := Label.new()
	help_label.name = "HelpLabel"
	help_label.text = "Include any evidence, witnesses, or steps to reproduce."
	help_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	main.add_child(help_label)
	
	# Buttons
	var btn_container := HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_END
	main.add_child(btn_container)
	
	spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_container.add_child(spacer)
	
	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(hide)
	btn_container.add_child(_cancel_btn)
	
	_submit_btn = Button.new()
	_submit_btn.text = "Submit Report"
	_submit_btn.pressed.connect(_on_submit)
	btn_container.add_child(_submit_btn)

func _on_type_changed(index: int) -> void:
	_report_type = index as ReportType
	
	# Update UI based on type
	match _report_type:
		ReportType.PLAYER_ABUSE:
			_title_label.text = "🚩 Report Player"
			_target_field.show()
			get_node("Panel/MarginContainer/VBoxContainer/TargetLabel").show()
			_description_field.placeholder_text = "Describe the abuse, include chat logs or evidence if possible..."
			get_node_or_null("Panel/MarginContainer/VBoxContainer/HelpLabel").hide()
		ReportType.BUG:
			_title_label.text = "🐛 Report Bug"
			_target_field.hide()
			get_node("Panel/MarginContainer/VBoxContainer/TargetLabel").hide()
			_description_field.placeholder_text = "Describe what happened, what you expected, and steps to reproduce..."
			get_node_or_null("Panel/MarginContainer/VBoxContainer/HelpLabel").show()
		ReportType.FEEDBACK:
			_title_label.text = "💬 Send Feedback"
			_target_field.hide()
			get_node("Panel/MarginContainer/VBoxContainer/TargetLabel").hide()
			_description_field.placeholder_text = "Share your thoughts, ideas, or suggestions..."
			get_node_or_null("Panel/MarginContainer/VBoxContainer/HelpLabel").hide()
		ReportType.SUGGESTION:
			_title_label.text = "💡 Make Suggestion"
			_target_field.hide()
			get_node("Panel/MarginContainer/VBoxContainer/TargetLabel").hide()
			_description_field.placeholder_text = "Describe your feature idea..."
			get_node_or_null("Panel/MarginContainer/VBoxContainer/HelpLabel").hide()
		ReportType.EXPLOIT:
			_title_label.text = "⚠️ Report Exploit"
			_target_field.show()
			get_node("Panel/MarginContainer/VBoxContainer/TargetLabel").show()
			_description_field.placeholder_text = "Describe the exploit in detail. Include any player names involved..."
			get_node_or_null("Panel/MarginContainer/VBoxContainer/HelpLabel").show()

func _on_submit() -> void:
	# Check rate limiting
	if not _check_rate_limit():
		return
	
	var description := _description_field.text.strip_edges()
	
	if description == "":
		_show_error("Please enter a description")
		return
	
	# Basic content validation
	if description.length() < 10:
		_show_error("Description too short. Please provide more detail.")
		return
	
	var target: Variant = _target_field.text.strip_edges()
	
	# Validate target for player reports
	if _report_type in [ReportType.PLAYER_ABUSE, ReportType.EXPLOIT]:
		if target == "":
			_show_error("Please enter a player name")
			return
	
	# Build report data
	var data: Dictionary = {
		"description": description,
		"target": target
	}
	
	# Submit to PlayerReporter (has its own rate limiting)
	if PlayerReporter:
		var report_type: int
		match _report_type:
			ReportType.PLAYER_ABUSE: report_type = PlayerReporter.ReportType.ABUSE
			ReportType.BUG: report_type = PlayerReporter.ReportType.BUG
			ReportType.FEEDBACK: report_type = PlayerReporter.ReportType.FEEDBACK
			ReportType.SUGGESTION: report_type = PlayerReporter.ReportType.SUGGESTION
			ReportType.EXPLOIT: report_type = PlayerReporter.ReportType.EXPLOIT
			_: report_type = PlayerReporter.ReportType.OTHER
		
		var result := PlayerReporter.submit_report(_reporter_id, report_type, data)
		
		if result.get("success", false):
			# Start cooldown after successful submission
			_start_cooldown()
			_show_success("Report submitted successfully. Thank you!")
			report_submitted.emit(_report_type, data)
			await get_tree().create_timer(1.5).timeout
			hide()
		else:
			_show_error(result.get("message", "Failed to submit report"))
	else:
		_show_error("Report system not available")
		report_submitted.emit(_report_type, data)
		hide()

func _check_rate_limit() -> bool:
	# Check cooldown
	if _submit_cooldown > 0:
		_show_error("Please wait %.0f seconds before submitting another report" % _submit_cooldown)
		rate_limited.emit(_submit_cooldown)
		return false
	
	# Check hourly limit via SecurityService if available
	if SecurityService:
		var rate_limit_key := "reports_%s" % _reporter_id
		if SecurityService.is_rate_limited(rate_limit_key, _max_reports_per_hour, 3600):
			_show_error("Hourly report limit reached. Please try again later.")
			rate_limited.emit(3600)
			return false
	
	return true

func _start_cooldown() -> void:
	_submit_cooldown = _cooldown_duration
	_submit_btn.disabled = true
	
	# Update cooldown label
	if _cooldown_label:
		_cooldown_label.show()
		_update_cooldown_display()

func _update_cooldown_display() -> void:
	if _cooldown_label:
		_cooldown_label.text = "Wait %.0fs" % _submit_cooldown

func _process(delta: float) -> void:
	if _submit_cooldown > 0:
		_submit_cooldown -= delta
		_update_cooldown_display()
		if _submit_cooldown <= 0:
			_submit_cooldown = 0
			_submit_btn.disabled = false
			if _cooldown_label:
				_cooldown_label.hide()

func _show_error(message: String) -> void:
	var error_label := Label.new()
	error_label.text = message
	error_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	error_label.z_index = 100
	_panel.add_child(error_label)
	
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_callback(error_label.queue_free)

func _show_success(message: String) -> void:
	var success_label := Label.new()
	success_label.text = message
	success_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3))
	success_label.z_index = 100
	_panel.add_child(success_label)
	
	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_callback(success_label.queue_free)

## Open the dialog for a specific reporter
func open(reporter_id: String, default_type: ReportType = ReportType.PLAYER_ABUSE, 
		target_player: String = "") -> void:
	
	_reporter_id = reporter_id
	_target_player = target_player
	_report_type = default_type
	
	# Reset fields
	_description_field.text = ""
	_target_field.text = target_player
	
	# Set type
	_type_options.selected = default_type
	_on_type_changed(default_type)
	
	show()

## Open specifically to report a player
func open_player_report(reporter_id: String, target_player: String) -> void:
	open(reporter_id, ReportType.PLAYER_ABUSE, target_player)

## Open specifically to report a bug
func open_bug_report(reporter_id: String) -> void:
	open(reporter_id, ReportType.BUG, "")

## Open specifically for feedback
func open_feedback(reporter_id: String) -> void:
	open(reporter_id, ReportType.FEEDBACK, "")

## Open specifically for a suggestion
func open_suggestion(reporter_id: String) -> void:
	open(reporter_id, ReportType.SUGGESTION, "")

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if not visible:
			closed.emit()
