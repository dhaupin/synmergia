## PlayerReporter - Unified player reporting system
## Handles bug reports, abuse reports, feedback, and suggestions
## All player reports flow through this central system
extends Node

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

static func _esc(text: String) -> String:
	return text.replace('[', '［').replace(']', '］')

## Report types
enum ReportType {
	ABUSE = 0,       # Player abuse/harassment
	BUG = 1,          # Game bug or glitch
	FEEDBACK = 2,     # General feedback
	SUGGESTION = 3,   # Feature suggestion
	EXPLOIT = 4,      # Suspected exploit/hack
	OTHER = 5         # Other issue
}

## Report priority
enum Priority {
	LOW = 0,
	NORMAL = 1,
	HIGH = 2,
	URGENT = 3
}

## Report status
enum Status {
	PENDING = 0,      # Awaiting review
	REVIEWING = 1,   # Being reviewed
	RESOLVED = 2,    # Issue addressed
	DISMISSED = 3,   # Report not valid
	ESCALATED = 4    # Escalated to higher authority
}

## Report entry
class Report:
	var id: String
	var type: ReportType
	var reporter_id: String
	var target_id: String  # Optional - player being reported
	var subject: String
	var description: String
	var priority: Priority
	var status: Status
	var created_at: float
	var updated_at: float
	var assigned_to: String  # Admin handling the report
	var resolution_notes: String
	var metadata: Dictionary  # Additional context
	
	func _init(p_reporter: String, p_type: ReportType, p_subject: String, p_desc: String, 
			p_target: String = "", p_meta: Dictionary = {}):
		id = "report_%s_%d" % [p_reporter, Time.get_ticks_msec()]
		type = p_type
		reporter_id = p_reporter
		target_id = p_target
		subject = p_subject
		description = p_desc
		priority = _calculate_priority()
		status = Status.PENDING
		created_at = Time.get_unix_time_from_system()
		updated_at = created_at
		metadata = p_meta
	
	func _calculate_priority() -> Priority:
		match type:
			ReportType.ABUSE:
				return Priority.HIGH
			ReportType.EXPLOIT:
				return Priority.URGENT
			ReportType.BUG:
				return Priority.NORMAL
			_:
				return Priority.LOW
	
	func to_dict() -> Dictionary:
		return {
			"id": id,
			"type": type,
			"reporter_id": reporter_id,
			"target_id": target_id,
			"subject": subject,
			"description": description,
			"priority": priority,
			"status": status,
			"created_at": created_at,
			"updated_at": updated_at,
			"assigned_to": assigned_to,
			"resolution_notes": resolution_notes,
			"metadata": metadata
		}
	
	func format_report() -> String:
		var type_str: String = _type_to_string()
		var status_str := _status_to_string()
		var priority_str := _priority_to_string()
		var time_str := Time.get_datetime_string_from_unix_time(created_at)
		
		var output := "[color=yellow]=== %s ===[/color]\n" % _esc(id)
		output += "[color=cyan]Type:[/color] %s | [color=cyan]Priority:[/color] %s | [color=cyan]Status:[/color] %s\n" % [_esc(type_str), _esc(priority_str), _esc(status_str)]
		output += "[color=cyan]Reporter:[/color] %s\n" % _esc(reporter_id)
		if target_id != "":
			output += "[color=cyan]Target:[/color] %s\n" % _esc(target_id)
		output += "[color=cyan]Subject:[/color] %s\n" % _esc(subject)
		output += "[color=cyan]Description:[/color] %s\n" % _esc(description)
		output += "[color=gray]Submitted:[/color] %s\n" % time_str
		
		if assigned_to != "":
			output += "[color=cyan]Assigned to:[/color] %s\n" % _esc(assigned_to)
		if resolution_notes != "":
			output += "[color=cyan]Resolution:[/color] %s\n" % _esc(resolution_notes)
		
		return output
	
	func _type_to_string() -> String:
		match type:
			ReportType.ABUSE: return "ABUSE"
			ReportType.BUG: return "BUG"
			ReportType.FEEDBACK: return "FEEDBACK"
			ReportType.SUGGESTION: return "SUGGESTION"
			ReportType.EXPLOIT: return "EXPLOIT"
			_: return "OTHER"
	
	func _status_to_string() -> String:
		match status:
			Status.PENDING: return "Pending"
			Status.REVIEWING: return "Reviewing"
			Status.RESOLVED: return "Resolved"
			Status.DISMISSED: return "Dismissed"
			Status.ESCALATED: return "Escalated"
			_: return "Unknown"
	
	func _priority_to_string() -> String:
		match priority:
			Priority.LOW: return "[color=gray]Low[/color]"
			Priority.NORMAL: return "[color=green]Normal[/color]"
			Priority.HIGH: return "[color=yellow]High[/color]"
			Priority.URGENT: return "[color=red]URGENT[/color]"
			_: return "?"

## All reports
var _reports: Dictionary = {}  # report_id -> Report

## Reports by reporter
var _reporter_reports: Dictionary = {}  # reporter_id -> Array of report IDs

## Reports by target
var _target_reports: Dictionary = {}  # target_id -> Array of report IDs

## Cooldown tracking: reporter_id -> last_report_time
var _report_cooldowns: Dictionary = {}
const REPORT_COOLDOWN_SECONDS: int = 60  # 1 minute between reports

## Rate limiting per reporter
const MAX_REPORTS_PER_HOUR: int = 10
var _hourly_reports: Dictionary = {}  # reporter_id -> {count, window_start}

func _ready() -> void:
	GameLog.info("PlayerReporter: Initialized")

## ============================================================================
## PUBLIC API
## ============================================================================

## Submit a new report
func submit_report(reporter_id: String, report_type: ReportType, data: Dictionary) -> Dictionary:
	# Validate reporter
	if reporter_id.strip_edges() == "":
		return {"success": false, "message": "Invalid reporter ID"}
	
	# Check cooldown
	var cooldown_check := _check_cooldown(reporter_id)
	if not cooldown_check.success:
		return cooldown_check
	
	# Check rate limit
	var rate_check := _check_rate_limit(reporter_id)
	if not rate_check.success:
		return rate_check
	
	# Parse data based on type
	var subject := ""
	var description := ""
	var target_id := ""
	var metadata := {}
	
	match report_type:
		ReportType.ABUSE:
			target_id = data.get("target", "")
			var reason: String = data.get("reason", "")
			subject = "Abuse Report: %s" % target_id
			description = reason
			metadata = {
				"evidence": data.get("evidence", []),
				"witnesses": data.get("witnesses", []),
				"chat_logs": data.get("chat_logs", "")
			}
		
		ReportType.BUG:
			subject = "Bug Report"
			description = data.get("description", "")
			metadata = {
				"steps_to_reproduce": data.get("steps", ""),
				"expected_behavior": data.get("expected", ""),
				"actual_behavior": data.get("actual", ""),
				"game_version": data.get("version", ""),
				"os": data.get("os", "")
			}
		
		ReportType.FEEDBACK:
			subject = "Feedback"
			description = data.get("message", "")
		
		ReportType.SUGGESTION:
			subject = "Suggestion"
			description = data.get("suggestion", "")
			metadata = {
				"category": data.get("category", "general")
			}
		
		ReportType.EXPLOIT:
			subject = "Exploit Report"
			description = data.get("description", "")
			target_id = data.get("player", "")
			metadata = {
				"exploit_type": data.get("exploit_type", ""),
				"severity": data.get("severity", "unknown")
			}
		
		ReportType.OTHER:
			subject = data.get("subject", "Other Report")
			description = data.get("description", "")
	
	# Validate required fields
	if description == "":
		return {"success": false, "message": "Description is required"}
	
	# Create report
	var report := Report.new(reporter_id, report_type, subject, description, target_id, metadata)
	_reports[report.id] = report
	
	# Index by reporter
	if not _reporter_reports.has(reporter_id):
		_reporter_reports[reporter_id] = []
	_reporter_reports[reporter_id].append(report.id)
	
	# Index by target
	if target_id != "":
		if not _target_reports.has(target_id):
			_target_reports[target_id] = []
		_target_reports[target_id].append(report.id)
	
	# Update cooldown
	_report_cooldowns[reporter_id] = Time.get_unix_time_from_system()
	
	# Update rate limit
	_update_rate_limit(reporter_id)
	
	# Log the report
	_log_report(report)
	
	# Emit signal
	report_submitted.emit(report)
	
	# Auto-escalate urgent reports
	if report.priority == Priority.URGENT:
		report.status = Status.ESCALATED
		report.assigned_to = "SYSTEM"
		_emit_urgent_alert(report)
	
	return {"success": true, "report_id": report.id, "message": "Report submitted successfully"}

## Get reports for a reporter
func get_reporter_reports(reporter_id: String) -> Array:
	var reports: Array = []
	if _reporter_reports.has(reporter_id):
		for report_id in _reporter_reports[reporter_id]:
			if _reports.has(report_id):
				reports.append(_reports[report_id])
	return reports

## Get reports against a player
func get_target_reports(target_id: String) -> Array:
	var reports: Array = []
	if _target_reports.has(target_id):
		for report_id in _target_reports[target_id]:
			if _reports.has(report_id):
				reports.append(_reports[report_id])
	return reports

## Get all pending reports (for admins)
func get_pending_reports(limit: int = 50) -> Array:
	var pending: Array = []
	
	for report_id in _reports.keys():
		var report: Report = _reports[report_id]
		if report.status == Status.PENDING or report.status == Status.ESCALATED:
			pending.append(report)
	
	# Sort by priority (urgent first), then by time
	pending.sort_custom(func(a, b): 
		if a.priority != b.priority:
			return a.priority > b.priority
		return a.created_at < b.created_at
	)
	
	return pending.slice(0, limit)

## Get report by ID
func get_report(report_id: String) -> Report:
	return _reports.get(report_id)

## Update report status (admin only)
func update_report_status(admin_id: String, report_id: String, new_status: Status, 
		notes: String = "") -> Dictionary:
	
	# Verify admin permission
	if PermissionManager:
		if not PermissionManager.has_permission(admin_id, PermissionManager.Level.MOD):
			return {"success": false, "message": "MOD level required"}
	
	if not _reports.has(report_id):
		return {"success": false, "message": "Report not found"}
	
	var report: Report = _reports[report_id]
	report.status = new_status
	report.updated_at = Time.get_unix_time_from_system()
	report.resolution_notes = notes
	
	if new_status == Status.REVIEWING:
		report.assigned_to = admin_id
	
	# Log status change
	GameLog.info("PlayerReporter: Report %s status changed to %s by %s" % [report_id, new_status, admin_id])
	
	# Notify reporter
	_notify_reporter(report)
	
	report_updated.emit(report)
	
	return {"success": true, "message": "Report updated"}

## Assign report to admin
func assign_report(admin_id: String, report_id: String) -> Dictionary:
	return update_report_status(admin_id, report_id, Status.REVIEWING)

## ============================================================================
## HELPER FUNCTIONS
## ============================================================================

func _check_cooldown(reporter_id: String) -> Dictionary:
	if _report_cooldowns.has(reporter_id):
		var last_report: int = _report_cooldowns[reporter_id]
		var elapsed: float = Time.get_unix_time_from_system() - last_report
		if elapsed < REPORT_COOLDOWN_SECONDS:
			var remaining := REPORT_COOLDOWN_SECONDS - int(elapsed)
			return {
				"success": false, 
				"message": "Please wait %d seconds before submitting another report" % remaining
			}
	return {"success": true}

func _check_rate_limit(reporter_id: String) -> Dictionary:
	var now := Time.get_ticks_msec()
	var hour_ms := 3600000  # 1 hour in ms
	
	if _hourly_reports.has(reporter_id):
		var data: Dictionary = _hourly_reports[reporter_id]
		# Reset if window expired
		if now - data["window_start"] > hour_ms:
			_hourly_reports[reporter_id] = {"count": 0, "window_start": now}
		elif data["count"] >= MAX_REPORTS_PER_HOUR:
			return {
				"success": false,
				"message": "You have reached the maximum of %d reports per hour" % MAX_REPORTS_PER_HOUR
			}
	
	return {"success": true}

func _update_rate_limit(reporter_id: String) -> void:
	var now := Time.get_ticks_msec()
	
	if not _hourly_reports.has(reporter_id):
		_hourly_reports[reporter_id] = {"count": 0, "window_start": now}
	
	_hourly_reports[reporter_id]["count"] += 1

func _log_report(report: Report) -> void:
	var log_msg := "REPORT: [%s] %s reported %s" % [
		report.id,
		report.reporter_id,
		report._type_to_string()
	]
	
	if report.target_id != "":
		log_msg += " against %s" % report.target_id
	
	if report.priority == Priority.URGENT:
		GameLog.warn(log_msg)
	elif report.priority == Priority.HIGH:
		GameLog.info(log_msg)
	else:
		GameLog.debug(log_msg)

func _notify_reporter(report: Report) -> void:
	if NotificationService:
		var status_msg := ""
		match report.status:
			Status.RESOLVED:
				status_msg = "Your report has been resolved: %s" % report.resolution_notes
			Status.DISMISSED:
				status_msg = "Your report was reviewed and dismissed: %s" % report.resolution_notes
			Status.ESCALATED:
				status_msg = "Your report has been escalated for urgent review."
		
		if status_msg != "":
			# Frame-level notify. The reporter's status is admin-mediated
			# free-form feedback; CUSTOM is the right kind (no dedicated
			# REPORT_STATUS slot). Dedupe key includes the report id and
			# status so a /status check on the same report doesn't
			# double-toast, but a status change to resolved then
			# escalated will.
			if is_instance_valid(NotificationService):
				NotificationService.notify(
					NotifKind.CUSTOM,
					status_msg,
					"PlayerReporter",
					"report:%s:%s" % [report.id, report.status],
					{"report_id": report.id, "status": report.status},
					report.reporter_id
				)

func _emit_urgent_alert(report: Report) -> void:
	# Emit signal for Discord webhook, email, etc.
	urgent_report.emit(report)
	
	# Log prominently
	GameLog.warn("URGENT REPORT: %s - %s" % [report.id, report.subject])

## ============================================================================
## MAINTENANCE
## ============================================================================

func _process(delta: float) -> void:
	# Cleanup old cooldown entries
	var now := Time.get_unix_time_from_system()
	var cooldown_cutoff := now - (REPORT_COOLDOWN_SECONDS * 2)
	
	for reporter_id in _report_cooldowns.keys():
		if _report_cooldowns[reporter_id] < cooldown_cutoff:
			_report_cooldowns.erase(reporter_id)

## ============================================================================
## SIGNALS
## ============================================================================

signal report_submitted(report: Report)
signal report_updated(report: Report)
signal urgent_report(report: Report)  # For Discord webhook, etc.
