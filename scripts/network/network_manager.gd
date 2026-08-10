extends Node

signal lobby_state_changed(players: Array, settings: Dictionary)
signal connection_state_changed(message: String)
signal network_error(message: String)

const DEFAULT_PORT := 24567
const MAX_FACTIONS := 4
const MAX_REMOTE_PLAYERS := MAX_FACTIONS - 1
const WORLD_SCENE := "res://scenes/world.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const PROFILE_PATH := "user://player.cfg"

var local_nickname := "Игрок"
var lobby_players := {}
var pending_peers := {}
var lobby_settings := {
	"seed": 12345,
	"requested_ai_count": 0,
	"port": DEFAULT_PORT,
}
var session_slots: Array[Dictionary] = []
var lobby_active := false
var session_configured := false
var lan_session := false
var hosting := false
var match_starting := false
var connection_pending := false
var menu_notice := ""
var join_order_counter := 0
var manual_shutdown := false


func _ready():
	_load_profile()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func set_local_nickname(value: String):
	local_nickname = _sanitize_nickname(value)
	_save_profile()


func host_lobby(nickname: String, seed_value: int, requested_ai_count: int, port: int = DEFAULT_PORT) -> String:
	shutdown_network()
	set_local_nickname(nickname)
	var safe_port := clampi(port, 1024, 65535)
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip("*")
	var result := peer.create_server(safe_port, MAX_REMOTE_PLAYERS)
	if result != OK:
		return "Не удалось создать LAN-сервер: %s" % error_string(result)

	multiplayer.multiplayer_peer = peer
	hosting = true
	lan_session = true
	lobby_active = true
	connection_pending = false
	match_starting = false
	join_order_counter = 1
	lobby_settings = {
		"seed": seed_value,
		"requested_ai_count": clampi(requested_ai_count, 0, MAX_FACTIONS),
		"port": safe_port,
	}
	lobby_players[1] = {
		"peer_id": 1,
		"nickname": _make_unique_nickname(local_nickname, 1),
		"ready": false,
		"join_order": 0,
	}
	connection_state_changed.emit("Лобби создано. Ожидание игроков…")
	_emit_lobby_state()
	return ""


func join_lobby(nickname: String, address: String, port: int = DEFAULT_PORT) -> String:
	shutdown_network()
	set_local_nickname(nickname)
	var clean_address := address.strip_edges()
	if clean_address.is_empty():
		return "Введите IP-адрес или имя компьютера хоста."
	var safe_port := clampi(port, 1024, 65535)
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_client(clean_address, safe_port)
	if result != OK:
		return "Не удалось начать подключение: %s" % error_string(result)

	multiplayer.multiplayer_peer = peer
	hosting = false
	lan_session = true
	lobby_active = true
	connection_pending = true
	match_starting = false
	lobby_settings = {"seed": 0, "requested_ai_count": 0, "port": safe_port}
	connection_state_changed.emit("Подключение к %s:%d…" % [clean_address, safe_port])
	return ""


func set_ready(value: bool):
	if not lobby_active or connection_pending or match_starting:
		return
	if multiplayer.is_server():
		_set_player_ready(1, value)
	else:
		_server_set_ready.rpc_id(1, value)


func prepare_singleplayer(seed_value: int, ai_count := 3):
	shutdown_network()
	lan_session = false
	session_configured = true
	lobby_active = false
	hosting = true
	session_slots.clear()
	session_slots.append(_make_slot(0, 1, local_nickname, false))
	var bot_count := mini(clampi(ai_count, 0, MAX_FACTIONS), MAX_FACTIONS - 1)
	for index in range(bot_count):
		session_slots.append(_make_slot(index + 1, 0, "ИИ %d" % (index + 1), true))
	_set_world_seed(seed_value)


func prepare_loaded_game(saved_slots: Array):
	shutdown_network()
	lan_session = false
	session_configured = true
	hosting = true
	session_slots.clear()
	if saved_slots.is_empty():
		session_slots.append(_make_slot(0, 1, local_nickname, false))
		return
	for raw_slot in saved_slots:
		if raw_slot is not Dictionary or session_slots.size() >= MAX_FACTIONS:
			continue
		var faction_id := clampi(int(raw_slot.get("faction_id", session_slots.size())), 0, MAX_FACTIONS - 1)
		var is_local := faction_id == 0
		var nickname := local_nickname if is_local else str(raw_slot.get("nickname", "ИИ %d" % faction_id))
		session_slots.append(_make_slot(faction_id, 1 if is_local else 0, nickname, not is_local))
	if session_slots.is_empty():
		session_slots.append(_make_slot(0, 1, local_nickname, false))


func shutdown_network():
	manual_shutdown = true
	var current_peer := multiplayer.multiplayer_peer
	if current_peer is ENetMultiplayerPeer:
		current_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_reset_runtime_state()
	manual_shutdown = false


func get_session_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in session_slots:
		result.append(slot.duplicate(true))
	return result


func get_lobby_players() -> Array:
	return _lobby_players_to_array()


func get_local_faction_id() -> int:
	var local_peer_id := multiplayer.get_unique_id() if lan_session else 1
	for slot in session_slots:
		if not bool(slot.get("is_ai", false)) and int(slot.get("controller_peer_id", 0)) == local_peer_id:
			return int(slot.get("faction_id", -1))
	return 0 if not lan_session else -1


func get_faction_slot(faction_id: int) -> Dictionary:
	for slot in session_slots:
		if int(slot.get("faction_id", -1)) == faction_id:
			return slot.duplicate(true)
	return {}


func has_session() -> bool:
	return session_configured


func is_lan_session() -> bool:
	return lan_session and session_configured


func is_host() -> bool:
	return hosting


func is_local_ready() -> bool:
	var local_peer_id := multiplayer.get_unique_id()
	return bool(lobby_players.get(local_peer_id, {}).get("ready", false))


func can_edit_faction(faction_id: int) -> bool:
	return faction_id == get_local_faction_id()


func get_local_addresses() -> Array[String]:
	var result: Array[String] = []
	for address in IP.get_local_addresses():
		var value := str(address)
		if value == "127.0.0.1" or value == "::1" or value.begins_with("169.254.") or value.begins_with("fe80:"):
			continue
		result.append(value)
	return result


func consume_menu_notice() -> String:
	var result := menu_notice
	menu_notice = ""
	return result


@rpc("any_peer", "call_remote", "reliable")
func _server_register_player(nickname: String):
	if not multiplayer.is_server() or not lobby_active or match_starting:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1:
		return
	var clean_nickname := _make_unique_nickname(_sanitize_nickname(nickname), sender)
	var order := join_order_counter
	if lobby_players.has(sender):
		order = int(lobby_players[sender].get("join_order", order))
	else:
		join_order_counter += 1
	lobby_players[sender] = {
		"peer_id": sender,
		"nickname": clean_nickname,
		"ready": false,
		"join_order": order,
	}
	pending_peers.erase(sender)
	_broadcast_lobby_state()


@rpc("any_peer", "call_remote", "reliable")
func _server_set_ready(value: bool):
	if not multiplayer.is_server() or not lobby_active or match_starting:
		return
	_set_player_ready(multiplayer.get_remote_sender_id(), value)


@rpc("authority", "call_local", "reliable")
func _receive_lobby_state(players: Array, settings: Dictionary):
	lobby_players.clear()
	for raw_player in players:
		if raw_player is not Dictionary:
			continue
		var player: Dictionary = raw_player.duplicate(true)
		var peer_id := int(player.get("peer_id", 0))
		if peer_id > 0:
			lobby_players[peer_id] = player
	lobby_settings = settings.duplicate(true)
	connection_pending = false
	lobby_active = true
	_emit_lobby_state()


@rpc("authority", "call_local", "reliable")
func _receive_start_session(raw_slots: Array, settings: Dictionary):
	if session_configured:
		return
	session_slots.clear()
	for raw_slot in raw_slots:
		if raw_slot is Dictionary and session_slots.size() < MAX_FACTIONS:
			session_slots.append(raw_slot.duplicate(true))
	lobby_settings = settings.duplicate(true)
	lobby_active = false
	connection_pending = false
	match_starting = true
	session_configured = true
	lan_session = true
	_set_world_seed(int(lobby_settings.get("seed", 12345)))
	connection_state_changed.emit("Все готовы. Запуск мира…")
	get_tree().call_deferred("change_scene_to_file", WORLD_SCENE)


@rpc("authority", "call_local", "reliable")
func _receive_session_slots(raw_slots: Array):
	session_slots.clear()
	for raw_slot in raw_slots:
		if raw_slot is Dictionary and session_slots.size() < MAX_FACTIONS:
			session_slots.append(raw_slot.duplicate(true))
	_apply_session_controllers_to_world()


func _set_player_ready(peer_id: int, value: bool):
	if not lobby_players.has(peer_id):
		return
	lobby_players[peer_id]["ready"] = value
	_broadcast_lobby_state()
	_try_start_match()


func _try_start_match():
	if not multiplayer.is_server() or match_starting or lobby_players.is_empty() or not pending_peers.is_empty():
		return
	for player in lobby_players.values():
		if not bool(player.get("ready", false)):
			return

	match_starting = true
	var ordered_players: Array = lobby_players.values()
	ordered_players.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("join_order", 0)) < int(b.get("join_order", 0)))
	var slots: Array[Dictionary] = []
	for player in ordered_players:
		if slots.size() >= MAX_FACTIONS:
			break
		slots.append(_make_slot(slots.size(), int(player.get("peer_id", 0)), str(player.get("nickname", "Игрок")), false))
	var free_slots := MAX_FACTIONS - slots.size()
	var bot_count := mini(int(lobby_settings.get("requested_ai_count", 0)), free_slots)
	for index in range(bot_count):
		slots.append(_make_slot(slots.size(), 0, "ИИ %d" % (index + 1), true))
	var current_peer := multiplayer.multiplayer_peer
	if current_peer != null:
		current_peer.refuse_new_connections = true
	_receive_start_session.rpc(_slots_to_array(slots), lobby_settings.duplicate(true))


func _on_peer_connected(peer_id: int):
	if multiplayer.is_server() and lobby_active and not match_starting:
		pending_peers[peer_id] = true
		connection_state_changed.emit("Игрок подключается…")
	elif multiplayer.is_server() and match_starting:
		var peer := multiplayer.multiplayer_peer
		if peer is ENetMultiplayerPeer:
			peer.disconnect_peer(peer_id)


func _on_peer_disconnected(peer_id: int):
	if not multiplayer.is_server():
		return
	pending_peers.erase(peer_id)
	if lobby_active and not session_configured:
		if lobby_players.erase(peer_id):
			_broadcast_lobby_state()
		_try_start_match()
		return
	if not session_configured:
		return
	var changed := false
	for slot in session_slots:
		if int(slot.get("controller_peer_id", 0)) != peer_id:
			continue
		slot["controller_peer_id"] = 0
		slot["is_ai"] = true
		slot["nickname"] = "%s (ИИ)" % str(slot.get("nickname", "Игрок"))
		changed = true
	if changed:
		_receive_session_slots.rpc(_slots_to_array(session_slots))


func _on_connected_to_server():
	connection_pending = true
	connection_state_changed.emit("Соединение установлено. Регистрация в лобби…")
	_server_register_player.rpc_id(1, local_nickname)


func _on_connection_failed():
	if manual_shutdown:
		return
	shutdown_network()
	network_error.emit("Не удалось подключиться к хосту.")


func _on_server_disconnected():
	if manual_shutdown:
		return
	var was_in_world := session_configured
	shutdown_network()
	if was_in_world:
		menu_notice = "Хост отключился — LAN-сессия завершена."
		get_tree().paused = false
		get_tree().call_deferred("change_scene_to_file", MAIN_MENU_SCENE)
	else:
		network_error.emit("Хост закрыл лобби.")


func _broadcast_lobby_state():
	if multiplayer.is_server():
		_receive_lobby_state.rpc(_lobby_players_to_array(), lobby_settings.duplicate(true))


func _emit_lobby_state():
	lobby_state_changed.emit(_lobby_players_to_array(), lobby_settings.duplicate(true))


func _lobby_players_to_array() -> Array:
	var players: Array = []
	for player in lobby_players.values():
		players.append(player.duplicate(true))
	players.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("join_order", 0)) < int(b.get("join_order", 0)))
	return players


func _slots_to_array(slots: Array[Dictionary]) -> Array:
	var result: Array = []
	for slot in slots:
		result.append(slot.duplicate(true))
	return result


func _make_slot(faction_id: int, controller_peer_id: int, nickname: String, is_ai: bool) -> Dictionary:
	return {
		"faction_id": faction_id,
		"controller_peer_id": controller_peer_id,
		"nickname": nickname,
		"is_ai": is_ai,
	}


func _apply_session_controllers_to_world():
	var world := get_tree().current_scene
	if not is_instance_valid(world) or not world.has_method("set_faction_controller"):
		return
	for slot in session_slots:
		world.set_faction_controller(
			int(slot.get("faction_id", 0)),
			int(slot.get("controller_peer_id", 0)),
			bool(slot.get("is_ai", true)),
			str(slot.get("nickname", "ИИ"))
		)


func _make_unique_nickname(value: String, ignored_peer_id: int) -> String:
	var base := _sanitize_nickname(value)
	var candidate := base
	var suffix := 2
	var used := {}
	for peer_id in lobby_players:
		if int(peer_id) != ignored_peer_id:
			used[str(lobby_players[peer_id].get("nickname", "")).to_lower()] = true
	while used.has(candidate.to_lower()):
		candidate = "%s %d" % [base, suffix]
		suffix += 1
	return candidate


func _sanitize_nickname(value: String) -> String:
	var result := value.strip_edges()
	result = result.replace("\n", " ").replace("\r", " ").replace("\t", " ")
	while result.contains("  "):
		result = result.replace("  ", " ")
	if result.is_empty():
		result = "Игрок"
	return result.left(24)


func _set_world_seed(seed_value: int):
	var save_manager := get_node_or_null("/root/SaveManager")
	if is_instance_valid(save_manager):
		save_manager.current_seed = seed_value
		save_manager.pending_save_data.clear()
	get_tree().paused = false


func _reset_runtime_state():
	lobby_players.clear()
	pending_peers.clear()
	lobby_settings = {"seed": 12345, "requested_ai_count": 0, "port": DEFAULT_PORT}
	session_slots.clear()
	lobby_active = false
	session_configured = false
	lan_session = false
	hosting = false
	match_starting = false
	connection_pending = false
	join_order_counter = 0


func _load_profile():
	var config := ConfigFile.new()
	if config.load(PROFILE_PATH) == OK:
		local_nickname = _sanitize_nickname(str(config.get_value("player", "nickname", "Игрок")))


func _save_profile():
	var config := ConfigFile.new()
	config.set_value("player", "nickname", local_nickname)
	config.save(PROFILE_PATH)
