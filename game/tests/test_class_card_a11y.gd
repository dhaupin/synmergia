## test_class_card_a11y - the class card is the screen-reader door to character
## creation. A blind player hears ONLY the select button's name and
## description: the Role / Resource / Armor / Skills labels are drawn, never
## announced. So the description must carry them, and it must DIFFER per class.
##
## Regression this pins: `ClassCard.setup()` built the description from
## `role_label.text` BEFORE assigning it, so every class announced the scene
## file's placeholder ("Melee DPS"). A Tank and a Healer were indistinguishable
## to a screen reader, and the card silently lied about the role.
##
## Run: cd game && godot --headless --path . --script res://tests/test_class_card_a11y.gd
extends SceneTree

const CARD := preload("res://ui/menus/class_card.tscn")
const CharacterClass := preload("res://core/schemas/character_class.gd")

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	await _run()
	print("class_card_a11y: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _check(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % what)
	else:
		_fail += 1
		print("FAIL: %s" % what)

func _card(display_name: String, role: int, resource: int) -> Dictionary:
	var card = CARD.instantiate()
	root.add_child(card)
	await process_frame
	var c := CharacterClass.new()
	c.id = "test_%d" % role
	c.display_name = display_name
	c.set("role", role)
	c.set("resource_type", resource)
	c.can_use_armor = {"cloth": true, "leather": true, "mail": false, "plate": false}
	card.setup(c, null)
	return {
		"card": card,
		"btn": card.get_node("Margin/VBox/SelectBtn"),
		"role_label": card.get_node("Margin/VBox/Role"),
	}

func _run() -> void:
	await _test_descriptions_differ_by_role()
	await _test_no_placeholder_leaks()
	_test_role_words_are_prose()
	await _test_every_class_in_data_speaks()

func _test_descriptions_differ_by_role() -> void:
	var tank := await _card("Bulwark", CharacterClass.Role.TANK, CharacterClass.ResourceType.RAGE)
	var heal := await _card("Shaman", CharacterClass.Role.HEALER, CharacterClass.ResourceType.MANA)
	var a := String(tank["btn"].accessibility_description)
	var b := String(heal["btn"].accessibility_description)
	_check(a != b, "a Tank and a Healer announce DIFFERENT descriptions")
	_check(a.contains("Tank"), "the Tank card says Tank (got: %s)" % a)
	_check(b.contains("Healer"), "the Healer card says Healer (got: %s)" % b)
	_check(String(tank["btn"].accessibility_name) == "Play Bulwark", "the card names the choice (Play Bulwark)")
	for d in [a, b]:
		_check(d.contains("Resource:") and d.contains("Armor:") and d.contains("Skills:"),
			"the description carries the drawn-only labels (got: %s)" % d)

func _test_no_placeholder_leaks() -> void:
	var retired := "Melee DPS"
	var leaked := []
	for role in [CharacterClass.Role.TANK, CharacterClass.Role.DD, CharacterClass.Role.MAGE,
			CharacterClass.Role.ROGUE, CharacterClass.Role.BENDER, CharacterClass.Role.HEALER]:
		var card := await _card("X", role, CharacterClass.ResourceType.MANA)
		if String(card["btn"].accessibility_description).contains(retired):
			leaked.append(role)
	_check(leaked.is_empty(), "no class announces the scene placeholder (%s)" % [str(leaked)])

func _test_role_words_are_prose() -> void:
	var bad := []
	for role in CharacterClass.ROLE_LABELS.keys():
		var word := CharacterClass.role_label(role)
		if word == "" or word == "Adventurer" or word.contains("_") or word.length() <= 2:
			bad.append("%d->%s" % [role, word])
	_check(bad.is_empty(), "every role has a spoken word, not an enum key (%s)" % [str(bad)])

func _test_every_class_in_data_speaks() -> void:
	var dir := DirAccess.open("res://data/classes")
	if dir == null:
		_check(false, "res://data/classes is readable")
		return
	var silent := []
	var n := 0
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var c = load("res://data/classes/" + f)
		if c == null or not (c is CharacterClass):
			continue
		n += 1
		var card := await _card(c.display_name, int(c.role), int(c.resource_type))
		var d := String(card["btn"].accessibility_description)
		if d.strip_edges() == "" or not d.contains(CharacterClass.role_label(int(c.role))):
			silent.append(f)
	_check(n > 0, "the shipped class catalog was read (%d classes)" % n)
	_check(silent.is_empty(), "all %d shipped classes announce their role (%s)" % [n, str(silent)])
