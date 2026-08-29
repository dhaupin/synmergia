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
		var count := 0
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
	GameLogger.info("CommunityGovernance: Initialized")

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
	
	GameLogger.info("CommunityGovernance: Created vote %s" % vote_id)
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
	
	GameLogger.info("CommunityGovernance: Vote %s closed" % vote_id)
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
		var elapsed := Time.get_unix_time_from_system() - last_vote
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
