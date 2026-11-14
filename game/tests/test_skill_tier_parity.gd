## Receipt: the skill-upgrade ladder is ONE law, and signatures resolve.
##
## Two real defects motivated this round:
##
##  1. The `common -> mythic` ladder was inlined in SEVEN places
##     (SkillAcademyService, DataService, GroundLootService, SkillBook,
##     SkillAcademyUI, CharacterStatsUI, the integrity test) and two of
##     them DISAGREED on the stat thresholds: both UIs said
##     0/30/60/90/120 while skill.gd's own `upgrade_tiers` deltas said
##     30/60/90/120/150 -- an off-by-one that only stayed invisible
##     because every `min_stat` was blank. core/schemas/skill_tier.gd is
##     now the single source; every consumer reads it.
##
##  2. `get_signature_schema` read `_catalog`, which holds UPGRADABLE
##     skills ONLY -- so it returned null for EVERY real signature, and
##     `get_signature_info` silently rendered an empty list. Signatures
##     are non-upgradable by definition; the lookup now goes through
##     DataService, the same place get_class_signatures reads.
##
## The data law this round also pins: every class ships exactly 3
## signatures, and every non-signature skill is upgradable (no orphan
## un-upgradable non-signature).
##
## Run: godot --headless --path game --script res://tests/test_skill_tier_parity.gd
extends SceneTree

const SkillTier = preload("res://core/schemas/skill_tier.gd")

var _passed: int = 0
var _failed: int = 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("   PASS  %s" % msg)
	else:
		_failed += 1
		print("   FAIL  %s" % msg)


func _finish() -> void:
	print("=== SKILL TIER PARITY RECEIPT: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ds = root.get_node_or_null("DataService")
	if ds != null and not ds._loaded and ds.has_method("load_all_data"):
		ds.load_all_data()
	await process_frame

	# --- 1. The canonical ladder ----------------------------------------
	_check(SkillTier.TIER_NAMES.size() == 5, "the ladder is FIVE rungs (not the six-rung item rarity)")
	_check(SkillTier.name_of(1) == "common" and SkillTier.name_of(5) == "mythic",
			"the rungs run common -> mythic")
	_check(SkillTier.level_of("mythic") == 5 and SkillTier.level_of("nonsense") == 0,
			"level_of round-trips and rejects a non-rung")
	_check(SkillTier.threshold("common") == 0 and SkillTier.threshold("mythic") == 120,
			"the canonical thresholds are 0..120")

	# --- 2. No consumer re-declares the ladder --------------------------
	# The old inline arrays/dicts are gone; the remaining references are
	# aliases onto SkillTier. Guard the two aliases that MUST agree.
	var acad = root.get_node_or_null("SkillAcademyService")
	_check(acad != null, "SkillAcademyService present")
	if acad != null:
		_check(acad.TIER_NAMES == SkillTier.TIER_NAMES,
				"SkillAcademyService.TIER_NAMES is the canonical array")
		_check(acad.TIER_TO_LEVEL == SkillTier.TIER_LEVELS,
				"SkillAcademyService.TIER_TO_LEVEL is the canonical map")
		_check(acad.BOOKS_PER_UPGRADE == SkillTier.BOOKS_PER_UPGRADE and acad.BOOKS_PER_UPGRADE == 4,
				"four books per upgrade")

	# --- 3. Every consumer produces the SAME book id --------------------
	# The academy producer and the loot-table producer must agree byte for
	# byte, or a loot drop names a book the academy cannot consume.
	if acad != null and ds != null:
		var a: Item = acad.create_book("human_charge", "epic")
		var b: Item = ds.get_item("book_human_charge_epic")
		_check(a != null and b != null, "both producers build book_human_charge_epic")
		if a != null and b != null:
			_check(str(a.id) == str(b.id), "academy + loot producers agree on the id")
			_check(int(a.book_upgrade_level) == int(b.book_upgrade_level),
					"and on the upgrade level (epic = 3)")

	# --- 4. An unknown tier is refused, not silently defaulted ----------
	if acad != null:
		_check(acad.create_book("human_charge", "platonic") == null,
				"an unknown tier yields no book (was a silent 'common' default)")
	if ds != null:
		_check(ds.get_item("book_human_charge_platonic") == null,
				"the loot path refuses an unknown tier too")

	# --- 5. The book gate is UPGRADABLE, on both producers --------------
	# A signature is non-upgradable, so no book may exist for it.
	if acad != null:
		_check(acad.create_book("akkan_gravity_well", "common") == null,
				"the academy refuses a signature book")
	if ds != null:
		_check(ds.get_item("book_akkan_gravity_well_common") == null,
				"the loot path refuses a signature book (parity)")

	# --- 6. Signatures resolve (the get_signature_schema bug) -----------
	if acad != null and ds != null:
		var sig_ids: Array = acad.get_class_signatures("human_warrior")
		_check(sig_ids.size() == 3, "human_warrior ships exactly 3 signatures (%d)" % sig_ids.size())
		var resolved: int = 0
		for sid in sig_ids:
			if acad.get_signature_schema(sid) != null:
				resolved += 1
		_check(resolved == sig_ids.size(),
				"get_signature_schema resolves EVERY signature (%d/%d)" % [resolved, sig_ids.size()])

	# --- 7. The data law across every class -----------------------------
	# Every class: exactly 3 signatures, and every non-signature upgradable.
	var by_class: Dictionary = {}
	for s in ds.get_all_skills():
		if s == null:
			continue
		var cid: String = str(s.required_class)
		if not by_class.has(cid):
			by_class[cid] = {"total": 0, "up": 0}
		by_class[cid]["total"] += 1
		if bool(s.upgradable):
			by_class[cid]["up"] += 1

	var bad_sig: Array = []
	var orphan: Array = []
	var unclassified: int = 0
	for cid in by_class:
		if cid == "":
			# Empty required_class is "any class", not a class of its own.
			unclassified = int(by_class[cid]["total"])
			continue
		var t: int = by_class[cid]["total"]
		var u: int = by_class[cid]["up"]
		var sig: int = t - u
		if sig != 3:
			bad_sig.append("%s=%d" % [cid, sig])
		if u == 0:
			orphan.append(cid)
	_check(bad_sig.is_empty(), "every class ships exactly 3 signatures (%s)" % ("ok" if bad_sig.is_empty() else ", ".join(bad_sig)))
	_check(orphan.is_empty(), "no class is all-signature")
	# The any-class skills are all upgradable (no signature is classless).
	_check(unclassified == 0 or unclassified == by_class[""]["up"],
			"the %d any-class skills are all upgradable" % unclassified)

	_finish()
