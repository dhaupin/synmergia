## CommunityGovernance - Player voting and community moderation
extends Node

enum VoteType {
	REPORT_VALIDATION = 0
	REPORT_SEVERITY = 1
	FEATURE_VOTE = 2
	COMMUNITY_POLL = 3
	ADMIN_APPEAL = 4
}

enum VoteStatus {
	OPEN = 0
	CLOSED = 1
	EXPIRED = 2
	CANCELED = 3
}


class ModeratorProgression:
	var player_id: String
	var level: int = 1
	var experience: int = 0
	var votes_participated: int = 0
	var votes_correct: int = 0
	var badges: Array = []
	var privileges: Array = []
	var last_activity: float = 0
	
	const MAX_LEVEL: int = 10
	const XP_PER_VOTE: int = 10
	const XP_PER_CORRECT: int = 25
	const XP_PER_LEVEL: int = 100
	
	func _init(p_player_id: String):
		player_id = p_player_id
		last_activity = Time.get_unix_time_from_system()
	
	func record_vote(correct: bool) -> void:
		votes_participated += 1
		last_activity = Time.get_unix_time_from_system()
		add_xp(XP_PER_VOTE)
		if correct:
			votes_correct += 1
			add_xp(XP_PER_CORRECT)
	
	func add_xp(amount: int) -> void:
		experience += amount
		while experience >= XP_PER_LEVEL and level < MAX_LEVEL:
			experience -= XP_PER_LEVEL
			level += 1
			_update_privileges()
			_update_badges()
	
	func _update_privileges() -> void:
		privileges.clear()
		if level >= 1: privileges.append("vote_basic")
		if level >= 3: privileges.append("vote_priority")
		if level >= 5: privileges.append("create_poll")
		if level >= 7: privileges.append("moderate_votes")
		if level >= 9: privileges.append("trusted_jury")
	
	func _update_badges() -> void:
		if level >= 2 and not badges.has("voting_initiate"): badges.append("voting_initiate")
		if level >= 5 and not badges.has("community_pillar"): badges.append("community_pillar")
		if level >= 8 and not badges.has("justice_keeper"): badges.append("justice_keeper")
		if level == 10 and not badges.has("elder_council"): badges.append("elder_council")
	
	func to_dict() -> Dictionary:
		return {
			"player_id": player_id,
			"level": level,
			"experience": experience,
			"xp_to_next": XP_PER_LEVEL - experience,
			"votes_participated": votes_participated,
			"votes_correct": votes_correct,
			"accuracy": float(votes_correct) / float(votes_participated) if votes_participated > 0 else 0.0,
			"badges": badges,
			"privileges": privileges
		}

class Vote:
	var id: String
	var type: VoteType
	var subject_id: String
	var question: String
	var description: String
	var options: Array
	var status: VoteStatus
	var created_by: String
	var created_at: float
	var expires_at: float
	var min_participation: int
	var vote_counts: Dictionary
	
	func _init(p_id: String, p_type: VoteType, p_subject: String, p_question: String, 
			p_description: String, p_options: Array, p_creator: String, p_duration_hours: int = 24):
		id = p_id
		type = p_type
		subject_id = p_subject
		question = p_question
		description = p_description
		options = p_options
		status = VoteStatus.OPEN
		created_by = p_creator
		created_at = Time.get_unix_time_from_system()
		expires_at = created_at + (p_duration_hours * 3600)
		min_participation = 5
		vote_counts = {}
	
	func has_voted(voter_id: String) -> bool:
		return vote_counts.has(voter_id)
	
	func cast_vote(voter_id: String, option_id) -> bool:
		if status != VoteStatus.OPEN:
			return false
		if Time.get_unix_time_from_system() > expires_at:
			status = VoteStatus.EXPIRED
			return false
		
		vote_counts[voter_id] = option_id
		return true
	
	func get_vote_count(option_id) -> int:
		var count: int = 0
		for voter_id in vote_counts.keys():
			if vote_counts[voter_id] == option_id:
				count += 1
		return count
	
	func get_total_votes() -> int:
		return vote_counts.size()
	
	func get_results() -> Array:
		var results: Array = []
		for option in options:
			results.append({
				"id": option.id,
				"text": option.text,
				"votes": get_vote_count(option.id),
				"percentage": 0.0
			})
		
		var total := get_total_votes()
		if total > 0:
			for result in results:
				result.percentage = (float(result.votes) / float(total)) * 100.0
		
		results.sort_custom(func(a, b): return a.votes > b.votes)
		return results
	
	func is_passed() -> bool:
		if get_total_votes() < min_participation:
			return false
		var results := get_results()
		if results.is_empty():
			return false
		var winner = results[0]
		var total := get_total_votes()
		return float(winner.votes) / float(total) > 0.5

var _votes: Dictionary = {}
var _player_vote_history: Dictionary = {}
var min_votes_for_result: int = 5
var default_vote_duration_hours: int = 24
var _report_vote_cooldowns: Dictionary = {}
var _current_voter: String = ""

func _ready() -> void:
	GameLog.info("CommunityGovernance: Initialized")

func create_vote(type: VoteType, subject_id: String, question: String, 
		description: String, options: Array, creator: String, duration_hours: int = 24) -> Dictionary:
	
	if creator.strip_edges() == "":
		return {"success": false, "message": "Invalid creator"}
	
	for vote_id in _votes.keys():
		var existing: Vote = _votes[vote_id]
		if existing.subject_id == subject_id and existing.status == VoteStatus.OPEN:
			return {"success": false, "message": "Vote already exists for this subject"}
	
	var vote_id := "vote_%s_%d" % [creator, Time.get_ticks_msec()]
	var vote := Vote.new(vote_id, type, subject_id, question, description, options, creator, duration_hours)
	
	_votes[vote_id] = vote
	
	if not _player_vote_history.has(creator):
		_player_vote_history[creator] = []
	_player_vote_history[creator].append(vote_id)
	
	GameLog.info("CommunityGovernance: Created vote %s" % vote_id)
	vote_created.emit(vote)
	
	return {"success": true, "vote_id": vote_id, "vote": vote}

func cast_vote(vote_id: String, voter_id: String, option_id) -> Dictionary:
	if voter_id.strip_edges() == "":
		return {"success": false, "message": "Invalid voter"}
	
	if not _check_vote_cooldown(voter_id):
		return {"success": false, "message": "Please wait before voting again"}
	
	if not _votes.has(vote_id):
		return {"success": false, "message": "Vote not found"}
	
	var vote: Vote = _votes[vote_id]
	
	if vote.has_voted(voter_id):
		return {"success": false, "message": "You have already voted"}
	
	if vote.status != VoteStatus.OPEN:
		return {"success": false, "message": "Voting is closed"}
	
	if not vote.cast_vote(voter_id, option_id):
		return {"success": false, "message": "Failed to cast vote"}
	
	_report_vote_cooldowns[voter_id] = Time.get_unix_time_from_system()
	vote_cast.emit(vote_id, voter_id, option_id)
	
	return {"success": true, "message": "Vote cast"}

func get_vote(vote_id: String) -> Dictionary:
	if not _votes.has(vote_id):
		return {}
	
	var vote: Vote = _votes[vote_id]
	
	return {
		"id": vote.id,
		"type": vote.type,
		"subject_id": vote.subject_id,
		"question": vote.question,
		"description": vote.description,
		"options": vote.options,
		"status": vote.status,
		"created_by": vote.created_by,
		"created_at": vote.created_at,
		"expires_at": vote.expires_at,
		"total_votes": vote.get_total_votes(),
		"results": vote.get_results(),
		"user_voted": vote.has_voted(_current_voter)
	}

func get_votes_by_type(type: VoteType, status_filter: VoteStatus = VoteStatus.OPEN) -> Array:
	var results: Array = []
	
	for vote_id in _votes.keys():
		var vote: Vote = _votes[vote_id]
		if vote.type == type and (status_filter < 0 or vote.status == status_filter):
			results.append({
				"id": vote.id,
				"question": vote.question,
				"total_votes": vote.get_total_votes(),
				"expires_at": vote.expires_at,
				"status": vote.status
			})
	
	return results

func get_open_votes() -> Array:
	return get_votes_by_type(VoteType.REPORT_VALIDATION, VoteStatus.OPEN) + \
	       get_votes_by_type(VoteType.FEATURE_VOTE, VoteStatus.OPEN) + \
	       get_votes_by_type(VoteType.COMMUNITY_POLL, VoteStatus.OPEN)

func close_vote(admin_id: String, vote_id: String) -> Dictionary:
	if PermissionManager:
		if not PermissionManager.has_permission(admin_id, PermissionManager.Level.MOD):
			return {"success": false, "message": "MOD level required"}
	
	if not _votes.has(vote_id):
		return {"success": false, "message": "Vote not found"}
	
	var vote: Vote = _votes[vote_id]
	vote.status = VoteStatus.CLOSED
	
	GameLog.info("CommunityGovernance: Vote %s closed" % vote_id)
	vote_closed.emit(vote)
	
	return {"success": true, "results": vote.get_results(), "passed": vote.is_passed()}

func create_report_validation_vote(reporter_id: String, report_id: String) -> Dictionary:
	var options: Array = [
		{"id": 1, "text": "Valid - deserves action"},
		{"id": 2, "text": "Invalid - dismiss"},
		{"id": 3, "text": "Insufficient info"}
	]
	
	return create_vote(
		VoteType.REPORT_VALIDATION,
		report_id,
		"Should this report result in action?",
		"Community vote on report validity.",
		options,
		reporter_id,
		12
	)

func create_feature_vote(creator_id: String, feature_id: String, 
		feature_name: String, description: String) -> Dictionary:
	
	var options: Array = [
		{"id": 1, "text": "Strong Yes"},
		{"id": 2, "text": "Yes"},
		{"id": 3, "text": "Neutral"},
		{"id": 4, "text": "No"},
		{"id": 5, "text": "Strong No"}
	]
	
	return create_vote(
		VoteType.FEATURE_VOTE,
		feature_id,
		"Should we implement: %s?" % feature_name,
		description,
		options,
		creator_id,
		72
	)

func get_moderation_queue() -> Array:
	var queue: Array = []
	var report_votes := get_votes_by_type(VoteType.REPORT_VALIDATION, VoteStatus.OPEN)
	
	for vote_data in report_votes:
		var vote: Vote = _votes[vote_data.id]
		queue.append({
			"vote_id": vote.id,
			"subject_id": vote.subject_id,
			"question": vote.question,
			"total_votes": vote.get_total_votes(),
			"min_participation": vote.min_participation,
			"time_remaining": max(0, int(vote.expires_at - Time.get_unix_time_from_system()))
		})
	
	return queue

func get_player_mod_stats(player_id: String) -> Dictionary:
	var total_votes_cast := 0
	
	for vote_id in _votes.keys():
		var vote: Vote = _votes[vote_id]
		if vote.vote_counts.has(player_id):
			total_votes_cast += 1
	
	return {
		"total_votes_cast": total_votes_cast,
		"reputation_score": _calculate_reputation_score(player_id)
	}

func _check_vote_cooldown(player_id: String) -> bool:
	if _report_vote_cooldowns.has(player_id):
		var last_vote := _report_vote_cooldowns[player_id]
		var elapsed: float = Time.get_unix_time_from_system() - last_vote
		return elapsed > 60
	return true

func _calculate_reputation_score(player_id: String) -> int:
	var score := 0
	
	if _player_vote_history.has(player_id):
		score += _player_vote_history[player_id].size() * 2
	
	for vote_id in _votes.keys():
		var vote: Vote = _votes[vote_id]
		if vote.vote_counts.has(player_id):
			score += 1
	
	return score

func _process(delta: float) -> void:
	var now := Time.get_unix_time_from_system()
	
	for vote_id in _votes.keys():
		var vote: Vote = _votes[vote_id]
		
		if vote.status == VoteStatus.OPEN and now > vote.expires_at:
			vote.status = VoteStatus.EXPIRED
			vote_expired.emit(vote)

signal vote_created(vote: Vote)
signal vote_cast(vote_id: String, voter_id: String, option_id)
signal vote_closed(vote: Vote)
signal vote_expired(vote: Vote)
signal level_up(player_id: String, new_level: int)
signal badge_earned(player_id: String, badge: String)

## MODERATOR PROGRESSION API

func get_progression(player_id: String) -> Dictionary:
	if not _moderator_progression.has(player_id):
		_moderator_progression[player_id] = ModeratorProgression.new(player_id)
	return _moderator_progression[player_id].to_dict()

func record_participation(player_id: String, vote_outcome: bool) -> void:
	if not _moderator_progression.has(player_id):
		_moderator_progression[player_id] = ModeratorProgression.new(player_id)
	var prog: ModeratorProgression = _moderator_progression[player_id]
	var old_level := prog.level
	prog.record_vote(vote_outcome)
	if prog.level > old_level:
		level_up.emit(player_id, prog.level)

func has_privilege(player_id: String, privilege: String) -> bool:
	if not _moderator_progression.has(player_id):
		return false
	return _moderator_progression[player_id].privileges.has(privilege)

func get_leaderboard(limit: int = 10) -> Array:
	var now := Time.get_unix_time_from_system()
	if now - _leaderboard_cache_time < LEADERBOARD_CACHE_DURATION and not _leaderboard_cache.is_empty():
		return _leaderboard_cache.slice(0, limit)
	var entries: Array = []
	for pid in _moderator_progression.keys():
		var prog: ModeratorProgression = _moderator_progression[pid]
		entries.append({
			"player_id": pid,
			"level": prog.level,
			"experience": prog.experience,
			"votes_participated": prog.votes_participated,
			"accuracy": float(prog.votes_correct) / float(prog.votes_participated) if prog.votes_participated > 0 else 0.0,
			"badges": prog.badges
		})
	entries.sort_custom(func(a, b): 
		if a.level != b.level: return a.level > b.level
		return a.experience > b.experience
	)
	_leaderboard_cache = entries
	_leaderboard_cache_time = now
	return entries.slice(0, limit)

func get_privilege_requirements() -> Dictionary:
	return {
		"vote_basic": {"level": 1, "description": "Participate in community votes"},
		"vote_priority": {"level": 3, "description": "Priority voting on controversial items"},
		"create_poll": {"level": 5, "description": "Create community polls"},
		"moderate_votes": {"level": 7, "description": "Close/manage community votes"},
		"trusted_jury": {"level": 9, "description": "Final say on report validation"}
	}
