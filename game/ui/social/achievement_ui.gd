## AchievementUI - Achievement display and progress tracking
extends Control
class_name AchievementUI

const AchievementData = preload("res://core/schemas/achievement_data.gd")

var _player_id: String = ""
var _achievement_defs: Dictionary = {}

signal panel_opened()
signal panel_closed()

func _ready() -> void:
        name = "AchievementUI"
        visible = false
        _setup_ui()
        _bind_signals()

func _setup_ui() -> void:
        var vbox := VBoxContainer.new()
        vbox.name = "VBox"
        add_child(vbox)

        var header := Label.new()
        header.name = "Header"
        header.text = "Achievements"
        header.add_theme_font_size_override("font_size", 18)
        vbox.add_child(header)

        var stats := Label.new()
        stats.name = "Stats"
        stats.text = "Unlocked: 0 / 0"
        vbox.add_child(stats)

        var scroll := ScrollContainer.new()
        scroll.name = "AchievementScroll"
        scroll.custom_minimum_size.y = 350
        vbox.add_child(scroll)

        var list := VBoxContainer.new()
        list.name = "AchievementList"
        list.size_flags_vertical = Control.SIZE_EXPAND_FILL
        scroll.add_child(list)

        var close_btn := Button.new()
        close_btn.text = "Close"
        close_btn.pressed.connect(close)
        vbox.add_child(close_btn)

func _bind_signals() -> void:
        var root := get_tree().root if get_tree() else null
        if root:
                var ach_inst: Node = root.get_node_or_null("AchievementService")
                if ach_inst:
                        if ach_inst.has_signal("achievement_unlocked"):
                                ach_inst.achievement_unlocked.connect(_on_achievement_unlocked)
                        if ach_inst.has_signal("achievement_progressed"):
                                ach_inst.achievement_progressed.connect(_on_achievement_progressed)

func _on_achievement_unlocked(player_id: String, achievement_id: String) -> void:
        if player_id != _player_id:
                return
        _refresh_achievements()

func _on_achievement_progressed(player_id: String, achievement_id: String, progress: float) -> void:
        if player_id != _player_id:
                return
        _refresh_achievements()

func open(panel_id: String = "") -> void:
        visible = true
        panel_opened.emit()
        _load_achievement_definitions()
        _refresh_achievements()

func close() -> void:
        visible = false
        panel_closed.emit()

func toggle(panel_id: String = "") -> void:
        if visible:
                close()
        else:
                open(panel_id)

func is_open() -> bool:
        return visible

func set_player_id(player_id: String) -> void:
        _player_id = player_id
        if visible:
                _refresh_achievements()

func _load_achievement_definitions() -> void:
        var root := get_tree().root if get_tree() else null
        if root:
                var ach_inst: Node = root.get_node_or_null("AchievementService")
                if ach_inst and ach_inst.has_method("get_all_achievements"):
                        _achievement_defs = ach_inst.get_all_achievements()

func _get_achievement_list() -> Array:
        var list: Array = []
        for ach_id in _achievement_defs:
                list.append(_achievement_defs[ach_id])
        list.sort_custom(func(a, b): return a.sort_order < b.sort_order)
        return list

func _get_player_progress(achievement_id: String) -> Dictionary:
        var root := get_tree().root if get_tree() else null
        if root:
                var ach_inst: Node = root.get_node_or_null("AchievementService")
                if ach_inst and ach_inst.has_method("get_achievement_progress"):
                        return ach_inst.get_achievement_progress(_player_id, achievement_id)
        return {"progress": 0.0, "unlocked": false}

func _refresh_achievements() -> void:
        var list: VBoxContainer = get_node_or_null("VBox/AchievementScroll/AchievementList")
        if not list:
                return

        for child in list.get_children():
                child.queue_free()

        var all_achievements: Array = _get_achievement_list()
        var unlocked_count := 0

        for ach in all_achievements:
                var progress: Dictionary = _get_player_progress(ach.id)
                var row := _create_achievement_row(ach, progress)
                list.add_child(row)
                if progress.get("unlocked", false):
                        unlocked_count += 1

        _update_stats(unlocked_count, all_achievements.size())

func _create_achievement_row(ach: AchievementData, progress: Dictionary) -> Control:
        var panel := PanelContainer.new()
        panel.custom_minimum_size.y = 60

        var hbox := HBoxContainer.new()
        panel.add_child(hbox)

        var is_unlocked: bool = progress.get("unlocked", false)

        var icon := Label.new()
        icon.text = "★" if is_unlocked else "☆"
        icon.add_theme_color_override("font_color", Color.GOLD if is_unlocked else Color.DIM_GRAY)
        hbox.add_child(icon)

        var info_vbox := VBoxContainer.new()
        info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        hbox.add_child(info_vbox)

        var name_lbl := Label.new()
        name_lbl.text = ach.display_name
        name_lbl.add_theme_color_override("font_color", Color.WHITE if is_unlocked else Color.DIM_GRAY)
        info_vbox.add_child(name_lbl)

        var desc_lbl := Label.new()
        desc_lbl.text = ach.description if is_unlocked or not ach.hidden else ach.secret_description
        desc_lbl.add_theme_font_size_override("font_size", 10)
        desc_lbl.add_theme_color_override("font_color", Color.GRAY)
        info_vbox.add_child(desc_lbl)

        if ach.achievement_type != AchievementData.AchievementType.GLOBAL:
                var progress_val: float = progress.get("progress", 0.0)
                var percentage: float = ach.get_progress_percentage(progress_val)
                var progress_lbl := Label.new()
                progress_lbl.text = "%d / %d (%.0f%%)" % [progress_val, ach.target, percentage * 100]
                progress_lbl.add_theme_font_size_override("font_size", 10)
                progress_lbl.add_theme_color_override("font_color", Color.LIGHT_BLUE)
                info_vbox.add_child(progress_lbl)

        return panel

func _update_stats(unlocked: int, total: int) -> void:
        var stats: Label = get_node_or_null("VBox/Stats")
        if stats:
                stats.text = "Unlocked: %d / %d" % [unlocked, total]
