## VotingUI - In-game UI for community voting
## Migrated onto UIPanel base class.
extends "res://ui/components/ui_panel.gd"
class_name VotingUI
var _tab_container: TabContainer
var _vote_list: ItemList
var _vote_detail: VBoxContainer
var _current_vote_id: String = ""
var _current_voter: String = ""

signal closed()  # Alias of panel_closed for back-compat.
signal vote_cast(vote_id: String, option_id)

func _ready() -> void:
	super._ready()
	panel_closed.connect(func() -> void: closed.emit())
	_bind_service_signals()


func _bind_service_signals() -> void:
	if not CommunityGovernance:
		return
	if CommunityGovernance.has_signal("vote_created"):
		if not CommunityGovernance.vote_created.is_connected(_on_vote_created):
			CommunityGovernance.vote_created.connect(_on_vote_created)
	if CommunityGovernance.has_signal("vote_closed"):
		if not CommunityGovernance.vote_closed.is_connected(_on_vote_closed):
			CommunityGovernance.vote_closed.connect(_on_vote_closed)
	if CommunityGovernance.has_signal("vote_expired"):
		if not CommunityGovernance.vote_expired.is_connected(_on_vote_expired):
			CommunityGovernance.vote_expired.connect(_on_vote_expired)


func _on_vote_created(_vote) -> void:
	if is_open():
		_refresh_vote_list()


func _on_vote_closed(_vote) -> void:
	if is_open():
		_refresh_vote_list()


func _on_vote_expired(_vote) -> void:
	if is_open():
		_refresh_vote_list()

func _setup_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UIStyles.create_panel_style(
		UIStyles.COLORS.background_dark,
		UIStyles.COLORS.border,
		2,
		8
	))
	panel.name = "Panel"
	add_child(panel)

	var main := VBoxContainer.new()
	main.name = "Main"
	panel.add_child(main)

	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(_tab_container)

	var active_tab := Control.new()
	active_tab.name = "Active"
	_tab_container.add_child(active_tab)
	_setup_active_tab(active_tab)

	var my_votes_tab := Control.new()
	my_votes_tab.name = "My Votes"
	_tab_container.add_child(my_votes_tab)
	_setup_my_votes_tab(my_votes_tab)

	var stats_tab := Control.new()
	stats_tab.name = "Stats"
	_tab_container.add_child(stats_tab)
	_setup_stats_tab(stats_tab)

func _setup_header() -> void:
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

	var title := Label.new()
	title.text = " Community Voting"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = ""
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

func _on_open() -> void:
	_refresh_vote_list()

func _setup_active_tab(tab: Control) -> void:
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab.add_child(hbox)

	_vote_list = ItemList.new()
	_vote_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vote_list.item_selected.connect(_on_vote_selected)
	hbox.add_child(_vote_list)

	var detail_panel := PanelContainer.new()
	detail_panel.custom_minimum_size.x = 350
	hbox.add_child(detail_panel)

	detail_panel.add_theme_stylebox_override("panel", UIStyles.create_panel_style(
		UIStyles.COLORS.background,
		UIStyles.COLORS.border,
		1,
		4
	))

	_vote_detail = VBoxContainer.new()
	detail_panel.add_child(_vote_detail)

func _setup_my_votes_tab(tab: Control) -> void:
	var label := Label.new()
	label.text = "Your voting history will appear here.\n\nVote on active items in the 'Active' tab."
	label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tab.add_child(label)

func _setup_stats_tab(tab: Control) -> void:
	var vbox := VBoxContainer.new()
	tab.add_child(vbox)

	var stats_label := Label.new()
	stats_label.text = "Your Community Stats"
	stats_label.add_theme_font_size_override("font_size", 16)
	stats_label.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	vbox.add_child(stats_label)

func _refresh_vote_list() -> void:
	if not _vote_list:
		return
	_vote_list.clear()

	if not CommunityGovernance:
		return

	var votes: Array = CommunityGovernance.get_open_votes()

	for vote_data in votes:
		var vote: Dictionary = vote_data
		var question: String = vote.get("question", "Unknown")
		var total_votes: int = vote.get("total_votes", 0)
		var display := "%s\n  %d votes" % [question, total_votes]
		_vote_list.add_item(display)

func _on_vote_selected(index: int) -> void:
	if not CommunityGovernance:
		return

	var votes: Array = CommunityGovernance.get_open_votes()
	if index < votes.size():
		var vote_data: Dictionary = votes[index]
		_show_vote_detail(vote_data.get("id", ""))

func _show_vote_detail(vote_id: String) -> void:
	_current_vote_id = vote_id

	for child in _vote_detail.get_children():
		child.queue_free()

	if not CommunityGovernance:
		return

	var vote_data: Dictionary = CommunityGovernance.get_vote(vote_id)

	if vote_data.is_empty():
		return

	var question := Label.new()
	question.text = vote_data.get("question", "")
	question.add_theme_font_size_override("font_size", 14)
	question.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	question.autowrap_mode = TextServer.AUTOWRAP_WORD
	_vote_detail.add_child(question)

	var desc := Label.new()
	desc.text = vote_data.get("description", "")
	desc.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_vote_detail.add_child(desc)

	var sep := Label.new()
	sep.custom_minimum_size.y = 10
	_vote_detail.add_child(sep)

	var has_voted: bool = vote_data.get("user_voted", false)

	if has_voted:
		var voted_label := Label.new()
		voted_label.text = " You have already voted"
		voted_label.add_theme_color_override("font_color", UIStyles.COLORS.success)
		_vote_detail.add_child(voted_label)
	else:
		var options: Array = vote_data.get("options", [])
		for option in options:
			var opt: Dictionary = option
			var opt_id: int = opt.get("id", 0)
			var opt_text: String = opt.get("text", "Option")

			var btn := Button.new()
			btn.text = opt_text
			btn.custom_minimum_size.y = 35
			btn.pressed.connect(func() -> void: _cast_vote(opt_id))
			_vote_detail.add_child(btn)

	var results: Array = vote_data.get("results", [])
	if not results.is_empty():
		var results_label := Label.new()
		results_label.text = "\nCurrent Results:"
		results_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
		_vote_detail.add_child(results_label)

		for result in results:
			var r: Dictionary = result
			var result_text := "  %s: %d votes (%.1f%%)" % [
				r.get("text", "?"),
				r.get("votes", 0),
				r.get("percentage", 0.0)
			]
			var result_label := Label.new()
			result_label.text = result_text
			result_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
			_vote_detail.add_child(result_label)

func _cast_vote(option_id: int) -> void:
	if not CommunityGovernance or _current_voter == "":
		return

	var result: Dictionary = CommunityGovernance.cast_vote(_current_voter, _current_vote_id, option_id)

	if result.get("success", false):
		_show_notification("Vote cast!")
		_refresh_vote_list()
		_show_vote_detail(_current_vote_id)
		vote_cast.emit(_current_vote_id, option_id)
	else:
		_show_notification("Failed: " + result.get("message", ""))

func _show_notification(message: String) -> void:
	var notif := Label.new()
	notif.text = message
	notif.add_theme_color_override("font_color", UIStyles.COLORS.success)
	notif.z_index = 1000
	notif.global_position = Vector2(100, 100)
	get_tree().root.add_child(notif)
	await get_tree().create_timer(3.0).timeout
	notif.queue_free()

# VotingUI uses 'voter_id' as the player id; UIPanel's open(player_id) routes
# it to _player_id, but the CommunityGovernance API expects voter_id. We
# mirror it into _current_voter for clarity.
func open(voter_id: String) -> void:
	_current_voter = voter_id
	super(voter_id)
