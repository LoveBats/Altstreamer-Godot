class_name AltstreamService
extends Node

const HOST		:= "https://altstream.online"
const CHAT_ENDPOINT	:= "/api/chat/stream?channel=%s"

signal connected
signal disconnected
signal connection_failed

signal chat_message_received(user: Altstream.User, message: Altstream.Message)
signal chat_sticker_received(user: Altstream.User, message_id: String, name: String, url: String)
signal chat_highlight_received(user: Altstream.User, message: Altstream.Message, reward_name: String)
signal chat_message_pinned(user: Altstream.User, message: Altstream.Message, pinned_by: String)
signal chat_message_unpinned()
signal chat_message_deleted(message_id: String)
signal chat_cleared()

signal raid_incoming(from: Altstream.User, _raider_count: int) # raider count currently unavailable
signal raid_outgoing_started(target: Altstream.User, viewer_count: int, countdown: int)
signal raid_outgoing_canceled()

#signal kofi_tip_received(from: Altstream.User, type: String, amount: String, currency: String)

signal reward_redeemed(user: Altstream.User, message_id: String, reward_name: String, user_input: String)
signal user_shouted_out(target: Altstream.User, game_name: String, game_cover_url: String, shouted_by: Altstream.User)

@export var autoconnect := true
@export var channel := ""

func start(channel_connect: String = channel) -> void:
	if client.status == EventStreamClient.Status.DISCONNECTED:
		if not channel_connect.is_empty():
			client.connect_to_host(HOST, CHAT_ENDPOINT % channel_connect)
		else:
			print("No channel specified for Altstreamer connection")
	else:
		print("EventStream not disconnected, could not initiate new connection.")

func stop() -> void:
	client.close()

# Above this comment is the public API of this type.
# Below you can find the implementation details.
# You should not need to access this.

var client := EventStreamClient.new()

func _init() -> void:
	client.connected.connect(_on_connected)
	client.disconnected.connect(_on_disconnected)
	client.connection_failed.connect(_on_connection_failed)
	client.event_received.connect(_on_event_received)

func _ready() -> void:
	if autoconnect:
		start()

func _process(_delta: float) -> void:
	client.poll()

func _on_connected() -> void:
	print("Altstreamer connected")
	connected.emit()

func _on_disconnected(error: String) -> void:
	if error: print("Altstreamer disconnected: " + error)
	else: print("Altstreamer disconnected")
	disconnected.emit()

func _on_connection_failed(error: String) -> void:
	if error: print("Altstreamer failed to connect: " + error)
	else: print("Altstreamer failed to connect")
	connection_failed.emit()

func _on_event_received(_event: String, event_data: String) -> void:
	for msg in JSON.parse_string(event_data):
		var message := _message_from_msg(msg)
		var user    := _user_from_msg(msg)
		var data: Dictionary[String, Variant]
		data.assign(msg.get("data", {}))

		match _type_lookup.get(msg.get("type")):
			Altstream.Type.MESSAGE      : _handle_message(message, user, msg)
			Altstream.Type.HIGHLIGHT    : _handle_highlight(message, user, data)
			Altstream.Type.REDEMPTION   : _handle_redemption(message, user, data)
			Altstream.Type.TIP          : pass
			Altstream.Type.SHOP         : pass # TODO: Implement Ko-Fi events.
			Altstream.Type.SUBSCRIPTION : pass
			Altstream.Type.PIN          : _handle_pin(data)
			Altstream.Type.UNPIN        : chat_message_unpinned.emit()
			Altstream.Type.SHOUTOUT     : _handle_shoutout(user, data)
			Altstream.Type.RAID         : _handle_raid(user, data)
			Altstream.Type.DELETE       : _handle_delete(msg)
			Altstream.Type.CLEAR        : chat_cleared.emit()

			Altstream.Type.SYSTEM:
				if message.text.begins_with("[RAID_CANCEL]"):
					raid_outgoing_canceled.emit()

func _handle_message(message: Altstream.Message, user: Altstream.User, raw_msg: Dictionary) -> void:
	var sticker_name := _try_get_string(raw_msg, "stickerName")
	var sticker_url  := _try_get_string(raw_msg, "stickerUrl")
	if message.text: chat_message_received.emit(user, message)
	if sticker_name: chat_sticker_received.emit(user, message.id, sticker_name, sticker_url)

func _handle_highlight(message: Altstream.Message, user: Altstream.User, data: Dictionary[String, Variant]) -> void:
	message.text     = _try_get_string(data, "text")
	var reward_name := _try_get_string(data, "rewardName")
	chat_highlight_received.emit(user, message, reward_name)

func _handle_redemption(message: Altstream.Message, user: Altstream.User, data: Dictionary[String, Variant]) -> void:
	var reward_name := _try_get_string(data, "rewardName")
	var user_input  := _try_get_string(data, "userInput") # optional
	reward_redeemed.emit(user, message.id, reward_name, user_input)

func _handle_pin(data: Dictionary[String, Variant]) -> void:
	var user      := _user_from_msg(data)
	var message   := _message_from_msg(data)
	var pinned_by := _try_get_string(data, "pinnedBy")
	chat_message_pinned.emit(user, message, pinned_by)

func _handle_shoutout(user: Altstream.User, data: Dictionary[String, Variant]) -> void:
	var target := Altstream.User.new()
	target.username     = _try_get_string(data, "targetUsername")
	target.display_name = _try_get_string(data, "targetDisplayName")
	target.avatar_url   = _try_get_string(data, "targetAvatar")
	var game_name      := _try_get_string(data, "gameName")
	var game_cover_url := _try_get_string(data, "gameCover")
	user_shouted_out.emit(target, game_name, game_cover_url, user)

func _handle_raid(user: Altstream.User, data: Dictionary[String, Variant]) -> void:
	if data.has("targetUsername"):
		var target := Altstream.User.new()
		target.username     = _try_get_string(data, "targetUsername")
		target.display_name = _try_get_string(data, "targetDisplayName")
		target.avatar_url   = _try_get_string(data, "targetImage")
		var viewers   := _try_get_int(data, "viewers")
		var countdown := _try_get_int(data, "countdownSeconds")
		raid_outgoing_started.emit(target, viewers, countdown)
	else:
		raid_incoming.emit(user, 0)

func _handle_delete(raw_msg: Dictionary) -> void:
	var target_id := _try_get_string(raw_msg, "targetId")
	chat_message_deleted.emit(target_id)


static var _type_lookup: Dictionary[String, Altstream.Type]
static var _role_lookup: Dictionary[String, Altstream.Role]
static func _static_init() -> void:
	for key: String in Altstream.Type: _type_lookup[key.to_lower()] = Altstream.Type[key]
	for key: String in Altstream.Role: _role_lookup[key.to_lower()] = Altstream.Role[key]

## Returns the value associated with `key` from this `Dictionary` as a `String`,
## or `default` if it's missing or a different data type (such as `TYPE_NIL`).
static func _try_get_string(dict: Dictionary, key: String, default := "") -> String:
	var variant = dict.get(key)
	return variant if (variant is String) else default

static func _try_get_int(dict: Dictionary, key: String, default := -1) -> int:
	var variant = dict.get(key)
	if variant is int: return variant
	elif variant is float: return roundi(variant)
	else: return default

static func _parse_color(value: String) -> Color:
	if value.is_empty(): return Color.WHITE
	var rgb := value.trim_prefix("#").hex_to_int()
	return Color.hex((rgb << 16) | 0x000000FF)

static func _user_from_msg(msg: Dictionary) -> Altstream.User:
	var user := Altstream.User.new()
	user.username     = _try_get_string(msg, "authorUsername")
	user.display_name = _try_get_string(msg, "author")
	user.pronouns     = _try_get_string(msg, "authorPronouns")
	user.avatar_url   = _try_get_string(msg, "authorImage")
	user.user_color   = _parse_color(_try_get_string(msg, "userColor"))

	for role: int in Altstream.Role.values():
		user.roles[role] = false
	if msg.get("roles") is Dictionary:
		for role: String in msg.roles:
			if _role_lookup.has(role):
				user.roles[_role_lookup[role]] = (msg.roles[role] == true)

	if msg.get("badges") is Array:
		for badge: String in msg.badges:
			if _role_lookup.has(badge):
				user.badges.append(_role_lookup[badge])

	return user

static func _message_from_msg(msg: Dictionary) -> Altstream.Message:
	var message := Altstream.Message.new()
	message.id      = _try_get_string(msg, "id")
	message.text    = _try_get_string(msg, "text")
	message.sent_at = _try_get_int   (msg, "sentAt")
	message.reply_to_id           = _try_get_string(msg, "replyToId")
	message.reply_to_username     = _try_get_string(msg, "replyToUsername")
	message.reply_to_display_name = _try_get_string(msg, "replyToAuthor")
	return message
