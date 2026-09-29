## BoutHostService - the S12 keystone: the RUNTIME that hosts a bout.
##
## Everything before this service is verified parts (lobby, rooms,
## bridge, teleports) with no production assembly. This service IS the
## assembly: on LobbyService.bout_assembled it spawns the arena room,
## seats every participant as a LINKED fighter (owner clarifier:
## players use their own class/gear/build -- no duel-set loaner forms;
## the seat binds the live entity by entity_id), arms the start timer
## against the zone's entry deadline, and on bout_ended pays out and
## tears the room down.
##
## The loop after tonight: stone -> queue -> assemble -> HOSTED ROOM
## -> fight -> payout -> home.
##
## Trial bout (the retention keystone): on LobbyService's
## trial_fallback_due, the host fabricates the marshal's dummies and
## hosts a winnable 1 v N lesson. Reduced payout; QuestService
## (KILL "marshal's dummies") and AchievementService (bout_win)
## credit on the win. Empty-queue hour: queue-of-one still means a
## fight, and the first stone touch ends in one.
##
## Payout (first pass, honest bookkeeping): winners take XP + gold,
## losers take consolation XP, via PlayerManager's duck-typed
## progression surface. Depth (per-kill credit, titles, wagers) is
## parked in labs/prd-bout-host.md.
##
## Host book shape: instance_id -> {zone_id, room, participants,
## started}. The bout_ended connection binds the instance_id (signal
## arity stays 2; the book key rides the bind).
extends Node

const ArenaScene = preload("res://scenes/instances/arena_instance.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind
const Contract = preload("res://core/schemas/instance_contract.gd")

## Payout: base XP for the winning team (per member), consolation for
## losers, plus gold to winners. Zone-scaled base lands later.
const WIN_XP: int = 120
const WIN_GOLD: int = 25
const CONSOLATION_XP: int = 40
const TRIAL_WIN_XP: int = 40
const TRIAL_WIN_GOLD: int = 10
const TRIAL_LOSS_XP: int = 15
## Dummy display name (QuestService KILL objectives target display
## names -- the lint's credit rule, same as "Wolf" for wolves).
const TRIAL_DUMMY_NAME: String = "marshal's dummies"
const TRIAL_DUMMY_COUNT: int = 2

## ---- ROYALE payout shape (owner answers, 2026-09-29) --------------------
## Placement economy: the Last Light pays, survival pays, kills pay,
## and dying to the fog still pays the lesson. Anti-fog-squat credit
## (last standing team takes fog kills) is the room's job; this is
## the ledger.
const ROYALE_WIN_XP: int = 250
const ROYALE_WIN_GOLD: int = 60
const ROYALE_SURVIVAL_XP_PER_MIN: int = 12
const ROYALE_KILL_XP: int = 25
const ROYALE_CONSOLATION_XP: int = 30
## First Last Light: the title (title_last_light) + the achievement
## (royale_first_win) carry the marker; the flat bonus makes the
## FIRST win pay like a small heist.
const ROYALE_FIRST_WIN_XP: int = 400

# instance_id -> {zone_id, room, participants: Array, started: bool}
var _hosted: Dictionary = {}
# Trial id uniquifier (two trials can be born in the same second).
var _trial_seq: int = 0


func _ready() -> void:
	if LobbyService != null and LobbyService.has_signal("bout_assembled"):
		LobbyService.bout_assembled.connect(_on_bout_assembled)
		GameLog.info("BoutHostService: armed on bout_assembled")
	if LobbyService != null and LobbyService.has_signal("trial_fallback_due"):
		LobbyService.trial_fallback_due.connect(_on_trial_fallback_due)
		GameLog.info("BoutHostService: armed on trial_fallback_due (the marshal watches)")


## The marshal's trial bout: fabricate the dummy block, host a real
## room around it. Dummies are entity-free (bridge bypasses them);
## the queued player gets a winnable fight that teaches the mode.
func _on_trial_fallback_due(zone_id: String, block: Dictionary) -> void:
	var pids: Array = block.get("player_ids", [])
	if pids.is_empty():
		return
	var zone = _zone(zone_id)
	if zone == null:
		GameLog.warn("BoutHostService: trial for unknown zone %s dropped" % zone_id)
		return
	_trial_seq += 1
	var instance_id: String = "trial_%s_%d_%d" % [zone_id, int(Time.get_unix_time_from_system()), _trial_seq]
	var room = ArenaScene.new()
	room.zone_data = zone
	room.instance_id = instance_id
	room._trial = true
	get_tree().root.add_child(room)

	var participants: Array = []
	# The queuer keeps their real identity, level book, and stone --
	# the aged block CARRIES the origin stone they queued at.
	var solo_stones: Dictionary = {}
	var queued_stone = block.get("origin_stone", Vector3.ZERO)
	for i in range(pids.size()):
		if queued_stone != Vector3.ZERO:
			room.origin_stones[str(pids[i])] = queued_stone
		_seat(room, str(pids[i]), 0, zone, participants)
		solo_stones[str(pids[i])] = room.origin_stones.get(str(pids[i]), Vector3.ZERO)
	# The marshal's dummies: entity-free, trial-tuned, team 1.
	for d in range(TRIAL_DUMMY_COUNT):
		room.spawn_dummy_fighter("trial_dummy_%d" % d, 1)

	_hosted[instance_id] = {
		"zone_id": zone_id,
		"room": room,
		"participants": participants,
		"started": false,
		"trial": true,
	}
	if room.has_signal("bout_ended"):
		room.bout_ended.connect(_on_bout_ended.bind(instance_id))

	# Trial bouts start fast -- the lesson should not make anyone wait
	# out a lobby deadline.
	room.start_deadline_override = 4.0
	var timer := get_tree().create_timer(4.0)
	timer.timeout.connect(func(): _start_if_live(instance_id))

	# Inbound teleport: the queuer is already standing at the stone;
	# stage them into the trial via the standard assembly path.
	LobbyService.bout_assembled.emit(zone_id, instance_id, participants, [], solo_stones)
	for pid in participants:
		_toast(str(pid), "The marshal nods. A trial bout begins -- show them what you carry.", "trial_start:%s:%s" % [str(pid), instance_id])


## Host a bout: room + linked seats + start timer.
func _on_bout_assembled(zone_id: String, instance_id: String, team_a: Array, team_b: Array, stones: Dictionary = {}) -> void:
	if _hosted.has(instance_id):
		return
	var zone = _zone(zone_id)
	if zone == null:
		GameLog.warn("BoutHostService: unknown zone %s; assembly dropped" % zone_id)
		return
	var room = ArenaScene.new()
	room.zone_data = zone
	room.instance_id = instance_id
	# Room registers itself with ArenaRoomService on tree entry.
	get_tree().root.add_child(room)
	# Origin stones ride the assembly signal (the round-trip
	# addresses); the seat path below only fills absences, so players
	# who queued through LobbyUI (no stone) fall back to bind point.
	for fid in stones:
		room.origin_stones[str(fid)] = stones[fid]

	var participants: Array = []
	for i in range(team_a.size()):
		_seat(room, str(team_a[i]), 0, zone, participants)
	for i in range(team_b.size()):
		_seat(room, str(team_b[i]), 1, zone, participants)

	_hosted[instance_id] = {
		"zone_id": zone_id,
		"room": room,
		"participants": participants,
		"started": false,
	}
	if room.has_signal("bout_ended"):
		room.bout_ended.connect(_on_bout_ended.bind(instance_id))

	# Start after the zone's entry deadline (contract default 20 s).
	# Probe/tool seam: the room may cap the deadline (script-mode
	# tests cannot wait the real 60-90 s).
	var deadline: float = 2.0
	if zone != null and "instance_entry_deadline" in zone:
		deadline = maxf(float(zone.instance_entry_deadline), 2.0)
	if "start_deadline_override" in room and float(room.start_deadline_override) >= 0.0:
		deadline = minf(deadline, float(room.start_deadline_override))
	var timer := get_tree().create_timer(deadline)
	timer.timeout.connect(func(): _start_if_live(instance_id))


## Seat one linked fighter. Owner clarifier: the seat IS the player --
## no loaner loadout. Missing nodes still get seats (headless flow:
## the book exists; the scene swap owns bodies later).
func _seat(room, pid: String, team: int, zone, participants: Array) -> void:
	if room.has_fighter(pid):
		return
	room.spawn_fighter(pid, team)
	var level: int = 1
	var entity = _entity(pid)
	if entity != null and "level" in entity:
		level = int(entity.level)
	room.set_fighter_level(pid, level)
	var stone: Vector3 = room.origin_stones.get(pid, Vector3.ZERO)
	if stone == Vector3.ZERO:
		stone = _stone_for(pid, zone)
		room.origin_stones[pid] = stone
	participants.append(pid)


## Origin stone fallback: the zone's bind point (players who arrived
## through the LobbyUI queue rather than a stone still go home).
func _stone_for(pid: String, zone) -> Vector3:
	if zone != null and "bind_point" in zone:
		return zone.bind_point
	return Vector3.ZERO


func _start_if_live(instance_id: String) -> void:
	var book: Dictionary = _hosted.get(instance_id, {})
	if book.is_empty():
		return
	var room = book.get("room")
	if room == null or room.is_over() or room.is_started():
		return
	room.start_bout()
	book["started"] = true
	_announce_start(book, instance_id)


func _announce_start(book: Dictionary, instance_id: String) -> void:
	for pid in book.get("participants", []):
		_toast(str(pid), "The bout begins. Last team standing.", "bout_start:%s:%s" % [str(pid), instance_id])


## Bout closed: payout, release, teardown. instance_id arrives via
## the connect-time bind (signal args first, bound args after).
## winner_team -1 = DRAW (the clock ran out -- owner point 1: squatting
## pays nobody; everyone takes consolation XP so the queue is the loop).
func _on_bout_ended(winner_team: int, stats: Dictionary, instance_id: String) -> void:
	var book: Dictionary = _hosted.get(instance_id, {})
	if book.is_empty():
		return
	_hosted.erase(instance_id)
	var mode: int = _book_mode(book)
	if mode == Contract.InstanceMode.ROYALE:
		_pay_royale(winner_team, stats, book)
		_credit_streak_achievements(book)
	elif winner_team >= 0:
		_pay_out(winner_team, book)
		_credit_streak_achievements(book)
	else:
		_pay_draw(book)
	_record_recent(winner_team, book, instance_id)
	var room = book.get("room")
	if room != null:
		room.queue_free()
	GameLog.info("BoutHostService: bout %s closed (winner team %d)" % [instance_id, winner_team])


## The bout's mode from the room's own rules (draws never misroute).
func _book_mode(book: Dictionary) -> int:
	var room = book.get("room")
	if room != null and room.bout_rules() != null:
		return int(room.bout_rules().get("mode", -1))
	return -1


## ---- ROYALE ledger -------------------------------------------------------

## Placement payout (owner answers): Last Light takes the crown purse
## + survival XP + kill credit + the first-win marker; everyone else
## takes survival XP + kill credit + consolation. Kills come from the
## room's streak book (each booked death credits one killer). The fog
## itself never pays a kill; the last standing team took the credit
## in-world already.
func _pay_royale(winner_team: int, stats: Dictionary, book: Dictionary) -> void:
	var room = book.get("room")
	if room == null:
		return
	var ach = _achievement_service()
	var elapsed: float = float(stats.get("elapsed_seconds", 0.0))
	for pid in book.get("participants", []):
		var sid: String = str(pid)
		var f = room._fighters.get(sid)
		if f == null:
			continue
		var kills: int = int(room.kill_counts.get(sid, 0))
		var survival_xp: int = int(elapsed / 60.0) * ROYALE_SURVIVAL_XP_PER_MIN
		if ach != null:
			ach.track(sid, "royale_survival", 1)
			if kills >= 5:
				ach.track(sid, "royale_kill", kills)
		if int(f.team) == winner_team:
			var first: bool = _grant_last_light(sid, ach)
			var xp: int = ROYALE_WIN_XP + survival_xp + kills * ROYALE_KILL_XP \
				+ (ROYALE_FIRST_WIN_XP if first else 0)
			_grant(sid, xp, ROYALE_WIN_GOLD)
			var crown: String = " LAST LIGHT. The valley remembers." if first \
				else " Last Light. The valley empties."
			_toast(sid, "You are the%s (+%d XP, +%d gold)" % [crown, xp, ROYALE_WIN_GOLD], "royale_win:%s" % sid)
		else:
			var xp2: int = ROYALE_CONSOLATION_XP + survival_xp + kills * ROYALE_KILL_XP
			_grant(sid, xp2, 0)
			_toast(sid, "The fog takes you. You survived %.0f s. (+%d XP)" % [elapsed, xp2], "royale_out:%s" % sid)


## First Last Light ever: tracks the royale_win category (the
## royale_first_win achievement unlocks at 1 and carries
## title_reward = title_last_light) and reports whether this call
## was the player's first.
func _grant_last_light(player_id: String, ach) -> bool:
	if ach == null:
		return false
	var first := true
	if ach.has_method("get_unlocked_achievements"):
		first = not ("royale_first_win" in ach.get_unlocked_achievements(player_id))
	ach.track(player_id, "royale_win", 1)
	return first


## Consolation for everyone on a draw -- never zero, never a win.
func _pay_draw(book: Dictionary) -> void:
	var room = book.get("room")
	if room == null:
		return
	for pid in book.get("participants", []):
		var sid: String = str(pid)
		if room._fighters.has(sid):
			_grant(sid, CONSOLATION_XP, 0)
			_toast(sid, "The clock ran out. A draw -- the marshal pays the lesson. (+%d XP)" % CONSOLATION_XP, "bout_draw:%s" % sid)


## The rival book (owner point 4): every REAL bout (no trial, at
## least two participants) records a recent-players entry per fighter
## -- who else fought, where, the result. One-click Rematch reads
## this book. Privacy: is_recent_hidden fighters are not written
## into OTHERS' books; they still keep their own record.
func _record_recent(winner_team: int, book: Dictionary, _instance_id: String) -> void:
	var svc = _recent_service()
	if svc == null:
		return
	if bool(book.get("trial", false)):
		return
	var participants: Array = book.get("participants", [])
	if participants.size() < 2:
		return
	var room = book.get("room")
	if room == null:
		return
	var teams: Dictionary = {}
	for pid in participants:
		var f = room._fighters.get(str(pid))
		teams[str(pid)] = int(f.team) if f != null else -1
	for pid in participants:
		var sid: String = str(pid)
		if svc.is_recent_hidden(sid):
			continue
		svc.record_bout(participants, str(book.get("zone_id", "")), \
			int(room._rules.get("mode", 0)), winner_team, teams)


## Killstreak achievements (owner point 2): the templated kill_streak
## defs (3/5/10/25/50) get their missing tracker. One increment per
## fighter per bout at their BEST streak; the service caps progress
## at each def's target and _do_unlock guards repeats.
func _credit_streak_achievements(book: Dictionary) -> void:
	var room = book.get("room")
	if room == null:
		return
	var ach = _achievement_service()
	if ach == null:
		return
	for pid in book.get("participants", []):
		var sid: String = str(pid)
		var best: int = room.best_streak_for(sid)
		if best > 0:
			ach.track(sid, "kill_streak", best)


## Payout via the duck-typed progression surface. Never throws on
## missing ledgers (headless/probe flow has no PlayerManager book).
func _pay_out(winner_team: int, book: Dictionary) -> void:
	var room = book.get("room")
	if room == null:
		return
	var trial: bool = bool(book.get("trial", false))
	for pid in book.get("participants", []):
		var sid: String = str(pid)
		var f = room._fighters.get(sid)
		if f == null:
			continue
		if int(f.team) == winner_team:
			if trial:
				_grant(sid, TRIAL_WIN_XP, TRIAL_WIN_GOLD)
				_toast(sid, "The marshal is satisfied. (+%d XP, +%d gold)" % [TRIAL_WIN_XP, TRIAL_WIN_GOLD], "trial_win:%s" % sid)
				_credit_trial_win(sid)
			else:
				_grant(sid, WIN_XP, WIN_GOLD)
				_toast(sid, "Victory. The marshal's purse opens. (+%d XP, +%d gold)" % [WIN_XP, WIN_GOLD], "bout_win:%s" % sid)
		else:
			var xp: int = TRIAL_LOSS_XP if trial else CONSOLATION_XP
			_grant(sid, xp, 0)
			_toast(sid, "The bout is lost. The lesson is paid. (+%d XP)" % xp, "bout_lose:%s" % sid)


## Quest + achievement credit on a trial win. QuestService KILL
## objectives target the dummy display name; AchievementService
## tracks the bout_win category (data/achievements trial_by_fire).
func _credit_trial_win(player_id: String) -> void:
	var qs = _quest_service()
	if qs != null and qs.has_method("update_quest_progress"):
		qs.update_quest_progress(player_id, 0, TRIAL_DUMMY_NAME, 1)
	var ach = _achievement_service()
	if ach != null:
		ach.track(player_id, "bout_win", 1)


func _grant(pid: String, xp: int, gold: int) -> void:
	var pm = _player_manager()
	if pm == null:
		return
	if pm.has_method("add_experience"):
		pm.add_experience(xp)
	if gold > 0 and pm.has_method("add_gold"):
		pm.add_gold(gold)


# ---- Inspection surface (probe) ------------------------------------------

func hosted_bout_ids() -> Array:
	return _hosted.keys()


func is_hosting(instance_id: String) -> bool:
	return _hosted.has(instance_id)


# ---- Resolvers ------------------------------------------------------------

func _zone(zone_id: String):
	if ZoneManager == null:
		return null
	return ZoneManager.get_zone(zone_id)


func _entity(pid: String):
	if EntityService == null:
		return null
	return EntityService.get_entity(pid)


func _player_manager():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("PlayerManager")


func _toast(player_id: String, message: String, dedupe_key: String) -> void:
	var notif = _notification_service()
	if notif == null:
		return
	notif.notify(
		NotifKind.ZONE_CHANGED,
		message,
		"BoutHostService",
		dedupe_key,
		{},
		player_id)


func _notification_service():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("NotificationService")


func _quest_service():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("QuestService")


func _achievement_service():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("AchievementService")


func _recent_service():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("RecentPlayersService")
