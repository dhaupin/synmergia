## WebhookManager - Central webhook integration manager
## Connects DiscordWebhook to all game signals
extends Node

## Singleton instance
static var instance: WebhookManager

## Discord webhook (lazy load to avoid type resolution issues)
var _discord = null
var _discord_initialized: bool = false

## Config
var discord_webhook_url: String = ""
var enabled: bool = true
var notify_on_admin_action: bool = true
var notify_on_report: bool = true
var notify_on_urgent: bool = true
var notify_on_exploit: bool = true
var notify_on_server_status: bool = false  # Only on start/stop

func _get_discord() -> Node:
	if not _discord_initialized:
		_discord = load("res://connectors/webhook/discord_webhook.gd").new()
		add_child(_discord)
		_discord_initialized = true
	return _discord

func _ready() -> void:
	instance = self

	# Load config
	_load_config()

	# Connect to signals
	_connect_signals()

	GameLog.info("WebhookManager: Initialized")

func _load_config() -> void:
	# Load from GameConfig Webhooks class
	discord_webhook_url = GameConfig.Webhooks.DISCORD_WEBHOOK_URL
	enabled = GameConfig.Webhooks.ENABLED
	notify_on_admin_action = GameConfig.Webhooks.NOTIFY_ADMIN_ACTIONS
	notify_on_report = GameConfig.Webhooks.NOTIFY_REPORTS
	notify_on_urgent = GameConfig.Webhooks.NOTIFY_URGENT
	notify_on_exploit = GameConfig.Webhooks.NOTIFY_EXPLOITS

	# Apply to connector
	if _discord_initialized:
		_get_discord().webhook_url = discord_webhook_url
		_get_discord().enabled = enabled

func _connect_signals() -> void:
	# PermissionManager signals
	if PermissionManager:
		PermissionManager.admin_action.connect(_on_admin_action)
		PermissionManager.player_kicked.connect(_on_player_kicked)
		PermissionManager.player_banned.connect(_on_player_banned)

	# PlayerReporter signals
	if PlayerReporter:
		PlayerReporter.report_submitted.connect(_on_report_submitted)
		PlayerReporter.urgent_report.connect(_on_urgent_report)

	# SecurityService signals (exploit detection)
	if SecurityService:
		SecurityService.exploit_detected.connect(_on_exploit_detected)

	# CommunityGovernance signals
	if CommunityGovernance:
		CommunityGovernance.vote_created.connect(_on_vote_created)
		CommunityGovernance.vote_closed.connect(_on_vote_closed)

## ============================================================================
## SIGNAL HANDLERS
## ============================================================================

func _on_admin_action(entry) -> void:
	if not enabled or not notify_on_admin_action:
		return
	if not _discord or discord_webhook_url == "":
		return

	_get_discord().send_admin_action(
		entry.admin_id,
		entry.action,
		entry.target_id,
		entry.success
	)

func _on_player_kicked(player_id: String, reason: String, admin_id: String) -> void:
	if not enabled or not notify_on_admin_action:
		return
	if not _discord or discord_webhook_url == "":
		return

	var details := {
		"reason": reason,
		"admin": admin_id
	}

	_get_discord().send_admin_action(admin_id, "KICK", player_id, true)

func _on_player_banned(player_id: String, duration: int, reason: String, admin_id: String) -> void:
	if not enabled or not notify_on_admin_action:
		return
	if not _discord or discord_webhook_url == "":
		return

	_get_discord().send_admin_action(admin_id, "BAN", player_id, true)

func _on_report_submitted(report) -> void:
	if not enabled or not notify_on_report:
		return
	if not _discord or discord_webhook_url == "":
		return

	_get_discord().send_player_report(
		report.id,
		report._type_to_string(),
		report.reporter_id,
		report.target_id,
		report.subject
	)

func _on_urgent_report(report) -> void:
	if not enabled or not notify_on_urgent:
		return
	if not _discord or discord_webhook_url == "":
		return

	_get_discord().send_urgent_report(
		report.id,
		report.reporter_id,
		report.target_id,
		report.subject,
		report.description
	)

## NOTE: SecurityService.exploit_detected carries a Dictionary (not a
## String) -- the arity mismatch here used to break every exploit
## webhook with "Cannot convert argument 3 from Dictionary to String".
## JSON-encode the evidence dict so the alert keeps its data.
func _on_exploit_detected(player_id: String, exploit_type: String, details) -> void:
	if not enabled or not notify_on_exploit:
		return
	if not _discord or discord_webhook_url == "":
		return

	var detail_text: String = details if details is String else JSON.stringify(details)
	_get_discord().send_exploit_alert(player_id, exploit_type, detail_text)

func _on_vote_created(vote) -> void:
	if not enabled:
		return
	if not _discord or discord_webhook_url == "":
		return

	# Only notify on important votes
	if vote.type == CommunityGovernance.VoteType.REPORT_VALIDATION:
		var embed = _get_discord().create_embed(
			" New Community Vote",
			"A new vote has been created for report validation.",
			3447003
		)
		embed.fields.append({
			"name": "Vote ID",
			"value": vote.id,
			"inline": true
		})
		embed.fields.append({
			"name": "Duration",
			"value": "12 hours",
			"inline": true
		})

		_get_discord().send_embed(embed, "Synmergia Governance")

func _on_vote_closed(vote) -> void:
	if not enabled:
		return
	if not _discord or discord_webhook_url == "":
		return

	var results = vote.get_results()
	var passed = vote.is_passed()
	var color := 3066993 if passed else 15158332

	var embed = _get_discord().create_embed(
		" Vote Closed: %s" % ("PASSED" if passed else "FAILED"),
		vote.question,
		color
	)

	embed.fields.append({
		"name": "Total Votes",
		"value": str(vote.get_total_votes()),
		"inline": true
	})

	if not results.is_empty():
		var top_result = results[0]
		embed.fields.append({
			"name": "Winner",
			"value": "%s (%d votes)" % [top_result.text, top_result.votes],
			"inline": true
		})

	_get_discord().send_embed(embed, "Synmergia Governance")

## ============================================================================
## PUBLIC API
## ============================================================================

## Send a custom alert
func send_alert(title: String, description: String, color: int = 15158332) -> void:
	if not enabled or discord_webhook_url == "":
		return

	var embed = _get_discord().create_embed(title, description, color)
	_get_discord().send_embed(embed, "Synmergia Alert")

## Send server status
func send_server_status(status: String, player_count: int, details: Dictionary = {}) -> void:
	if not enabled or not notify_on_server_status or discord_webhook_url == "":
		return

	_get_discord().send_server_status(status, player_count, details)

## Update webhook URL
func set_webhook_url(url: String) -> void:
	discord_webhook_url = url
	if _discord:
		_get_discord().webhook_url = url

## Enable/disable
func set_enabled(enable: bool) -> void:
	enabled = enable
	if _discord:
		_get_discord().enabled = enable

## Toggle notification types
func set_notify_admin_actions(enabled: bool) -> void:
	notify_on_admin_action = enabled

func set_notify_reports(enabled: bool) -> void:
	notify_on_report = enabled

func set_notify_urgent(enabled: bool) -> void:
	notify_on_urgent = enabled

func set_notify_exploits(enabled: bool) -> void:
	notify_on_exploit = enabled
