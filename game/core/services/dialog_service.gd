## DialogService - NPC dialogue loading and state management
## Loads DialogueData resources from data/dialogues/*.tres and drives DialogUI.
extends Node
# QoSService uses static shim methods (AGENTS.md allowlist); the const is required.
const QoSService = preload("res://core/autoload/qos_service.gd")

## Tree-safe GameLog lookup (script-mode-safe; the bare identifier
## fails compile when autoloads are absent -- test_islands).
func _glog() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameLog")) if tree and tree.root else null

## Tree-safe QuestService lookup (script-mode-safe).
func _quest_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("QuestService")) if tree and tree.root else null

## Tree-safe FollowService lookup (script-mode-safe).
func _follow_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("FollowService")) if tree and tree.root else null

## Tree-safe WaypointService lookup (script-mode-safe).
func _waypoint_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("WaypointService")) if tree and tree.root else null

## Tree-safe InventoryService lookup (script-mode-safe).
func _inv_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("InventoryService")) if tree and tree.root else null

## Tree-safe TitleService lookup (script-mode-safe).
func _title_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("TitleService")) if tree and tree.root else null

## Tree-safe SkillAcademyService lookup (script-mode-safe).
func _academy_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("SkillAcademyService")) if tree and tree.root else null

## Tree-safe _pmgr() lookup (script-mode-safe).
func _pmgr() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("PlayerManager")) if tree and tree.root else null

## Resolve an Item resource by id through DataService (the static data
## catalog), late-loaded so script-mode receipts stay autoload-safe.
func _resolve_item(item_id: String):
	if item_id.is_empty():
		return null
	var ds = _data_svc()
	if ds != null and ds.has_method("get_item"):
		return ds.get_item(item_id)
	return null

func _data_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("DataService")) if tree and tree.root else null

## Singleton instance (use singleton() to access)
static var _instance: Node = null
func _enter_tree() -> void:
	# Converge singleton() onto the autoload instance. Without this,
	# singleton() lazily created a SECOND DialogService and UI code
	# bound to its signals while npc_entity.gd emitted on the autoload
	# -- split brain, DialogUI never received dialogue_started.
	if _instance == null:
		_instance = self
static func singleton() -> Node:
	if _instance == null:
		_instance = load("res://core/services/dialog_service.gd").new()
		_instance._ready()
	return _instance

## BBCode XSS escape (AGENTS.md "Security: BBCode XSS").
## DialogUI renders user-supplied text in RichLabels; unescaped [ and ]
## let a player inject formatting/color/URL tags. We neutralize '[' to
## the [lb] literal-bracket tag; a bare ']' cannot open a tag, so it
## needs no escaping (escaping it corrupted the [lb] we had inserted).
static func _esc(text: String) -> String:
	return text.replace("[", "[lb]")

const DialogueData = preload("res://core/schemas/dialogue_data.gd")
# ShopUI and UIStyles are not autoloads (class_name only).
# MenuManager is NOT preloaded here: it pulls in dialog_ui.gd at
# parse time, which preloads dialog_service.gd (this file), forming
# a 3-node cyclic preload that 4.7.2 rejects. MenuManager exposes a
# static open_menu() facade, so the call site below resolves it
# lazily via the class_name registered when menu_manager.gd loads.
const ShopUI = preload("res://ui/components/shop_ui.gd")
const UIStyles = preload("res://ui/components/ui_styles.gd")

var _dialogues: Dictionary = {}
var _current_dialogue: DialogueData = null
var _current_node: int = 0
var _dialogue_seen: Dictionary = {}  # dialogue_id -> max node index reached (per-player memory, prd-dialogue sec.3)

signal dialogue_started(npc_id: String, dialogue_id: String)
signal dialogue_ended(npc_id: String, dialogue_id: String)
signal node_changed(node_index: int, node_data: Dictionary)
signal action_executed(action_type: int, action_data: Dictionary)

func _ready() -> void:
	_load_dialogues()
	var _gl := _glog()
	if _gl:
		_gl.info("DialogService: Loaded %d dialogues" % _dialogues.size())

const ResourceScan = preload("res://core/frame/srv/resource_scan.gd")

func _load_dialogues() -> void:
	# Export-safe scan: the pack stores .tres as .res + .tres.remap.
	var paths := ResourceScan.list_resources("res://data/dialogues")
	if paths.is_empty() and DirAccess.open("res://data/dialogues") == null:
		var _gl := _glog()
		if _gl:
			_gl.warn("DialogService: No data/dialogues/ directory")
		return
	for p in paths:
		var dialogue: DialogueData = load(p)
		if dialogue and dialogue.id != "":
			_dialogues[dialogue.id] = dialogue

func get_dialogue(dialogue_id: String) -> DialogueData:
	return _dialogues.get(dialogue_id)

func start_dialogue(npc_id: String, dialogue_id: String) -> bool:
	# QoS: Rate limit dialogue starts
	var player_id := get_local_player_id()
	if QoSService and player_id and not QoSService.rate_limit(player_id, "dialogue"):
		return false

	var dialogue: DialogueData = get_dialogue(dialogue_id)
	if dialogue == null:
		var _gl := _glog()
		if _gl:
			_gl.warn("DialogService: Dialogue not found: %s" % _esc(dialogue_id))
		return false
	_current_dialogue = dialogue
	_current_node = 0
	_mark_seen(dialogue_id, 0)
	dialogue_started.emit(_esc(npc_id), _esc(dialogue_id))
	node_changed.emit(_current_node, _node_to_dict(dialogue.get_node(_current_node)))
	return true

func advance() -> Dictionary:
	if _current_dialogue == null or _current_dialogue.nodes.is_empty():
		end_dialogue()
		return {}
	var node := _current_dialogue.get_node(_current_node)
	if not _has_choices(node):
		var leaving: Dictionary = node
		_current_node += 1
		# Node action fires on advance-out of auto-advance nodes (prd-dialogue sec.5:
		# choice actions fire in select_choice; node actions fire when leaving).
		_execute_node_action(leaving)
	if _current_node < 0 or _current_node >= _current_dialogue.nodes.size():
		end_dialogue()
		return {}
	var node_dict := _node_to_dict(_current_dialogue.get_node(_current_node))
	node_changed.emit(_current_node, node_dict)
	return node_dict

func select_choice(choice_index: int) -> Dictionary:
	if _current_dialogue == null:
		return {}
	var choices: Array[Dictionary] = _current_dialogue.get_choices(_current_node)
	if choice_index < 0 or choice_index >= choices.size():
		return {}
	var next: int = choices[choice_index].get("next_node", -1)
	# Choice action fires BEFORE navigation (prd-dialogue sec. 5). The
	# outgoing choice may mutate state (GIVE_QUEST, GIVE_ITEM) that the
	# destination node's condition layer then reads.
	var chosen: Dictionary = choices[choice_index]
	_execute_choice_action(chosen)
	if next < 0:
		end_dialogue()
		return {}
	_current_node = next
	_mark_seen(_current_dialogue.id, _current_node)
	if _current_node < 0 or _current_node >= _current_dialogue.nodes.size():
		end_dialogue()
		return {}
	var node_dict := _node_to_dict(_current_dialogue.get_node(_current_node))
	node_changed.emit(_current_node, node_dict)
	return node_dict

func get_current_node() -> Dictionary:
	if _current_dialogue == null:
		return {}
	if _current_node < 0 or _current_node >= _current_dialogue.nodes.size():
		return {}
	return _node_to_dict(_current_dialogue.get_node(_current_node))

func _has_choices(node: Dictionary) -> bool:
	if not node.has("choices"):
		return false
	var choices: Array = node["choices"]
	return not choices.is_empty()

func _node_to_dict(node: Dictionary) -> Dictionary:
	var choices: Array[Dictionary] = []
	if node.has("choices"):
		for choice: Dictionary in node["choices"]:
			choices.append({
				"text": choice.get("text", ""),
				"next": choice.get("next_node", -1)
			})
	return {
		"speaker": node.get("speaker", ""),
		"text": node.get("text", ""),
		"choices": choices
	}

func end_dialogue() -> void:
	var npc_id: String = _current_dialogue.npc_id if _current_dialogue else ""
	var dialogue_id: String = _current_dialogue.id if _current_dialogue else ""
	_current_dialogue = null
	_current_node = 0
	dialogue_ended.emit(npc_id, dialogue_id)

## Per-player conversation memory (prd-dialogue sec.3): records the
## furthest node reached per dialogue_id. In-memory this cut; persists
## through the existing player-state path when the state-schema
## extension lands. Never stores transcript text.
func _mark_seen(dialogue_id: String, node_index: int) -> void:
	if dialogue_id.is_empty():
		return
	var prev: int = _dialogue_seen.get(dialogue_id, -1)
	if node_index > prev:
		_dialogue_seen[dialogue_id] = node_index

func get_seen_node(dialogue_id: String) -> int:
	return _dialogue_seen.get(dialogue_id, -1)

func has_seen_dialogue(dialogue_id: String) -> bool:
	return _dialogue_seen.has(dialogue_id)

func has_dialogue(dialogue_id: String) -> bool:
	return _dialogues.has(dialogue_id)

## Fire a choice's action (before navigation). Non-NONE only; failures
## log but never block the tree (prd-dialogue sec. 5: actions are
## best-effort mutations the destination conditions then read).
func _execute_choice_action(choice: Dictionary) -> void:
	var at: int = choice.get("action_type", 0)
	if at == 0:
		return
	var ad: Dictionary = choice.get("action_data", {})
	var player_id := get_local_player_id()
	var ok := execute_action(at, ad, player_id)
	var _gl := _glog()
	if _gl:
		if ok:
			_gl.info("DialogAction: choice fired type=%d dialogue=%s" % [at, _current_dialogue.id if _current_dialogue else "?"])
		else:
			_gl.warn("DialogAction: choice FAILED type=%d dialogue=%s" % [at, _current_dialogue.id if _current_dialogue else "?"])

## Fire a node's action on advance-out of an auto-advance (choicesless)
## node. Closing nodes consolidate rewards this way (prd-dialogue sec. 5).
func _execute_node_action(node: Dictionary) -> void:
	var at: int = node.get("action_type", 0)
	if at == 0:
		return
	var ad: Dictionary = node.get("action_data", {})
	var player_id := get_local_player_id()
	var ok := execute_action(at, ad, player_id)
	var _gl := _glog()
	if _gl:
		if ok:
			_gl.info("DialogAction: node fired type=%d dialogue=%s" % [at, _current_dialogue.id if _current_dialogue else "?"])
		else:
			_gl.warn("DialogAction: node FAILED type=%d dialogue=%s" % [at, _current_dialogue.id if _current_dialogue else "?"])

func execute_action(action_type: int, action_data: Dictionary, player_id: String = "") -> bool:
	var DialogActionType = DialogueData.DialogActionType
	match action_type:
		DialogActionType.NONE:
			return true
		DialogActionType.GIVE_QUEST:
			var quest_id: String = action_data.get("quest_id", "")
			if _quest_svc() and quest_id:
				return _quest_svc().accept_quest(player_id, quest_id)
		DialogActionType.COMPLETE_QUEST:
			var quest_id: String = action_data.get("quest_id", "")
			if _quest_svc() and quest_id:
				return _quest_svc().turn_in_quest(player_id, quest_id)
		DialogActionType.ABANDON_QUEST:
			var quest_id: String = action_data.get("quest_id", "")
			if _quest_svc() and quest_id:
				_quest_svc().abandon_quest(player_id, quest_id)
				return true
		DialogActionType.START_FOLLOW:
			var target_id: String = action_data.get("target_id", "")
			if _follow_svc() and target_id:
				return _follow_svc().request_follow(player_id, target_id)
		DialogActionType.STOP_FOLLOW:
			if _follow_svc():
				# FollowService exposes stop_follow, not cancel_follow --
				# the old call was a nonexistent method (silent no-op).
				# Return the real result (false when not following).
				return _follow_svc().stop_follow(player_id, "dialogue")
		DialogActionType.OPEN_SHOP:
			var shop_id: String = action_data.get("shop_id", "")
			if ShopUI:
				ShopUI.open_shop(shop_id)
				return true
		DialogActionType.OPEN_VAULT:
			# The vault panel is registered as "bank" in MenuManager
			# (BankUI). There is no VaultUI class -- the old reference
			# was a dangling identifier that also made this branch
			# return a Node from a String-returning function.
			# MenuManager is NOT preloaded here (it would form a
			# cyclic preload: dialog_service -> menu_manager ->
			# dialog_ui -> dialog_service). Load it lazily at the
			# call site instead.
			var MenuManager = load("res://ui/components/menu_manager.gd")
			if MenuManager:
				MenuManager.open_menu("bank")
				return true
		DialogActionType.SET_WAYPOINT:
			var wp_name: String = action_data.get("name", "Marker")
			var color: int = action_data.get("color", 0)
			if _waypoint_svc():
				# _waypoint_svc().create_waypoint would be called with player pos
				var _gl := _glog()
				if _gl:
					_gl.debug("DialogAction: SET_WAYPOINT '%s'" % wp_name)
				return true
		DialogActionType.GIVE_ITEM:
			var item_id: String = action_data.get("item_id", "")
			var quantity: int = action_data.get("quantity", 1)
			if _inv_svc() and item_id:
				# InventoryService has no add_item(player, item, qty): the
				# ONE purse is the mounted component. Resolve the item
				# through DataService and grant it there.
				var inv = _inv_svc().get_inventory(player_id) if _inv_svc().has_method("get_inventory") else null
				var item = _resolve_item(item_id)
				if inv != null and item != null and inv.has_method("add_item"):
					inv.add_item(item, quantity)
					return true
		DialogActionType.GIVE_CURRENCY:
			var amount: int = action_data.get("amount", 0)
			var currency: String = action_data.get("currency", "gold")
			if amount != 0:
				var inv = _inv_svc().get_inventory(player_id) if _inv_svc() and _inv_svc().has_method("get_inventory") else null
				if inv != null:
					if currency == "" or currency == "gold":
						if amount > 0:
							inv.add_gold(amount)
						else:
							inv.remove_gold(-amount)
						return true
					if amount > 0:
						inv.add_currency(currency, amount)
					else:
						inv.remove_currency(currency, -amount)
					return true
		DialogActionType.REMOVE_ITEM:
			var item_id: String = action_data.get("item_id", "")
			var quantity: int = action_data.get("quantity", 1)
			var inv = _inv_svc().get_inventory(player_id) if _inv_svc() and _inv_svc().has_method("get_inventory") else null
			if inv != null and item_id and inv.has_method("remove_item_by_id"):
				return inv.remove_item_by_id(item_id, quantity)
		DialogActionType.REMOVE_CURRENCY:
			var amount: int = action_data.get("amount", 0)
			var currency: String = action_data.get("currency", "gold")
			var inv = _inv_svc().get_inventory(player_id) if _inv_svc() and _inv_svc().has_method("get_inventory") else null
			if inv != null and amount > 0:
				if currency == "" or currency == "gold":
					return inv.remove_gold(amount)
				return inv.remove_currency(currency, amount)
		DialogActionType.UNLOCK_TITLE:
			# Resource.get(key, default) was removed in 4.7.2; the
			# guard already exists, so drop the default arg.
			var title_id: String = action_data.get("title_id")
			if _title_svc() and title_id:
				# TitleService's public grant is unlock() (a static shim);
				# unlock_title() never existed.
				_title_svc().unlock(player_id, title_id)
				return true
		DialogActionType.TEACH_SKILL:
			var skill_id: String = action_data.get("skill_id")
			if _academy_svc() and skill_id:
				# Skills are learned by consuming a SkillBook item; the
				# academy grants one through the ONE purse. unlock_skill()
				# never existed.
				var book = _academy_svc().create_book(skill_id, "common")
				var inv = _inv_svc().get_inventory(player_id) if _inv_svc() and _inv_svc().has_method("get_inventory") else null
				if book != null and inv != null and inv.has_method("add_item"):
					inv.add_item(book, 1)
					return true
		_:
			var _gl := _glog()
			if _gl:
				_gl.warn("DialogAction: Unknown action type %d" % action_type)
			return false
	return false

func get_local_player_id() -> String:
	if _pmgr():
		var player = _pmgr().get_local_player()
		if player and "entity_id" in player:
			return player.entity_id
	return ""
