## WebhookBase - Generic webhook connector (abstract base)
## 
## This is the base handler that all webhook connectors inherit from.
## Keeps webhook logic DRY in one place.
##
## Architecture:
##   webhook_base.gd (generic handler) ← discord_webhook.gd (Discord-specific)
##                          ← slack_webhook.gd (future)
##                          ← generic_http_webhook.gd (future)
##
## Usage:
##   1. Set webhook_url from GameConfig
##   2. Call send() to queue messages
##   3. Use derived classes for platform-specific formatting

class_name WebhookBase
extends Node

## Webhook message (generic format)
class WebhookMessage:
	var content: String
	var embeds: Array
	var username: String
	var avatar_url: String
	var tts: bool
	
	func _init(p_content: String = ""):
		content = p_content
		embeds = []
		username = ""
		avatar_url = ""
		tts = false
	
	func to_dict() -> Dictionary:
		var data := {"content": content}
		if not embeds.is_empty():
			data["embeds"] = embeds
		if username != "":
			data["username"] = username
		if avatar_url != "":
			data["avatar_url"] = avatar_url
		if tts:
			data["tts"] = true
		return data

## Embed object (generic format)
class Embed:
	var title: String
	var description: String
	var color: int
	var url: String
	var timestamp: String
	var footer: Dictionary
	var image: Dictionary
	var thumbnail: Dictionary
	var author: Dictionary
	var fields: Array
	
	func _init():
		title = ""
		description = ""
		color = 0
		url = ""
		timestamp = ""
		footer = {}
		image = {}
		thumbnail = {}
		author = {}
		fields = []
	
	func set_color_hex(hex: String) -> void:
		hex = hex.lstrip("#")
		color = int("0x" + hex)
	
	func to_dict() -> Dictionary:
		var data := {}
		if title != "": data["title"] = title
		if description != "": data["description"] = description
		if color != 0: data["color"] = color
		if url != "": data["url"] = url
		if timestamp != "": data["timestamp"] = timestamp
		if not footer.is_empty(): data["footer"] = footer
		if not image.is_empty(): data["image"] = image
		if not thumbnail.is_empty(): data["thumbnail"] = thumbnail
		if not author.is_empty(): data["author"] = author
		if not fields.is_empty(): data["fields"] = fields
		return data

## Signal when message is sent
signal message_sent(success: bool, response_code: int)

## HTTP client
var _http_request: HTTPRequest

## Message queue for rate limiting
var _message_queue: Array = []
var _is_sending: bool = false
var _rate_limit_remaining: int = -1
var _rate_limit_reset: float = 0

## Configuration (loaded from GameConfig)
var webhook_url: String = ""
var enabled: bool = true
var rate_limit_per_second: int = 5

func _init() -> void:
	pass

func _ready() -> void:
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)
	
	# Load config from GameConfig
	_load_config()

func _load_config() -> void:
	if GameConfig:
		var cfg := GameConfig.Webhooks
		enabled = cfg.ENABLED
		rate_limit_per_second = cfg.MAX_MESSAGES_PER_MINUTE / 60.0

func send(message: WebhookMessage) -> void:
	if not enabled:
		return
	_message_queue.append(message)
	_process_queue()

func send_immediate(message: WebhookMessage) -> bool:
	if webhook_url == "":
		Logger.warn("WebhookBase: No webhook URL configured")
		return false
	
	if _rate_limit_remaining == 0:
		if Time.get_unix_time_from_system() < _rate_limit_reset:
			return false
		else:
			_rate_limit_remaining = -1
	
	var payload := JSON.stringify(message.to_dict())
	var headers := ["Content-Type: application/json"]
	
	var result := _http_request.request(webhook_url, headers, HTTPClient.METHOD_POST, payload)
	return result == OK

func _process_queue() -> void:
	if _is_sending or _message_queue.is_empty():
		return
	
	_is_sending = true
	var message: WebhookMessage = _message_queue.pop_front() as WebhookMessage
	var success := send_immediate(message)
	
	if not success and _rate_limit_remaining == 0:
		var delay := max(0.1, _rate_limit_reset - Time.get_unix_time_from_system())
		await get_tree().create_timer(delay).timeout
	
	_is_sending = false
	
	if not _message_queue.is_empty():
		_process_queue()

func _on_request_completed(result: int, response_code: int, headers: Array, body: PackedByteArray) -> void:
	for header in headers:
		var parts := header.split(": ", false, 1)
		if parts.size() == 2:
			match parts[0].to_lower():
				"x-ratelimit-remaining":
					_rate_limit_remaining = int(parts[1])
				"x-ratelimit-reset":
					_rate_limit_reset = float(parts[1])
	
	message_sent.emit(response_code == 200 or response_code == 204, response_code)
	
	if response_code != 200 and response_code != 204:
		Logger.warn("WebhookBase: Request failed with code %d" % response_code)

static func create_embed(title: String = "", description: String = "", color: int = 0) -> Embed:
	var embed := Embed.new()
	embed.title = title
	embed.description = description
	embed.color = color
	return embed
