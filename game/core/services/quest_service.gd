## QuestService - Player quest management
## Handles quest acceptance, progress tracking, and completion
extends Node
# QoSService uses static shim methods (AGENTS.md allowlist); the const is required.
const QoSService = preload("res://core/autoload/qos_service.gd")

const QuestData = preload("res://core/schemas/quest_data.gd")
# UIStyles is not an autoload (class_name only). QuestService
# references UIStyles.COLORS.X in BBColor formatting, which requires
# the class_name registered at parse time. Preload it here.
const UIStyles = preload("res://ui/components/ui_styles.gd")
const DictStore = preload("res://adapters/persistence/dict_store.gd")
const _kv_prefix := "quest:player:"

static func _esc(text: String) -> String:
	# Neutralize only '[': a bare ']' cannot open a BBCode tag. Replacing
	# ']' too corrupted the '[lb]' tokens the first replace had just
	# inserted ('[lb]' -> '[lb[rb]'), which RichTextLabel renders as
	# literal text. (AGENTS.md "Security: BBCode XSS".)
	return text.replace("[", "[lb]")

## Singleton
static var instance: QuestService

## Player quests: player_id -> {quest_id -> quest_state}
var _player_quests: Dictionary = {}

## Available quests per player: player_id -> [quest_ids]
var _available_quests: Dictionary = {}

## Epoch day of the last daily-quest reset (SignService day index).
## -1 until the first check; one reset pass per day boundary.
var _daily_reset_day: int = -1

## Signals
signal quest_accepted(player_id: String, quest_id: String)
signal quest_updated(player_id: String, quest_id: String, objective_id: String, progress: int)
signal quest_completed(player_id: String, quest_id: String)
signal quest_rewarded(player_id: String, quest_id: String, rewards: Dictionary)
signal quest_failed(player_id: String, quest_id: String, reason: String)

## Frame-level notification dispatch (typed-Kind pipeline).
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

# Limits
const MAX_ACTIVE_QUESTS: int = 20
const MAX_QUEST_NAME_LENGTH: int = 64

func _ready() -> void:
	instance = self
	GameLog.info("QuestService: Ready")
	_load_player_quests()
	_connect_combat_event_bridges()
	_connect_lore_event_bridges()
	# Insight bridge + daily reset need SignService (a LATER autoload,
	# the _ready null-instance trap) -- defer both past the boot. The
	# swim bridge reads OceanService (also later in the autoload list):
	# same deferral, one pattern.
	call_deferred("_connect_insight_bridge")
	call_deferred("_connect_swim_bridge")
	call_deferred("_maybe_reset_dailies")
	var reset_timer := Timer.new()
	reset_timer.wait_time = 60.0
	reset_timer.autostart = true
	reset_timer.timeout.connect(_maybe_reset_dailies)
	add_child(reset_timer)


## The sky-solve bridge (prd-psy.md section 10): RECORD_INSIGHT
## objectives credit SignService.insight_recorded. Target is the
## literal "sky_insight" -- quest .tres objectives author the same
## string, one credit path, no candidate fallbacks.
func _connect_insight_bridge() -> void:
	if SignService != null and SignService.has_signal("insight_recorded") \
			and not SignService.insight_recorded.is_connected(_on_insight_recorded):
		SignService.insight_recorded.connect(_on_insight_recorded)


## The swim credit bridge (the cistern's law, prd-ocean-depths):
## OceanService emits water_entered exactly once per dry -> wet entry
## with the ocean volume's data id; quest objectives target the
## ocean_ id verbatim. OceanService is a LATER autoload, so the
## connect is deferred like the insight bridge; has_signal makes the
## bridge optional (old pack contexts without the signal skip it).
func _connect_swim_bridge() -> void:
	var ocean = get_node_or_null("/root/OceanService")
	if ocean != null and ocean.has_signal("water_entered") \
			and not ocean.water_entered.is_connected(_on_water_entered_for_quest):
		ocean.water_entered.connect(_on_water_entered_for_quest)


func _on_water_entered_for_quest(body_id: String, volume_id: String) -> void:
	if str(body_id).is_empty() or str(volume_id).is_empty():
		return
	update_quest_progress(str(body_id), QuestData.ObjectiveType.SWIM, str(volume_id), 1)


func _on_insight_recorded(player_id: String, _sign_id: String, _window_index: int) -> void:
	update_quest_progress(player_id, QuestData.ObjectiveType.RECORD_INSIGHT, "sky_insight", 1)


## REWARDED daily quests re-accept at the day boundary (the missing
## reset that kept quest_type DAILY a screen saver). Erasing the
## REWARDED entry makes check_quest_availability offer it again; the
## wheel-almanac gate still applies -- accept, watch, earn.
func _maybe_reset_dailies() -> void:
	if SignService == null:
		return
	# The HUMAN day, not the sky's: the 2-hour sky day and the UTC day
	# both roll the board at meaningless hours (every 2 hours; 19:00
	# EST). Dailies reset at MIDNIGHT EASTERN (America/New_York, DST
	# honored) -- SignService.current_human_day_index shared clock,
	# admin time-travel still moves every calendar together.
	var day := SignService.current_human_day_index()
	if day == _daily_reset_day:
		return
	_daily_reset_day = day
	for player_id in _player_quests.keys():
		var quests: Dictionary = _player_quests[player_id]
		var reset := 0
		for quest_id in quests.keys():
			var state: Dictionary = quests[quest_id]
			var qstate := int(state.get("state", -1))
			var qdata = state.get("data")
			if qdata == null or not ("quest_type" in qdata):
				continue
			if int(qdata.quest_type) != QuestData.QuestType.DAILY:
				continue
			## Two boundary lives: REWARDED erases so the daily can be
			## earned again (the original fix), and an IN_PROGRESS daily
			## EXPIRES at dawn -- quest_failed had a listener state and
			## zero emitters, while stale half-done dailies dangled
			## across days. Erase keeps the catalog path identical to
			## the REWARDED reset.
			if qstate == QuestData.QuestState.IN_PROGRESS:
				quests.erase(quest_id)
				reset += 1
				quest_failed.emit(str(player_id), quest_id, "Daily expired at the midnight reset")
				continue
			if qstate != QuestData.QuestState.REWARDED:
				continue
			quests.erase(quest_id)
			reset += 1
		if reset > 0:
			_persist_player_quests(str(player_id))
			GameLog.info("QuestService: %d daily quest(s) reset for %s" % [reset, str(player_id)])

## ============================================================================
## EVENT BRIDGES (combat -> objectives)
## ============================================================================

## Wire combat events into objective tracking. update_quest_progress had
## zero callers -- objectives could never advance. The kill bridge feeds
## off EventHub.kill_rewarded (the same signal the HUD reward floats use),
## so credit semantics match the XP/gold payout exactly: direct killer
## first, threat-table owner as fallback (tank credit, heal threat).
## Party members ALSO progress shared "kill X" objectives when their
## party XP split shows they were present for the kill.
func _connect_combat_event_bridges() -> void:
	if EventHub != null and EventHub.has_signal("kill_rewarded") \
			and not EventHub.kill_rewarded.is_connected(_on_kill_rewarded_for_quest):
		EventHub.kill_rewarded.connect(_on_kill_rewarded_for_quest)

func _on_kill_rewarded_for_quest(entity, killer, rewards: Dictionary) -> void:
	if entity == null:
		return
	var target := ""
	if "display_name" in entity:
		target = str(entity.display_name)
	elif "entity_id" in entity:
		target = str(entity.entity_id)
	if target == "":
		return

	# Primary credit: whoever the reward resolved to (killer == credit).
	var credit_id := str(rewards.get("player_id", ""))
	if credit_id != "":
		update_quest_progress(credit_id, QuestData.ObjectiveType.KILL, target, 1)

	# Party members present for the kill also tick shared objectives.
	if rewards.get("party_shared", false):
		var distribution: Dictionary = rewards.get("party_distribution", {})
		for member_id in distribution:
			if str(member_id) == credit_id:
				continue
			update_quest_progress(str(member_id), QuestData.ObjectiveType.KILL, target, 1)

## ============================================================================
## EVENT BRIDGES (lore -> objectives)
## ============================================================================

## Talk + Collect bridges. Before these, only KILL objectives could ever
## advance: the Awakening (the game's first quest) is a TALK objective and
## the daily herb run is COLLECT -- both were permanently stuck. Talk
## credits by npc_ id (dialog_service emits dialogue_ended with the
## NPCData id; quest targets author the same id). Collect keys off the
## item's display_name, matching how quest .tres targets are authored
## ("Moonpetal Flower").
func _connect_lore_event_bridges() -> void:
	if DialogService != null and DialogService.has_signal("dialogue_ended") \
			and not DialogService.dialogue_ended.is_connected(_on_dialogue_ended_for_quest):
		DialogService.dialogue_ended.connect(_on_dialogue_ended_for_quest)
	if EventHub != null and EventHub.has_signal("item_picked_up") \
			and not EventHub.item_picked_up.is_connected(_on_item_picked_up_for_quest):
		EventHub.item_picked_up.connect(_on_item_picked_up_for_quest)
	if ZoneManager != null and ZoneManager.has_signal("player_entered_zone") \
			and not ZoneManager.player_entered_zone.is_connected(_on_player_entered_zone_for_quest):
		ZoneManager.player_entered_zone.connect(_on_player_entered_zone_for_quest)

## EXPLORE bridge: zone entry is the objective's world event.
## Data contract: objective targets use the ZoneData id verbatim
## ("zone_"-prefixed). One id style, one credit path -- no trimmed
## or display-name fallback candidates.
func _on_player_entered_zone_for_quest(player, zone) -> void:
	if player == null or zone == null:
		return
	var z_val = zone.get("id")
	if z_val == null or str(z_val) == "":
		return
	var pid_val = player.get("player_id")
	if pid_val == null or str(pid_val) == "":
		pid_val = player.get("entity_id")
	if pid_val == null or str(pid_val) == "":
		return
	update_quest_progress(str(pid_val), QuestData.ObjectiveType.EXPLORE, str(z_val), 1)

func _on_dialogue_ended_for_quest(npc_id: String, _dialogue_id: String) -> void:
	# Data contract: TALK objectives target the NPCData id verbatim
	# ("npc_"-prefixed). dialogue_ended already carries that id -- no
	# display-name resolution, no dual-candidate loop.
	var npc := str(npc_id)
	if npc.is_empty():
		return
	for player_id in _active_dialogue_players(npc):
		update_quest_progress(player_id, QuestData.ObjectiveType.TALK, npc, 1)

## Best-effort attribution for TALK credit: dialogue_ended carries no
## player id, so credit every player whose tracked quest is in progress
## with this npc id as an incomplete TALK objective. Small
## player counts make the scan cheap; correctness is exact because
## update_quest_progress re-validates the objective target.
func _active_dialogue_players(npc_name: String) -> Array:
	var out: Array = []
	for player_id in _player_quests.keys():
		var quests: Dictionary = _player_quests.get(player_id, {})
		if quests.is_empty():
			continue
		for quest_id in quests:
			var quest_state: Dictionary = quests[quest_id]
			if quest_state.get("state") != QuestData.QuestState.IN_PROGRESS:
				continue
			for obj in quest_state.get("objectives", []):
				if obj.get("type") == QuestData.ObjectiveType.TALK \
						and str(obj.get("target", "")) == npc_name \
						and not obj.get("completed", false):
					out.append(str(player_id))
					break
	return out

func _on_item_picked_up_for_quest(entity, item) -> void:
	if entity == null or item == null:
		return
	# .get() over `in` so dynamic and script properties both resolve.
	var player_id := ""
	var pid_val = entity.get("player_id")
	if pid_val == null or str(pid_val) == "":
		pid_val = entity.get("entity_id")
	if pid_val != null:
		player_id = str(pid_val)
	var target := ""
	var t_val = item.get("display_name")
	if t_val == null or str(t_val) == "":
		t_val = item.get("item_name")
	if t_val != null:
		target = str(t_val)
	if player_id == "" or target == "":
		return
	update_quest_progress(player_id, QuestData.ObjectiveType.COLLECT, target, 1)

## ============================================================================
## QUEST LOADING / PERSISTENCE
## ============================================================================

func load_player_quests(player_id: String) -> void:
	# The boot loader (_load_player_quests) reads the shared KV through
	# the DictStore with the quest:player:<id> key; the former db-stub
	# load returned {} and DISCARDED synced quest state. Read the same
	# living path per-player (a db-backed specialization stays a
	# later contract -- the adapter layer remains the only storage).
	var store := DictStore.new()
	var raw: Variant = store.get_value(_kv_prefix + player_id)
	if raw is Dictionary and not (raw as Dictionary).is_empty():
		_player_quests[player_id] = raw
		_available_quests[player_id] = _get_available_quest_ids(player_id)
	else:
		_player_quests[player_id] = {}
		_available_quests[player_id] = []
	GameLog.debug("QuestService: Loaded quests for %s" % player_id)

func save_player_quests(player_id: String) -> void:
	# The boot path's writer: the "sync to database" stub swallowed
	# the call, so per-player quest state silently never persisted.
	# Same KV the boot loader reads.
	_persist_player_quests(player_id)

func _get_available_quest_ids(player_id: String) -> Array:
	# Return quest IDs that the player can accept
	var available: Array = []
	var player_data: Dictionary = _player_quests.get(player_id, {})
	var player_level: int = _get_player_level(player_id)

	if DataService:
		# get_all_quests() returns the VALUES (Array[QuestData]); index
		# by the resource's own id, never by the value itself. The old
		# `all_quests[quest_id]` treated the value as a key (broken) and
		# `quest.get("min_level", 1)` used the Resource default arg that
		# 4.7.2 removed (runtime "Expected 1 argument(s)"). Round 20.
		var all_quests: Array = DataService.get_all_quests()
		for quest in all_quests:
			if not quest is QuestData:
				continue
			var qid: String = str(quest.id)
			if qid.is_empty():
				continue
			# Skip already accepted/completed quests
			if player_data.has(qid):
				continue
			# Check level requirement
			if player_level < int(quest.min_level):
				continue
			# Chain gate (same rule as check_quest_availability).
			if not _first_unmet_prereq(player_data, quest).is_empty():
				continue
			available.append(qid)
	return available

func get_player_quests(player_id: String) -> Dictionary:
	return _player_quests.get(player_id, {})

func get_active_quests(player_id: String) -> Array:
	var quests := []
	var player_data: Dictionary = _player_quests.get(player_id, {})
	for quest_id in player_data:
		var state: int = player_data[quest_id].get("state", QuestData.QuestState.LOCKED)
		if state == QuestData.QuestState.IN_PROGRESS:
			quests.append(quest_id)
	return quests

## ============================================================================
## QUEST AVAILABILITY
## ============================================================================

func get_available_quests(player_id: String) -> Array:
	# Return quests that can be accepted
	var available: Array = []
	var player_data: Dictionary = _player_quests.get(player_id, {})
	var player_level: int = _get_player_level(player_id)

	if DataService:
		# Values are QuestData resources; read exports directly (4.7.2
		# removed Resource.get's default arg). Round 20.
		var all_quests: Array = DataService.get_all_quests()
		for quest in all_quests:
			if not quest is QuestData:
				continue
			var qid: String = str(quest.id)
			if qid.is_empty():
				continue
			# Skip already accepted quests
			if player_data.has(qid):
				continue
			# Check level requirement
			var min_level: int = int(quest.min_level)
			if player_level < min_level:
				continue
			# Chain gate: the roster must not offer a quest whose authored
			# prerequisite is unmet, or the UI would list a quest the accept
			# gate then refuses.
			if not _first_unmet_prereq(player_data, quest).is_empty():
				continue
			var qname: String = str(quest.display_name)
			if qname.is_empty():
				qname = qid
			available.append({
				"id": qid,
				"name": qname,
				"description": str(quest.description),
				"min_level": min_level
			})
	return available

func check_quest_availability(player_id: String, quest_id: String) -> Dictionary:
	var result := {
		"available": false,
		"reason": ""
	}

	var quest := _load_quest_data(quest_id)
	if not quest:
		result.reason = "Quest not found"
		return result

	var player_data: Dictionary = _player_quests.get(player_id, {})

	# Check if already has quest
	if player_data.has(quest_id):
		var state: int = player_data[quest_id].get("state", QuestData.QuestState.LOCKED)
		if state == QuestData.QuestState.IN_PROGRESS:
			result.reason = "Already in progress"
			return result
		elif state == QuestData.QuestState.REWARDED:
			result.reason = "Already completed"
			return result

	# Check level requirements (the helper exists and drives the
	# availability roster already; the gate was left commented there).
	var player_level := _get_player_level(player_id)
	if player_level < quest.min_level:
		result.reason = "Level too low (need %d)" % quest.min_level
		return result

	# Check the authored quest chain. previous_quest_id and required_quests
	# are declared on QuestData and authored in data/quests/*.tres, but
	# nothing enforced them -- a player could accept a sequel before its
	# prerequisite, or pick up "The Old Roads" before "The Awakening".
	var missing: String = _first_unmet_prereq(player_data, quest)
	if not missing.is_empty():
		result.reason = "Requires quest: %s" % missing
		return result

	result.available = true
	return result

## First authored prerequisite the player has not turned in, or "" when
## every prerequisite is met. Both the accept gate and the roster read it
## so the offered list and the accepted set never disagree.
func _first_unmet_prereq(player_data: Dictionary, quest: QuestData) -> String:
	var prereqs: Array = []
	if not quest.previous_quest_id.is_empty():
		prereqs.append(quest.previous_quest_id)
	for req in quest.required_quests:
		if not prereqs.has(str(req)):
			prereqs.append(str(req))
	for prereq_id in prereqs:
		if prereq_id.is_empty():
			continue
		if not player_data.has(prereq_id):
			return prereq_id
		if int(player_data[prereq_id].get("state", QuestData.QuestState.LOCKED)) != QuestData.QuestState.REWARDED:
			return prereq_id
	return ""

func _load_quest_data(quest_id: String) -> QuestData:
	if DataService:
		return DataService.get_quest(quest_id)
	return null

## ============================================================================
## QUEST ACCEPTANCE
## ============================================================================

func accept_quest(player_id: String, quest_id: String) -> bool:
	# QoS: Rate limit quest accepts
	if QoSService and not QoSService.rate_limit(player_id, "quest_accept"):
		return false

	# Security: Validate quest_id format
	if not _is_valid_quest_id(quest_id):
		return false

	var availability := check_quest_availability(player_id, quest_id)
	if not availability.available:
		GameLog.warn("QuestService: Cannot accept quest - %s" % availability.reason)
		return false

	var quest := _load_quest_data(quest_id)
	if not quest:
		return false

	# Initialize quest state
	if not _player_quests.has(player_id):
		_player_quests[player_id] = {}

	var objectives := []
	for obj in quest.objectives:
		if not obj is Dictionary:
			continue
		objectives.append({
			"id": obj.get("id", str(objectives.size())),
			"type": int(obj.get("type", QuestData.ObjectiveType.KILL)),
			"target": str(obj.get("target", obj.get("target_id", ""))),
			"required": int(obj.get("count", 1)),
			"current": 0,
			"completed": false,
			# The optional flag is authored in the .tres but was dropped
			# here, so _are_all_objectives_complete demanded the optional
			# objectives too -- any quest with an optional objective could
			# never complete (quest_intro_core_npcs, the blacksmith's
			# onboarding quest, has two).
			"optional": bool(obj.get("optional", false))
		})

	_player_quests[player_id][quest_id] = {
		"state": QuestData.QuestState.IN_PROGRESS,
		"accepted_at": Time.get_unix_time_from_system(),
		"objectives": objectives,
		"data": quest
	}

	_persist_player_quests(player_id)
	quest_accepted.emit(player_id, quest_id)
	GameLog.info("QuestService: %s accepted quest %s" % [player_id, quest_id])
	return true

func abandon_quest(player_id: String, quest_id: String) -> bool:
	var player_data: Dictionary = _player_quests.get(player_id, {})
	if not player_data.has(quest_id):
		return false

	var state: int = player_data[quest_id].get("state", QuestData.QuestState.LOCKED)
	if state != QuestData.QuestState.IN_PROGRESS:
		return false

	# Remove quest
	player_data.erase(quest_id)
	_persist_player_quests(player_id)
	## The HUD quest tracker listens on quest_updated for its refresh;
	## abandoning left the line on screen forever. Announce the state
	## change so the tracker drops it in the same tick.
	quest_updated.emit(player_id, quest_id, "", 0)
	GameLog.info("QuestService: %s abandoned quest %s" % [player_id, quest_id])
	return true

## ============================================================================
## QUEST PROGRESS
## ============================================================================

func update_quest_progress(player_id: String, objective_type: int, target: String, amount: int = 1) -> void:
	var player_data: Dictionary = _player_quests.get(player_id, {})
	var updated := []

	for quest_id in player_data:
		var quest_state: Dictionary = player_data[quest_id]
		if quest_state.get("state") != QuestData.QuestState.IN_PROGRESS:
			continue

		var objectives: Array = quest_state.get("objectives", [])
		var changed := false

		for obj in objectives:
			if obj.get("completed", false):
				continue
			if obj.get("type") != objective_type:
				continue
			if obj.get("target") != target:
				continue

			# Update progress
			obj["current"] = mini(obj["current"] + amount, obj["required"])
			obj["completed"] = obj["current"] >= obj["required"]
			changed = true

			quest_updated.emit(player_id, quest_id, obj["id"], obj["current"])
			updated.append({"quest": quest_id, "objective": obj["id"]})

		# Check if all objectives complete
		if changed and _are_all_objectives_complete(objectives):
			quest_state["state"] = QuestData.QuestState.COMPLETE
			_persist_player_quests(player_id)
			quest_completed.emit(player_id, quest_id)

			# Frame-level dispatch. QUEST_COMPLETED -> NotifKind.QUEST
			# (autoload maps the kind to NotificationType.QUEST for the
			# legacy render path). Dedupe on (player, quest_id) so a
			# follow-up objective tick that re-evaluates to complete
			# does not double-toast.
			# NOTE: no 2-arg Resource.get here -- 4.7.2 removed the
			# default argument and a completion would SCRIPT ERROR.
			var qdata = quest_state.get("data")
			var qname: String = "Unknown"
			if qdata != null and "display_name" in qdata:
				qname = str(qdata.display_name)
			# auto_complete is authored in the .tres ("complete without
			# turn-in NPC") but was never read, so quests that set it still
			# demanded a visit to the giver. Pay them the moment they complete.
			var auto: bool = qdata != null and "auto_complete" in qdata and bool(qdata.auto_complete)
			if is_instance_valid(NotificationService):
				var msg: String = "Quest Complete: %s" % qname
				if not auto:
					msg += " - Return to quest giver!"
				NotificationService.notify(
					NotifKind.QUEST_COMPLETED,
					msg,
					"QuestService",
					"quest_complete:%s:%s" % [player_id, quest_id],
					{"quest_id": quest_id, "player_id": player_id},
					player_id
				)
			if auto:
				turn_in_quest(player_id, quest_id)

	if updated.is_empty():
		return

	GameLog.debug("QuestService: Updated %d quest(s) for %s" % [updated.size(), player_id])

func _are_all_objectives_complete(objectives: Array) -> bool:
	for obj in objectives:
		# Optional objectives never gate completion (QuestData.check_completion
		# applies the same rule); requiring them stranded every quest that
		# authors one.
		if obj.get("optional", false):
			continue
		if not obj.get("completed", false):
			return false
	return true

## ============================================================================
## QUEST COMPLETION
## ============================================================================

func turn_in_quest(player_id: String, quest_id: String) -> bool:
	var player_data: Dictionary = _player_quests.get(player_id, {})
	if not player_data.has(quest_id):
		return false

	var quest_state: Dictionary = player_data[quest_id]
	if quest_state.get("state") != QuestData.QuestState.COMPLETE:
		return false

	var quest: QuestData = quest_state.get("data")
	if not quest:
		return false

	# Apply rewards
	var rewards := _apply_rewards(player_id, quest)

	# Mark as rewarded
	quest_state["state"] = QuestData.QuestState.REWARDED
	quest_state["rewarded_at"] = Time.get_unix_time_from_system()

	_persist_player_quests(player_id)
	quest_rewarded.emit(player_id, quest_id, rewards)
	GameLog.info("QuestService: %s turned in quest %s" % [player_id, quest_id])
	return true

func _apply_rewards(player_id: String, quest: QuestData) -> Dictionary:
	# quest.rewards is Array[Reward] (one entry per reward line). We fold
	# the array into a summary dict the rest of the game can read without
	# depending on the Reward schema.
	var summary := {
		"experience": 0,
		"gold": 0,
		"items": [],
		"reputation": {},
		"titles": []
	}
	# Two authoring forms exist. The structured `rewards` array is the
	# detailed form (it can carry items with drop chances); the scalar
	# xp_reward/gold_reward/faction/title exports are the summary form.
	# The catalog authors BOTH for the same values, so paying both would
	# double every reward -- the array wins when present, the scalars are
	# the fallback. Reading only `rewards` (the old code) left every quest
	# paying nothing on turn-in.
	var has_xp := false
	var has_gold := false
	for reward in quest.rewards:
		if not reward is Dictionary:
			continue
		var rtype: String = str(reward.get("type", ""))
		match rtype:
			"experience", "xp":
				has_xp = true
				summary["experience"] += int(reward.get("quantity", 0))
			"gold":
				has_gold = true
				summary["gold"] += int(reward.get("quantity", 0))
			"item":
				summary["items"].append({
					"id": reward.get("id", ""),
					"quantity": int(reward.get("quantity", 1)),
				})
			"reputation", "faction":
				summary["reputation"][reward.get("id", "")] = int(reward.get("quantity", 0))
			"title":
				summary["titles"].append(reward.get("id", ""))
	if not has_xp:
		summary["experience"] += int(quest.xp_reward)
	if not has_gold:
		summary["gold"] += int(quest.gold_reward)
	if not quest.faction_reward.is_empty() and int(quest.faction_amount) != 0:
		summary["reputation"][quest.faction_reward] = int(quest.faction_amount)
	if not quest.title_reward.is_empty():
		summary["titles"].append(quest.title_reward)
	_grant_rewards(player_id, summary)
	return summary

## Pay the folded summary through the live services. Every grant is
## duck-typed and late-resolved so a script-mode receipt (no mounted
## wallet, autoloads not pre-loaded) still folds the summary without
## crashing; the reward signal fires either way.
func _grant_rewards(player_id: String, summary: Dictionary) -> void:
	if player_id.is_empty():
		return
	var xp: int = int(summary.get("experience", 0))
	var gold: int = int(summary.get("gold", 0))

	# XP and gold land on the local player node when it is the earner
	# (add_experience/add_gold own the level-up and one-purse lanes) and
	# mirror into PlayerManager -- the persistent stats surface the HUD
	# reads -- exactly like KillRewards does.
	var pm := _pmgr()
	var local_node = null
	if pm != null and pm.has_method("get_local_player"):
		local_node = pm.get_local_player()
	if local_node != null and _node_player_id(local_node) == player_id:
		if xp > 0 and local_node.has_method("add_experience"):
			local_node.call("add_experience", xp)
		if gold > 0 and local_node.has_method("add_gold"):
			local_node.call("add_gold", gold)
	if pm != null:
		if xp > 0 and pm.has_method("add_experience"):
			pm.add_experience(xp)
		if gold > 0 and pm.has_method("add_gold"):
			pm.add_gold(gold)

	# Items: resolve through DataService, grant through the ONE purse.
	var inv_svc := _inventory_service()
	if inv_svc != null and inv_svc.has_method("get_inventory"):
		var inv = inv_svc.get_inventory(player_id)
		if inv != null and inv.has_method("add_item"):
			for entry in summary.get("items", []):
				var item_id: String = str(entry.get("id", ""))
				if item_id.is_empty():
					continue
				var item = _resolve_item(item_id)
				if item != null:
					inv.add_item(item, int(entry.get("quantity", 1)))

	# Titles ride TitleService's own ledger.
	var titles: Array = summary.get("titles", [])
	if not titles.is_empty():
		var tsvc = _resolve_autoload("TitleService")
		if tsvc != null and tsvc.has_method("unlock"):
			for title_id in titles:
				tsvc.unlock(player_id, str(title_id))

## Player id of a node, tolerant of both Entity and PlayerController.
func _node_player_id(node) -> String:
	if node == null:
		return ""
	if "entity_id" in node and str(node.get("entity_id")) != "":
		return str(node.get("entity_id"))
	if "player_id" in node:
		return str(node.get("player_id"))
	return ""

func _resolve_item(item_id: String):
	var ds = _resolve_autoload("DataService")
	if ds != null and ds.has_method("get_item"):
		return ds.get_item(item_id)
	return null

func _inventory_service() -> Node:
	return _resolve_autoload("InventoryService")

func _pmgr() -> Node:
	return _resolve_autoload("PlayerManager")

## Late-resolve an autoload through the tree so script-mode receipts
## (which do not pre-load autoloads) work; bare-identifier fallback for
## full boot. Mirrors the convention in kill_rewards.gd.
func _resolve_autoload(svc_name: String) -> Node:
	var ml := Engine.get_main_loop()
	if ml != null and (ml is SceneTree):
		return (ml as SceneTree).root.get_node_or_null(svc_name)
	return null


func get_quest_progress(player_id: String, quest_id: String) -> Dictionary:
	var player_data: Dictionary = _player_quests.get(player_id, {})
	if not player_data.has(quest_id):
		return {}

	var quest_state: Dictionary = player_data[quest_id]
	return {
		"state": quest_state.get("state"),
		"objectives": quest_state.get("objectives", []),
		"data": quest_state.get("data")
	}

func get_quest_objectives_text(player_id: String, quest_id: String) -> Array:
	var progress := get_quest_progress(player_id, quest_id)
	if not progress.is_empty():
		return _format_objectives_text(progress.get("objectives", []))
	# Not accepted yet (the journal AVAILABLE tab): format the catalog
	# objectives so the player sees what the quest asks before accepting.
	var quest := _load_quest_data(quest_id)
	if quest == null:
		return []
	var raw := []
	for o in quest.objectives:
		if o is Dictionary:
			raw.append({
				"type": int(o.get("type", QuestData.ObjectiveType.KILL)),
				"target": str(o.get("target", "")),
				"current": 0,
				"required": int(o.get("count", 1)),
				"completed": false
			})
	return _format_objectives_text(raw)

func _format_objectives_text(objectives: Array) -> Array:
	var result := []

	for obj in objectives:
		var obj_type: int = obj.get("type", QuestData.ObjectiveType.KILL)
		var target: String = obj.get("target", "")
		var current: int = obj.get("current", 0)
		var required: int = obj.get("required", 1)
		var completed: bool = obj.get("completed", false)

		var text := ""
		match obj_type:
			QuestData.ObjectiveType.KILL:
				text = "Kill %s: %d/%d" % [_esc(target), current, required]
			QuestData.ObjectiveType.COLLECT:
				text = "Collect %s: %d/%d" % [_esc(target), current, required]
			QuestData.ObjectiveType.TALK:
				text = "Talk to %s" % _esc(target)
			QuestData.ObjectiveType.EXPLORE:
				text = "Explore %s" % _esc(target)
			QuestData.ObjectiveType.SWIM:
				text = "Swim %s: %d/%d" % [_esc(target), current, required]
			QuestData.ObjectiveType.RECORD_INSIGHT:
				text = "Watch the sky: %d/%d" % [current, required]
			_:
				text = "%s: %d/%d" % [_esc(target), current, required]

		if completed:
			text = "[color=%s]%s[/color]" % [UIStyles.COLORS.success.to_html(), text]
		else:
			text = "[color=%s]%s[/color]" % [UIStyles.COLORS.text_primary.to_html(), text]

		result.append(text)

	return result

## ============================================================================
## HELPERS
## ============================================================================

func _get_player_level(player_id: String) -> int:
	# Try to get player level from available services
	if InventoryService and InventoryService.has_method("get_player_level"):
		var level: int = InventoryService.get_player_level(player_id)
		if level > 0:
			return level
	# Fallback: check player stats via PlayerManager
	if PlayerManager and PlayerManager.has_method("get_player_info"):
		var info: Dictionary = PlayerManager.get_player_info(player_id)
		if info is Dictionary and info.has("level"):
			return int(info.get("level", 1))
	# Default to level 1
	return 1

func _is_valid_quest_id(quest_id: String) -> bool:
	# Security: Validate quest_id format to prevent injection
	if quest_id.is_empty() or quest_id.length() > 64:
		return false
	# Only alphanumeric, underscores, hyphens allowed
	var regex := RegEx.new()
	regex.compile("^[a-zA-Z0-9_-]+$")
	return regex.search(quest_id) != null

func _load_player_quests() -> void:
	var store := DictStore.new()
	_player_quests.clear()
	for key in store.all_keys():
		# Filter OUR prefix: the store is shared KV -- other services'
		# entries used to hit the cast below and crash _ready (the
		# SignService loader always filtered; this one forgot).
		if not str(key).begins_with(_kv_prefix):
			continue
		var player_id: String = str(key).replace(_kv_prefix, "")
		var raw = store.get_value(str(key))
		if not (raw is Dictionary):
			continue
		var data: Dictionary = raw
		if not data.is_empty():
			_player_quests[player_id] = data

func _persist_player_quests(player_id: String) -> void:
	var store := DictStore.new()
	var quests: Dictionary = _player_quests.get(player_id, {})
	if quests.is_empty():
		store.erase(_kv_prefix + player_id)
	else:
		store.set_value(_kv_prefix + player_id, quests)
