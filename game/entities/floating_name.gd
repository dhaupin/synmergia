## FloatingName - the world nameplate law.
##
## One attachment surface for every entity family: a billboard Label3D
## child named "NameLabel" hung above the entity's head. Entities keep
## no bespoke label code -- callers pass the plate kind and the helper
## sizes/colors it (bosses read big, enemies red, NPCs gold, players
## carry the title color). Idempotent: ensure() creates or updates the
## same child, so re-spawns and title changes restamp one node instead
## of stacking plates.
##
## Usage:   FloatingName.ensure(entity, entity.display_name, "enemy")
##          FloatingName.ensure(player, base_name, "player")
extends Node3D

## Kind tuning: font size + color + lift per plate family.
const KINDS := {
	"player": {"size": 18, "color": Color(0.92, 0.96, 1.0), "outline": 6, "lift": 2.4},
	"npc": {"size": 20, "color": Color(1.0, 0.85, 0.4), "outline": 6, "lift": 2.4},
	"enemy": {"size": 18, "color": Color(1.0, 0.45, 0.45), "outline": 6, "lift": 2.2},
	"elite": {"size": 24, "color": Color(1.0, 0.6, 0.2), "outline": 8, "lift": 2.6},
	"boss": {"size": 32, "color": Color(1.0, 0.3, 0.3), "outline": 10, "lift": 3.0},
}

## Compose the plate text: level bracket when level >= 1
## ("Wrathful Wolf [3]"), plain name otherwise.
static func compose_text(name: String, level: int = 0) -> String:
	if level >= 1:
		return "%s [%d]" % [name, level]
	return name


## Create-or-update the host's "NameLabel". Returns the label.
## Optional cfg keys:
##   tint: Color override (used for player title colors)
##   big: bool -> 2x font size (world bosses)
static func ensure(host: Node3D, text: String, kind: String = "npc", cfg: Dictionary = {}) -> Label3D:
	if host == null or not is_instance_valid(host):
		return null
	var label := host.get_node_or_null("NameLabel") as Label3D
	if label == null:
		label = Label3D.new()
		label.name = "NameLabel"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.double_sided = false
		host.add_child(label)
	var tuning: Dictionary = KINDS.get(kind, KINDS["npc"])
	var color: Color = cfg.get("tint", tuning["color"])
	var scale_big := 2 if bool(cfg.get("big", false)) else 1
	label.text = text
	label.modulate = color
	label.font_size = int(tuning["size"]) * scale_big
	label.outline_size = int(tuning["outline"])
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.pixel_size = 0.008
	# Lift based on the kind's normal height; big plates sit a bit
	# higher so a boss-level font does not clip into the body.
	label.position = Vector3(0, float(tuning["lift"]) + (0.6 if scale_big == 2 else 0.0), 0)
	return label


## Refresh a player's plate text from TitleService: prefix before the
## name, suffix after ("[The Slayer] Fang, the unbroken"). Falls back
## to the bare name when the service or a prefix/suffix is missing.
static func player_text(entity: Node) -> String:
	var base_name := ""
	if "display_name" in entity and str(entity.display_name) != "":
		base_name = str(entity.display_name)
	elif "entity_id" in entity:
		base_name = str(entity.entity_id)
	else:
		base_name = entity.name
	var title_svc: Node = null
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		title_svc = (ml as SceneTree).root.get_node_or_null("TitleService")
	if title_svc == null:
		return base_name
	return str(title_svc.call("get_display_name", str(entity.get("entity_id")), base_name))
