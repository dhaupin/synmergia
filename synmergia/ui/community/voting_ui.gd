## VotingUI - In-game UI for community voting
class_name VotingUI
extends Control

var _panel: PanelContainer
var _tab_container: TabContainer
var _vote_list: ItemList
var _vote_detail: VBoxContainer
var _current_vote_id: String = ""
var _current_voter: String = ""

signal closed()
signal vote_cast(vote_id: String, option_id)

func _ready() -> void:
	_setup_ui()
	hide()

func _setup_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.98)
	style.border_color = Color(0.3, 0.3, 0.4)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	_panel.add_theme_stylebox_override("panel", style)
	
	add_child(_panel)
	
	var main := VBoxContainer.new()
	_panel.add_child(main)
	
	# Header
	var header := HBoxContainer.new()
	main.add_child(header)
	
	var title := Label.new()
	title.text = "🗳️ Community Voting"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	header.add_child(title)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(func(): hide())
	header.add_child(close_btn)
	
	# Tabs
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
	
	var detail_style := StyleBoxFlat.new()
	detail_style.bg_color = Color(0.08, 0.08, 0.1)
	detail_style.corner_radius_top_left = 4
	detail_style.corner_radius_top_right = 4
	detail_style.corner_radius_bottom_left = 4
	detail_style.corner_radius_bottom_right = 4
	detail_panel.add_theme_stylebox_override("panel", detail_style)
	
	_vote_detail = VBoxContainer.new()
	detail_panel.add_child(_vote_detail)

func _setup_my_votes_tab(tab: Control) -> void:
	var label := Label.new()
	label.text = "Your voting history will appear here.\n\nVote on active items in the 'Active' tab."
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tab.add_child(label)

func _setup_stats_tab(tab: Control) -> void:
	var vbox := VBoxContainer.new()
	tab.add_child(vbox)
	
	var stats_label := Label.new()
	stats_label.text = "Your Community Stats"
	stats_label.add_theme_font_size_override("font_size", 16)
	stats_label.add_theme_color_override("font_color", Color(1, 1, 1))
	vbox.add_child(stats_label)

func _refresh_vote_list() -> void:
	_vote_list.clear()
	
	if not CommunityGovernance:
		return
	
	var votes := CommunityGovernance.get_open_votes()
	
	for vote_data in votes:
		var question: String = vote_data.get("question", "Unknown")
		var total_votes: int = vote_data.get("total_votes", 0)
		var display := "%s\n  %d votes" % [question, total_votes]
		_vote_list.add_item(display)

func _on_vote_selected(index: int) -> void:
	if not CommunityGovernance:
		return
	
	var votes := CommunityGovernance.get_open_votes()
	if index < votes.size():
		var vote_data: Dictionary = votes[index]
		_show_vote_detail(vote_data.get("id", ""))

func _show_vote_detail(vote_id: String) -> void:
	_current_vote_id = vote_id
	
	for child in _vote_detail.get_children():
		child.queue_free()
	
	if not CommunityGovernance:
		return
	
	var vote_data := CommunityGovernance.get_vote(vote_id)
	
	if vote_data.is_empty():
		return
	
	var question := Label.new()
	question.text = vote_data.get("question", "")
	question.add_theme_font_size_override("font_size", 14)
	question.add_theme_color_override("font_color", Color(1, 1, 1))
	question.autowrap_mode = TextServer.AUTOWRAP_WORD
	_vote_detail.add_child(question)
	
	var desc := Label.new()
	desc.text = vote_data.get("description", "")
	desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_vote_detail.add_child(desc)
	
	var sep := Label.new()
	sep.custom_minimum_size.y = 10
	_vote_detail.add_child(sep)
	
	var has_voted: bool = vote_data.get("user_voted", false)
	
	if has_voted:
		var voted_label := Label.new()
		voted_label.text = "✓ You have already voted"
		voted_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
		_vote_detail.add_child(voted_label)
	else:
		var options: Array = vote_data.get("options", [])
		for option in options:
			var opt_id = option.get("id", 0)
			var opt_text: String = option.get("text", "Option")
			
			var btn := Button.new()
			btn.text = opt_text
			btn.custom_minimum_size.y = 35
			btn.pressed.connect(func(): _cast_vote(opt_id))
			_vote_detail.add_child(btn)
	
	var results: Array = vote_data.get("results", [])
	if not results.is_empty():
		var results_label := Label.new()
		results_label.text = "\nCurrent Results:"
		results_label.add_theme_color_override("font_color", Color(1, 1, 0.8))
		_vote_detail.add_child(results_label)
		
		for result in results:
			var result_text := "  %s: %d votes (%.1f%%)" % [
				result.get("text", "?"),
				result.get("votes", 0),
				result.get("percentage", 0.0)
			]
			var result_label := Label.new()
			result_label.text = result_text
			result_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			_vote_detail.add_child(result_label)

func _cast_vote(option_id) -> void:
	if not CommunityGovernance or _current_voter == "":
		return
	
	var result := CommunityGovernance.cast_vote(_current_voter, _current_vote_id, option_id)
	
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
	notif.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
	notif.z_index = 1000
	notif.global_position = Vector2(100, 100)
	get_tree().root.add_child(notif)
	await get_tree().create_timer(3.0).timeout
	notif.queue_free()

func open(voter_id: String) -> void:
	_current_voter = voter_id
	_refresh_vote_list()
	show()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		closed.emit()
