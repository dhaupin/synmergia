## Static registry mapping island names to [PackedScene] resources.
##
## The ONLY place that holds parse-time references to UI scenes. Because
## every entry is a [code]const X = preload(...)[/code], the GDScript
## parser resolves the path at parse time -- no class_name lookups, no
## autoload race, no cascade.
##
## To add a new island:
## 1. Add a [code]const X = preload("res://path/to/scene.tscn")[/code] line
## 2. Add an entry to [code]ISLANDS[/code]
##
## Consumers do [code]IslandRegistry.resolve("inventory")[/code].
##
## [b]Note on the existing list[/b]: only scenes that already exist in
## the project are wired in. Other entries are pre-commented for the
## next migration session -- they will be added when the matching
## scenes are created or moved to the [code]res://ui/[/code] tree.
class_name IslandRegistry
extends Node

# --- Existing scenes (wired in) ---
const COOLDOWN_BAR := preload("res://ui/components/cooldown_bar.tscn")
const REPORT_DIALOG := preload("res://ui/player/report_dialog.tscn")
const PLAYER_TARGET_TOOLTIP := preload("res://ui/player/player_target_tooltip.tscn")
const MAIN_MENU := preload("res://ui/menus/main_menu.tscn")
const RESPAWN_UI := preload("res://ui/respawn/respawn_ui.tscn")
const VOTING_UI := preload("res://ui/community/voting_ui.tscn")
const ADMIN_DASHBOARD := preload("res://ui/admin/admin_dashboard.tscn")
const ADMIN_TOOLBAR := preload("res://ui/admin/admin_toolbar.tscn")

# --- Future scenes (add when created) ---
# const HEALTH_BAR := preload("res://ui/hud/health_bar.tscn")
# const CHAT_BOX := preload("res://ui/hud/chat_box.tscn")
# const INVENTORY := preload("res://ui/panels/inventory_panel.tscn")
# const PARTY := preload("res://ui/panels/party_panel.tscn")
# const GUILD := preload("res://ui/panels/guild_panel.tscn")
# const TRADE := preload("res://ui/panels/trade_panel.tscn")
# const NOTIFICATION := preload("res://ui/hud/notification.tscn")
# const ACTION_MENU := preload("res://ui/components/action_menu.tscn")
# const TOOLTIP := preload("res://ui/components/tooltip.tscn")
# const BUFF_BAR := preload("res://ui/hud/buff_bar.tscn")
# const MINIMAP := preload("res://ui/hud/minimap.tscn")
# const TARGET_FRAME := preload("res://ui/targeting/target_frame.tscn")

const ISLANDS: Dictionary = {
	"cooldown_bar": COOLDOWN_BAR,
	"report_dialog": REPORT_DIALOG,
	"player_target_tooltip": PLAYER_TARGET_TOOLTIP,
	"main_menu": MAIN_MENU,
	"respawn_ui": RESPAWN_UI,
	"voting_ui": VOTING_UI,
	"admin_dashboard": ADMIN_DASHBOARD,
	"admin_toolbar": ADMIN_TOOLBAR,
}

const TRIGGERS: Dictionary = {
	"inventory": ["inventory", "bag", "loot", "items", "backpack"],
	"guild": ["guild", "clan", "roster"],
	"trade": ["trade", "buy", "sell", "vendor", "shop"],
	"party": ["party", "group", "raid"],
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
