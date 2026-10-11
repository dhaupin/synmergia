


extends "res://ui/components/ui_panel.gd"
class_name ReportDialog

const ReportKind = preload("res://core/admin/player_reporter.gd")

func _reporter() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("PlayerReporter")) if tree and tree.root else null

func _securityservice() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("SecurityService")) if tree and tree.root else null

## ReportDialog - Modal dialog for submitting player reports
## Migrated onto UIPanel base class.

# _securityservice() is an autoload singleton. It is accessed bare so
# the singleton instance is used -- preloading it here would shadow
# the singleton and make _securityservice().validate_message(...) resolve
# to the class (non-static method), which the parser rejects.
#
# UIPanel is also preloaded here because the base class is referenced
# by name in this file's body; the string-path extends above already
# loads it at parse time, so this const is redundant but harmless.
const UIPanel = preload("res://ui/components/ui_panel.gd")
enum ReportType {
	PLAYER_ABUSE = 0,
	BUG = 1,
	FEEDBACK = 2,
	SUGGESTION = 3,
	EXPLOIT = 4,
}

const MAX_TARGET_LENGTH: int = 32
const MAX_DESCRIPTION_LENGTH: int = 2000

var _reporter_id: String = ""
var _target_player: String = ""
var _report_type: ReportType = ReportType.PLAYER_ABUSE
var _submit_cooldown: float = 0.0
var _cooldown_duration: float = 60.0
var _max_reports_per_hour: int = 10

var _title_label: Label
var _target_field: LineEdit
var _description_field: TextEdit
var _type_options: OptionButton
var _submit_btn: Button
var _cancel_btn: Button
var _cooldown_label: Label
var _help_label: Label
var _target_label: Label

signal report_submitted(type: int, data: Dictionary)
signal closed()  # Alias of panel_closed for back-compat.
signal rate_limited(remaining_seconds: float)

func _ready() -> void:
	super._ready()
	panel_closed.connect(func() -> void: closed.emit())

func _setup_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(450, 400)
	panel.add_theme_stylebox_override("panel", UIStyles.create_panel_style(
		UIStyles.COLORS.background,
		UIStyles.COLORS.accent_warning,
		3,
		12
	))
	panel.name = "Panel"
	add_child(panel)

	var main := VBoxContainer.new()
	main.name = "Main"
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(main)

	_title_label = Label.new()
	_title_label.text = " Submit Report"
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	_title_label.name = "Title"
	main.add_child(_title_label)

	var type_label := Label.new()
	type_label.text = "Report Type:"
	type_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	main.add_child(type_label)

	_type_options = OptionButton.new()
	_type_options.add_item("Player Abuse / Harassment", ReportType.PLAYER_ABUSE)
	_type_options.add_item("Game Bug / Glitch", ReportType.BUG)
	_type_options.add_item("Feedback", ReportType.FEEDBACK)
	_type_options.add_item("Feature Suggestion", ReportType.SUGGESTION)
	_type_options.add_item("Suspected Exploit / Hack", ReportType.EXPLOIT)
	_type_options.item_selected.connect(_on_type_changed)
	main.add_child(_type_options)

	_target_label = Label.new()
	_target_label.name = "TargetLabel"
	_target_label.text = "Player Name:"
	_target_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	main.add_child(_target_label)

	_target_field = LineEdit.new()
	_target_field.placeholder_text = "Enter player name..."
	_target_field.custom_minimum_size.y = 35
	main.add_child(_target_field)

	var desc_label := Label.new()
	desc_label.text = "Description:"
	desc_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	main.add_child(desc_label)

	_description_field = TextEdit.new()
	_description_field.custom_minimum_size.y = 150
	_description_field.placeholder_text = "Describe the issue in detail..."
	main.add_child(_description_field)

	_help_label = Label.new()
	_help_label.name = "HelpLabel"
	_help_label.text = "Include any evidence, witnesses, or steps to reproduce."
	_help_label.add_theme_color_override("font_color", UIStyles.COLORS.text_disabled)
	_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	main.add_child(_help_label)

	var btn_container := HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_END
	main.add_child(btn_container)

	var btn_spacer := Control.new()
	btn_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_container.add_child(btn_spacer)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(close)
	btn_container.add_child(_cancel_btn)

	_submit_btn = Button.new()
	_submit_btn.text = "Submit Report"
	_submit_btn.pressed.connect(_on_submit)
	btn_container.add_child(_submit_btn)

	_cooldown_label = Label.new()
	_cooldown_label.text = ""
	_cooldown_label.add_theme_color_override("font_color", UIStyles.COLORS.warning)
	_cooldown_label.name = "CooldownLabel"
	main.add_child(_cooldown_label)

func _setup_header() -> void:
	# ReportDialog embeds the title in the body (Title label) so users see the
	# dynamic type-specific header. The UIPanel's standard header would
	# duplicate it. Provide a minimal close-button-only header.
	var panel := get_panel()
	if not panel:
		return
	var main := panel.get_node_or_null("Main") as VBoxContainer
	if not main:
		return

	var header := HBoxContainer.new()
	header.name = "Header"
	main.add_child(header)
	main.move_child(header, 0)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = ""
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

func _on_type_changed(index: int) -> void:
	_report_type = index as ReportType

	match _report_type:
		ReportType.PLAYER_ABUSE:
			_title_label.text = " Report Player"
			_target_field.show()
			_target_label.show()
			_description_field.placeholder_text = "Describe the abuse, include chat logs or evidence if possible..."
			if _help_label: _help_label.hide()
		ReportType.BUG:
			_title_label.text = " Report Bug"
			_target_field.hide()
			_target_label.hide()
			_description_field.placeholder_text = "Describe what happened, what you expected, and steps to reproduce..."
			if _help_label: _help_label.show()
		ReportType.FEEDBACK:
			_title_label.text = " Send Feedback"
			_target_field.hide()
			_target_label.hide()
			_description_field.placeholder_text = "Share your thoughts, ideas, or suggestions..."
			if _help_label: _help_label.hide()
		ReportType.SUGGESTION:
			_title_label.text = " Make Suggestion"
			_target_field.hide()
			_target_label.hide()
			_description_field.placeholder_text = "Describe your feature idea..."
			if _help_label: _help_label.hide()
		ReportType.EXPLOIT:
			_title_label.text = " Report Exploit"
			_target_field.show()
			_target_label.show()
			_description_field.placeholder_text = "Describe the exploit in detail. Include any player names involved..."
			if _help_label: _help_label.show()

func _on_submit() -> void:
	if not _check_rate_limit():
		return

	var description: String = _description_field.text.strip_edges()

	if description == "":
		_show_error("Please enter a description")
		return

	if description.length() < 10:
		_show_error("Description too short. Please provide more detail.")
		return

	# Security: Validate description length
	if description.length() > MAX_DESCRIPTION_LENGTH:
		_show_error("Description too long (max %d characters)" % MAX_DESCRIPTION_LENGTH)
		return

	# Security: Validate via _securityservice() if available
	if _securityservice():
		var validation = _securityservice().validate_message(description, _reporter_id)
		if not validation.valid:
			_show_error("Invalid input: " + validation.reason)
			return

	var target: String = _target_field.text.strip_edges()

	if _report_type == ReportType.PLAYER_ABUSE or _report_type == ReportType.EXPLOIT:
		if target == "":
			_show_error("Please enter a player name")
			return

		# Security: Validate target name length
		if target.length() > MAX_TARGET_LENGTH:
			_show_error("Player name too long")
			return

		# Security: Validate target name via _securityservice()
		if _securityservice():
			var target_validation = _securityservice().validate_player_name(target)
			if not target_validation.valid:
				_show_error("Invalid player name: " + target_validation.reason)
				return

	var data: Dictionary = {
		"description": description,
		"target": target,
	}

	if _reporter():
		var report_type: int
		match _report_type:
			ReportType.PLAYER_ABUSE: report_type = ReportKind.ReportType.ABUSE
			ReportType.BUG: report_type = ReportKind.ReportType.BUG
			ReportType.FEEDBACK: report_type = ReportKind.ReportType.FEEDBACK
			ReportType.SUGGESTION: report_type = ReportKind.ReportType.SUGGESTION
			ReportType.EXPLOIT: report_type = ReportKind.ReportType.EXPLOIT
			_: report_type = ReportKind.ReportType.OTHER

		var result: Dictionary = _reporter().submit_report(_reporter_id, report_type, data)

		if result.get("success", false):
			_start_cooldown()
			_show_success("Report submitted successfully. Thank you!")
			report_submitted.emit(_report_type, data)
			await get_tree().create_timer(1.5).timeout
			close()
		else:
			_show_error(result.get("message", "Failed to submit report"))
	else:
		_show_error("Report system not available")
		report_submitted.emit(_report_type, data)
		close()

func _check_rate_limit() -> bool:
	if _submit_cooldown > 0:
		_show_error("Please wait %d seconds before submitting another report" % int(_submit_cooldown))
		rate_limited.emit(_submit_cooldown)
		return false
	return true

func _start_cooldown() -> void:
	_submit_cooldown = _cooldown_duration

func _update_cooldown_display() -> void:
	if _submit_cooldown > 0 and _cooldown_label:
		_cooldown_label.text = "Cooldown: %ds" % int(_submit_cooldown)
		_submit_btn.disabled = true
	else:
		if _cooldown_label: _cooldown_label.text = ""
		if _submit_btn: _submit_btn.disabled = false

func _process(delta: float) -> void:
	if _submit_cooldown > 0:
		_submit_cooldown = max(0.0, _submit_cooldown - delta)
		_update_cooldown_display()

func _show_error(message: String) -> void:
	if _cooldown_label:
		_cooldown_label.text = "[color=#ff6666]%s[/color]" % message
		_cooldown_label.add_theme_color_override("font_color", UIStyles.COLORS.error)

func _show_success(message: String) -> void:
	if _cooldown_label:
		_cooldown_label.text = message
		_cooldown_label.add_theme_color_override("font_color", UIStyles.COLORS.success)

## Open the dialog for a specific reporter. UIPanel.open only takes a
## player_id, so we capture the full state here and forward the reporter
## id as the panel's player_id.
func open(reporter_id: String, default_type: ReportType = ReportType.PLAYER_ABUSE,
		target_player: String = "") -> void:
	_reporter_id = reporter_id
	_target_player = target_player
	_report_type = default_type

	if _description_field:
		_description_field.text = ""
	if _target_field:
		_target_field.text = target_player

	if _type_options:
		_type_options.selected = default_type
	_on_type_changed(default_type)

	super(reporter_id)

func open_player_report(reporter_id: String, target_player: String) -> void:
	open(reporter_id, ReportType.PLAYER_ABUSE, target_player)

func open_bug_report(reporter_id: String) -> void:
	open(reporter_id, ReportType.BUG, "")

func open_feedback(reporter_id: String) -> void:
	open(reporter_id, ReportType.FEEDBACK, "")


func open_suggestion(reporter_id: String) -> void:
	open(reporter_id, ReportType.SUGGESTION, "")
