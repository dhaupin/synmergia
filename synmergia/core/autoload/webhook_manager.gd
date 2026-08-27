## WebhookManager - Central webhook integration manager
## Connects DiscordWebhook to all game signals
class_name WebhookManager
extends Node

## Singleton instance
static var instance: WebhookManager

## Discord webhook
var _discord: DiscordWebhook

## Config
var discord_webhook_url: String = ""
var enabled: bool = true
var notify_on_admin_action: bool = true
var notify_on_report: bool = true
var notify_on_urgent: bool = true
var notify_on_exploit: bool = true
var notify_on_server_status: bool = false  # Only on start/stop

func _ready() -> void:
	instance = self
	
	# Create Discord webhook
	_discord = DiscordWebhook.new()
	add_child(_discord)
	
	# Load config
	_load_config()
	
	# Connect to signals
	_connect_signals()
	
	Logger.info("WebhookManager: Initialized")

func _load_config() -> void:
	# Load from GameConfig if available
	if GameConfig.has("Webhooks"):
		var webhooks: Dictionary = GameConfig.Webhooks
		discord_webhook_url = webhooks.get("DISCORD_WEBHOOK_URL", "")
		enabled = webhooks.get("ENABLED", true)
		notify_on_admin_action = webhooks.get("NOTIFY_ADMIN_ACTIONS", true)
		notify_on_report = webhooks.get("NOTIFY_REPORTS", true)
		notify_on_urgent = webhooks.get("NOTIFY_URGENT", true)
		notify_on_exploit = webhooks.get("NOTIFY_EXPLOITS", true)
	
	# Apply to connector
	if _discord:
		_discord.webhook_url = discord_webhook_url
		_discord.enabled = enabled

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
	
	_discord.send_admin_action(
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
	
	_discord.send_admin_action(admin_id, "KICK", player_id, true)

func _on_player_banned(player_id: String, duration: int, reason: String, admin_id: String) -> void:
	if not enabled or not notify_on_admin_action:
		return
	if not _discord or discord_webhook_url == "":
		return
	
	_discord.send_admin_action(admin_id, "BAN", player_id, true)

func _on_report_submitted(report) -> void:
	if not enabled or not notify_on_report:
		return
	if not _discord or discord_webhook_url == "":
		return
	
	_discord.send_player_report(
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
	
	_discord.send_urgent_report(
		report.id,
		report.reporter_id,
		report.target_id,
		report.subject,
		report.description
	)

func _on_exploit_detected(player_id: String, exploit_type: String, details: String) -> void:
	if not enabled or not notify_on_exploit:
		return
	if not _discord or discord_webhook_url == "":
		return
	
	_discord.send_exploit_alert(player_id, exploit_type, details)

func _on_vote_created(vote) -> void:
	if not enabled:
		return
	if not _discord or discord_webhook_url == "":
		return
	
	# Only notify on important votes
	if vote.type == CommunityGovernance.VoteType.REPORT_VALIDATION:
		var embed := _discord.create_embed(
			"🗳️ New Community Vote",
			"A new vote has been created for report validation.",
			DiscordWebhook.COLOR_BLUE
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
		
		_discord.send_embed(embed, "Synmergia Governance")

func _on_vote_closed(vote) -> void:
	if not enabled:
		return
	if not _discord or discord_webhook_url == "":
		return
	
	var results := vote.get_results()
	var passed := vote.is_passed()
	var color := DiscordWebhook.COLOR_GREEN if passed else DiscordWebhook.COLOR_RED
	
	var embed := _discord.create_embed(
		"🗳️ Vote Closed: %s" % ("PASSED" if passed else "FAILED"),
		vote.question,
		color
	)
	
	embed.fields.append({
		"name": "Total Votes",
		"value": str(vote.get_total_votes()),
		"inline": true
	})
	
	if not results.is_empty():
		var top_result := results[0]
		embed.fields.append({
			"name": "Winner",
			"value": "%s (%d votes)" % [top_result.text, top_result.votes],
			"inline": true
		})
	
	_discord.send_embed(embed, "Synmergia Governance")

## ============================================================================
## PUBLIC API
## ============================================================================

## Send a custom alert
func send_alert(title: String, description: String, color: int = DiscordWebhook.COLOR_RED) -> void:
	if not enabled or discord_webhook_url == "":
		return
	
	var embed := _discord.create_embed(title, description, color)
	_discord.send_embed(embed, "Synmergia Alert")

## Send server status
func send_server_status(status: String, player_count: int, details: Dictionary = {}) -> void:
	if not enabled or not notify_on_server_status or discord_webhook_url == "":
		return
	
	_discord.send_server_status(status, player_count, details)

## Update webhook URL
func set_webhook_url(url: String) -> void:
	discord_webhook_url = url
	if _discord:
		_discord.webhook_url = url

## Enable/disable
func set_enabled(enable: bool) -> void:
	enabled = enable
	if _discord:
		_discord.enabled = enable

## Toggle notification types
func set_notify_admin_actions(enabled: bool) -> void:
	notify_on_admin_action = enabled

func set_notify_reports(enabled: bool) -> void:
	notify_on_report = enabled

func set_notify_urgent(enabled: bool) -> void:
	notify_on_urgent = enabled

func set_notify_exploits(enabled: bool) -> void:
	notify_on_exploit = enabled
