## DiscordWebhook - Discord webhook connector
## Sends formatted messages to Discord channels via webhooks
##
## Inherits from WebhookBase for generic webhook handling.
## Contains only Discord-specific formatting and color constants.
extends WebhookBase

const WebhookBase = preload("res://connectors/webhook/webhook_base.gd")
class_name DiscordWebhook

## Discord color constants
const COLOR_RED: int = 15158332
const COLOR_ORANGE: int = 15105570
const COLOR_YELLOW: int = 16776960
const COLOR_GREEN: int = 3066993
const COLOR_BLUE: int = 3447003
const COLOR_PURPLE: int = 10181046
const COLOR_GRAY: int = 9807270

func _ready() -> void:
	super._ready()

	# Load Discord-specific config from GameConfig
	if GameConfig:
		webhook_url = GameConfig.Webhooks.DISCORD_WEBHOOK_URL

	GameLog.info("DiscordWebhook: Initialized with URL: %s" % ["set" if webhook_url != "" else "not configured"])

## Send simple text message
func send_message(content: String, username: String = "Synmergia") -> void:
	var msg := WebhookMessage.new(content)
	msg.username = username
	send(msg)

## Send embed message
func send_embed(embed: Embed, username: String = "Synmergia") -> void:
	var msg := WebhookMessage.new("")
	msg.embeds.append(embed.to_dict())
	msg.username = username
	send(msg)

## Send security alert (red)
func send_security_alert(title: String, description: String, details: Dictionary = {}) -> void:
	var embed := create_embed(title, description, COLOR_RED)
	embed.timestamp = Time.get_datetime_string_from_unix_time(Time.get_unix_time_from_system())
	embed.footer = {"text": "Synmergia Security Alert"}

	# Add fields for details
	for key in details.keys():
		embed.fields.append({
			"name": key,
			"value": str(details[key]),
			"inline": true
		})

	send_embed(embed, "Synmergia Security")

## Send urgent report alert
func send_urgent_report(report_id: String, reporter: String, target: String,
		subject: String, description: String) -> void:
	var embed := create_embed(
		"🚨 URGENT REPORT: %s" % report_id,
		"**Reporter:** %s\n**Target:** %s\n\n**Subject:** %s\n\n**Description:**\n%s" % [
			reporter, target, subject, description
		],
		COLOR_RED
	)
	embed.timestamp = Time.get_datetime_string_from_unix_time(Time.get_unix_time_from_system())
	embed.footer = {"text": "Synmergia - Report System"}

	send_embed(embed, "Synmergia Reports")

## Send admin action notification
func send_admin_action(admin_id: String, action: String, target: String, success: bool) -> void:
	var color := COLOR_GREEN if success else COLOR_RED
	var status := "✅" if success else "❌"

	var embed := create_embed(
		"%s Admin Action: %s" % [status, action],
		"**Admin:** %s\n**Target:** %s" % [admin_id, target],
		color
	)
	embed.timestamp = Time.get_datetime_string_from_unix_time(Time.get_unix_time_from_system())
	embed.footer = {"text": "Synmergia Admin Audit"}

	send_embed(embed, "Synmergia Admin")

## Send player report notification
func send_player_report(report_id: String, type: String, reporter: String,
		target: String, subject: String) -> void:
	var color := COLOR_YELLOW
	var type_emoji := "📢"

	match type.to_upper():
		"ABUSE":
			type_emoji = "⚠️"
			color = COLOR_ORANGE
		"BUG":
			type_emoji = "🐛"
			color = COLOR_BLUE
		"FEEDBACK":
			type_emoji = "💬"
			color = COLOR_GREEN
		"SUGGESTION":
			type_emoji = "💡"
			color = COLOR_PURPLE
		"EXPLOIT":
			type_emoji = "🚨"
			color = COLOR_RED

	var embed := create_embed(
		"%s %s Report" % [type_emoji, type],
		"**ID:** %s\n**Reporter:** %s\n**Target:** %s\n**Subject:** %s" % [
			report_id, reporter, target if target != "" else "(none)", subject
		],
		color
	)
	embed.timestamp = Time.get_datetime_string_from_unix_time(Time.get_unix_time_from_system())
	embed.footer = {"text": "Synmergia Player Reports"}

	send_embed(embed, "Synmergia Reports")

## Send server status update
func send_server_status(status: String, player_count: int, details: Dictionary = {}) -> void:
	var color := COLOR_GREEN if status == "online" else COLOR_RED
	var embed := create_embed(
		"Server Status: %s" % status.capitalize(),
		"**Players Online:** %d" % player_count,
		color
	)
	embed.timestamp = Time.get_datetime_string_from_unix_time(Time.get_unix_time_from_system())
	embed.footer = {"text": "Synmergia Status"}

	for key in details.keys():
		embed.fields.append({
			"name": key,
			"value": str(details[key]),
			"inline": true
		})

	send_embed(embed, "Synmergia Status")

## Send exploit detection alert
func send_exploit_alert(player_id: String, exploit_type: String, details: String) -> void:
	var embed := create_embed(
		"🚨 Exploit Detected",
		"**Player:** %s\n**Type:** %s\n\n**Details:**\n%s" % [
			player_id, exploit_type, details
		],
		COLOR_RED
	)
	embed.timestamp = Time.get_datetime_string_from_unix_time(Time.get_unix_time_from_system())
	embed.footer = {"text": "Synmergia Anti-Cheat"}

	send_embed(embed, "Synmergia Anti-Cheat")
