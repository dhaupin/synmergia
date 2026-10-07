## Static registry mapping island names to UI resources.
##
## Supports both scene-based islands (PackedScene) and script-only components.
## All entries use [code]preload[/code] for parse-time resolution.
##
## To add a new island:
## 1. For scenes: preload your scene path (see entries below for the shape)
## 2. For scripts: preload your script path
## 3. Add entry to [code]ISLANDS[/code]
##
## Consumers: [code]IslandRegistry.resolve("name")[/code]
extends Node
class_name IslandRegistry

# === Scene-based islands ===
const COOLDOWN_BAR := preload("res://ui/components/cooldown_bar.tscn")
const REPORT_DIALOG := preload("res://ui/player/report_dialog.tscn")
const PLAYER_TARGET_TOOLTIP := preload("res://ui/player/player_target_tooltip.tscn")
const MAIN_MENU := preload("res://ui/menus/main_menu.tscn")
const RESPAWN_UI := preload("res://ui/respawn/respawn_ui.tscn")
const VOTING_UI := preload("res://ui/community/voting_ui.tscn")
const ADMIN_DASHBOARD := preload("res://ui/admin/admin_dashboard.tscn")
const ADMIN_TOOLBAR := preload("res://ui/admin/admin_toolbar.tscn")

# === Script-based components ===
const ACTION_BAR := preload("res://ui/components/action_bar.gd")
const INVENTORY_UI := preload("res://ui/components/inventory_ui.gd")
const BANK_UI := preload("res://ui/components/bank_ui.gd")
const SHOP_UI := preload("res://ui/components/shop_ui.gd")
const CHARACTER_PANEL := preload("res://ui/components/character_panel.gd")
const BUFF_BAR := preload("res://ui/components/buff_bar.gd")
const QUICK_ACCESS_BAR := preload("res://ui/components/quick_access_bar.gd")
const MINIMAP := preload("res://ui/components/minimap.gd")
const TARGET_FRAME := preload("res://ui/components/target_frame.gd")
const ACTION_MENU := preload("res://ui/components/action_menu.gd")
const DIALOG_UI := preload("res://ui/components/dialog_ui.gd")
const SETTINGS_PANEL := preload("res://ui/components/settings_panel.gd")
const COMBAT_LOG := preload("res://ui/components/combat_log.gd")
const MOUNT_UI := preload("res://ui/components/mount_ui.gd")

const ISLANDS: Dictionary = {
	# Scenes
	"cooldown_bar": COOLDOWN_BAR,
	"report_dialog": REPORT_DIALOG,
	"player_target_tooltip": PLAYER_TARGET_TOOLTIP,
	"main_menu": MAIN_MENU,
	"respawn_ui": RESPAWN_UI,
	"voting_ui": VOTING_UI,
	"admin_dashboard": ADMIN_DASHBOARD,
	"admin_toolbar": ADMIN_TOOLBAR,
	# Scripts
	"action_bar": ACTION_BAR,
	"inventory": INVENTORY_UI,
	"bank": BANK_UI,
	"shop": SHOP_UI,
	"character_panel": CHARACTER_PANEL,
	"buff_bar": BUFF_BAR,
	"quick_access_bar": QUICK_ACCESS_BAR,
	"minimap": MINIMAP,
	"target_frame": TARGET_FRAME,
	"action_menu": ACTION_MENU,
	"dialog": DIALOG_UI,
	"settings": SETTINGS_PANEL,
	"combat_log": COMBAT_LOG,
	"mounts": MOUNT_UI,
}

const TRIGGERS: Dictionary = {
	"inventory": ["inventory", "bag", "loot", "items", "backpack"],
	"guild": ["guild", "clan", "roster"],
	"trade": ["trade", "buy", "sell", "vendor", "shop"],
	"party": ["party", "group", "raid"],
	"mounts": ["mount", "stable"],
	"action_menu": ["examine", "use", "talk", "open"],
}

static func resolve(name: String) -> PackedScene:
	return ISLANDS.get(name, null)


static func has(name: String) -> bool:
	return ISLANDS.has(name)


static func all_names() -> Array[String]:
	var out: Array[String] = []
	for key in ISLANDS.keys():
		out.append(String(key))
	return out


## Scan a string (e.g. a chat input) for trigger words and return the
## islands that should be pre-loaded. Static helper -- no instance needed.
static func islands_triggered_by(text: String) -> Array[String]:
	var lower := text.to_lower()
	var needed: Array[String] = []
	for island in TRIGGERS:
		for trigger in TRIGGERS[island]:
			if lower.contains(String(trigger)):
				needed.append(String(island))
				break
	return needed
