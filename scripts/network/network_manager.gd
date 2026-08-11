extends Node

signal lobby_state_changed(players: Array, settings: Dictionary)
signal connection_state_changed(message: String)
signal network_error(message: String)
signal discovered_lobbies_changed(lobbies: Array)

const DEFAULT_PORT := 24567
const MAX_FACTIONS := 4
const MAX_REMOTE_PLAYERS := MAX_FACTIONS - 1
const WORLD_SCENE := "res://scenes/world.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const PROFILE_PATH := "user://player.cfg"
const DISCOVERY_PORT := 24566
const DISCOVERY_QUERY := "SOVEREIGN_DISCOVER_V1"
const DISCOVERY_RESPONSE := "SOVEREIGN_LOBBY_V1"
const DISCOVERY_SCAN_INTERVAL := 1.5
const DISCOVERY_LOBBY_TIMEOUT_MSEC := 5000
const UNIT_STATE_SYNC_INTERVAL := 0.1
const BUILDING_STATE_SYNC_INTERVAL := 0.5
const MAX_UNITS_PER_COMMAND := 128
const MAX_BUILDINGS_PER_COMMAND := 256
const SERVER_ENTITY_ID_START := 1000000
const NETWORK_BUILDING_KINDS: Array[String] = [
	"residence", "warehouse", "factory", "food_factory", "mine",
	"power_plant", "barracks", "military_factory", "government", "road",
]

var local_nickname := "Игрок"
var local_player_id := ""
var lobby_players := {}
var pending_peers := {}
var lobby_settings := {
	"seed": 12345,
	"requested_ai_count": 0,
	"port": DEFAULT_PORT,
	"loaded_game": false,
	"saved_slots": [],
}
var loaded_world_data: Dictionary = {}
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
var _unit_state_sync_accumulator := 0.0
var _building_state_sync_accumulator := 0.0
var _next_server_entity_id := SERVER_ENTITY_ID_START
var _authoritative_resource_amounts := {}
var _world_ready_peers := {}
var _lan_discovery_peer: PacketPeerUDP
var _lan_discovery_mode: StringName = &"off"
var _lan_discovery_timer := 0.0
var _discovered_lobbies := {}


func _ready():
	_load_profile()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_start_lobby_scanner()


func _process(delta: float):
	_process_lan_discovery(delta)
	if not is_lan_session() or not multiplayer.is_server():
		_unit_state_sync_accumulator = 0.0
		_building_state_sync_accumulator = 0.0
		return
	var world := _get_world()
	if not is_instance_valid(world):
		return
	_unit_state_sync_accumulator += delta
	_building_state_sync_accumulator += delta
	if _unit_state_sync_accumulator >= UNIT_STATE_SYNC_INTERVAL and world.has_method("get_network_unit_states"):
		_unit_state_sync_accumulator = fmod(_unit_state_sync_accumulator, UNIT_STATE_SYNC_INTERVAL)
		_receive_unit_states.rpc(world.get_network_unit_states())
	if _building_state_sync_accumulator >= BUILDING_STATE_SYNC_INTERVAL and world.has_method("get_network_building_states"):
		_building_state_sync_accumulator = fmod(_building_state_sync_accumulator, BUILDING_STATE_SYNC_INTERVAL)
		_receive_building_states.rpc(world.get_network_building_states())
		if not _authoritative_resource_amounts.is_empty() and not _all_remote_worlds_ready():
			var resource_states: Array = []
			for record_id in _authoritative_resource_amounts:
				resource_states.append({"record_id": int(record_id), "amount": int(_authoritative_resource_amounts[record_id])})
			_receive_resource_states.rpc(resource_states)


func set_local_nickname(value: String):
	local_nickname = _sanitize_nickname(value)
	_save_profile()


func host_lobby(nickname: String, seed_value: int, requested_ai_count: int, port: int = DEFAULT_PORT, saved_game: Dictionary = {}) -> String:
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
	var loading_save := saved_game.has("world") and saved_game.has("meta")
	loaded_world_data = saved_game.world.duplicate(true) if loading_save else {}
	var saved_slots: Array = _infer_saved_slots(loaded_world_data, _normalize_saved_slots(loaded_world_data.get("session_slots", []))) if loading_save else []
	lobby_settings = {
		"seed": seed_value,
		"requested_ai_count": clampi(requested_ai_count, 0, MAX_FACTIONS),
		"port": safe_port,
		"loaded_game": loading_save,
		"save_name": str(saved_game.get("meta", {}).get("name", "Без названия")) if loading_save else "",
		"saved_slots": saved_slots,
	}
	lobby_players[1] = {
		"peer_id": 1,
		"nickname": _make_unique_nickname(local_nickname, 1),
		"player_id": local_player_id,
		"ready": false,
		"join_order": 0,
		"requested_faction_id": -1,
		"selected_faction_id": -1,
		"requires_faction_choice": false,
	}
	_reconcile_loaded_lobby_assignments()
	_start_lobby_advertiser()
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
	_stop_lan_discovery()
	hosting = false
	lan_session = true
	lobby_active = true
	connection_pending = true
	match_starting = false
	lobby_settings = {"seed": 0, "requested_ai_count": 0, "port": safe_port, "loaded_game": false, "saved_slots": []}
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
	_stop_lan_discovery()
	lan_session = false
	session_configured = true
	lobby_active = false
	hosting = true
	session_slots.clear()
	session_slots.append(_make_slot(0, 1, local_nickname, false, local_player_id))
	var bot_count := mini(clampi(ai_count, 0, MAX_FACTIONS), MAX_FACTIONS - 1)
	for index in range(bot_count):
		session_slots.append(_make_slot(index + 1, 0, "ИИ %d" % (index + 1), true))
	_set_world_seed(seed_value)


func prepare_loaded_game(saved_slots: Array):
	shutdown_network()
	_stop_lan_discovery()
	lan_session = false
	session_configured = true
	hosting = true
	session_slots.clear()
	if saved_slots.is_empty():
		session_slots.append(_make_slot(0, 1, local_nickname, false, local_player_id))
		return
	var normalized := _normalize_saved_slots(saved_slots)
	var local_faction := _find_owned_faction_in_slots(normalized, local_player_id, local_nickname)
	if local_faction < 0 and not normalized.is_empty():
		local_faction = int(normalized[0].get("faction_id", 0))
	for raw_slot in normalized:
		var faction_id := int(raw_slot.get("faction_id", 0))
		var is_local := faction_id == local_faction
		var nickname := local_nickname if is_local else str(raw_slot.get("nickname", "ИИ %d" % faction_id))
		var owner_id := local_player_id if is_local else str(raw_slot.get("owner_id", ""))
		session_slots.append(_make_slot(faction_id, 1 if is_local else 0, nickname, not is_local, owner_id))
	if session_slots.is_empty():
		session_slots.append(_make_slot(0, 1, local_nickname, false, local_player_id))


func shutdown_network():
	manual_shutdown = true
	var current_peer := multiplayer.multiplayer_peer
	if current_peer is ENetMultiplayerPeer:
		current_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_reset_runtime_state()
	manual_shutdown = false
	_start_lobby_scanner()


func get_session_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in session_slots:
		result.append(slot.duplicate(true))
	return result


func get_lobby_players() -> Array:
	return _lobby_players_to_array()


func get_discovered_lobbies() -> Array:
	var result: Array = []
	for lobby in _discovered_lobbies.values():
		var public_lobby: Dictionary = lobby.duplicate(true)
		public_lobby.erase("last_seen_msec")
		result.append(public_lobby)
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		var first_host := str(a.get("host_name", "")).to_lower()
		var second_host := str(b.get("host_name", "")).to_lower()
		return first_host < second_host if first_host != second_host else str(a.get("address", "")) < str(b.get("address", ""))
	)
	return result


func refresh_lan_lobbies():
	if _lan_discovery_mode != &"scanner":
		_start_lobby_scanner()
	_lan_discovery_timer = 0.0
	_send_discovery_query()


func get_local_lobby_player() -> Dictionary:
	var peer_id := multiplayer.get_unique_id()
	return lobby_players.get(peer_id, {}).duplicate(true)


func get_available_loaded_faction_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not bool(lobby_settings.get("loaded_game", false)):
		return result
	var local_peer_id := multiplayer.get_unique_id()
	var claimed := {}
	for player in lobby_players.values():
		if int(player.get("peer_id", 0)) == local_peer_id:
			continue
		var faction_id := int(player.get("selected_faction_id", -1))
		if faction_id >= 0:
			claimed[faction_id] = true
	for slot in lobby_settings.get("saved_slots", []):
		if slot is not Dictionary:
			continue
		var faction_id := int(slot.get("faction_id", -1))
		if faction_id < 0 or claimed.has(faction_id):
			continue
		result.append({"faction_id": faction_id, "nickname": _ai_display_name(str(slot.get("nickname", "ИИ")))})
	return result


func choose_loaded_faction(faction_id: int):
	if not lobby_active or not bool(lobby_settings.get("loaded_game", false)):
		return
	if multiplayer.is_server():
		_set_loaded_faction_choice(1, faction_id)
	else:
		_server_choose_loaded_faction.rpc_id(1, faction_id)


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


func is_remote_client() -> bool:
	return is_lan_session() and not multiplayer.is_server()


func notify_world_ready():
	if not is_lan_session():
		return
	var local_peer_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		_world_ready_peers[local_peer_id] = true
	else:
		_server_world_ready.rpc_id(1)


func request_unit_command(units: Array, action: StringName, payload: Dictionary = {}):
	var unit_ids: Array[int] = []
	for candidate in units:
		if candidate is Unit and is_instance_valid(candidate) and candidate.can_be_controlled_locally() and candidate.network_id > 0:
			unit_ids.append(candidate.network_id)
			if unit_ids.size() >= MAX_UNITS_PER_COMMAND:
				break
	if unit_ids.is_empty():
		return
	if not is_lan_session():
		_apply_unit_command(get_local_faction_id(), action, unit_ids, payload)
	elif multiplayer.is_server():
		_handle_server_unit_command(1, action, unit_ids, payload)
	else:
		_server_request_unit_command.rpc_id(1, action, unit_ids, payload)


func request_building_action(building: Building, action: StringName, payload: Dictionary = {}):
	if not is_instance_valid(building) or building.network_id <= 0 or not building.can_be_edited_locally():
		return
	if not is_lan_session():
		_apply_building_action(building.faction_id, building.network_id, action, payload)
	elif multiplayer.is_server():
		_handle_server_building_action(1, building.network_id, action, payload)
	else:
		_server_request_building_action.rpc_id(1, building.network_id, action, payload)


func request_spawn_buildings(specifications: Array, builders: Array):
	if specifications.is_empty():
		return
	var builder_ids: Array[int] = []
	for candidate in builders:
		if candidate is Unit and is_instance_valid(candidate) and candidate.can_be_controlled_locally() and candidate.network_id > 0:
			builder_ids.append(candidate.network_id)
	if not is_lan_session():
		var local_specs: Array = []
		for raw_spec in specifications:
			if raw_spec is Dictionary:
				var spec: Dictionary = raw_spec.duplicate(true)
				spec["faction_id"] = get_local_faction_id()
				spec["network_id"] = _allocate_server_entity_id()
				local_specs.append(spec)
		var local_world := _get_world()
		if is_instance_valid(local_world) and local_world.has_method("spawn_network_buildings"):
			local_world.spawn_network_buildings(local_specs, builder_ids)
	elif multiplayer.is_server():
		_handle_server_spawn_buildings(1, specifications, builder_ids)
	else:
		_server_request_spawn_buildings.rpc_id(1, specifications, builder_ids)


func replicate_resource_amount(record_id: int, amount: int):
	if is_lan_session() and multiplayer.is_server() and record_id > 0:
		var safe_amount := maxi(amount, 0)
		if not _all_remote_worlds_ready():
			_authoritative_resource_amounts[record_id] = safe_amount
		_receive_resource_amount.rpc(record_id, safe_amount)


func get_local_addresses() -> Array[String]:
	var result: Array[String] = []
	for address in IP.get_local_addresses():
		var value := str(address)
		if value == "127.0.0.1" or value == "::1" or value.begins_with("169.254.") or value.begins_with("fe80:"):
			continue
		result.append(value)
	return result


func _start_lobby_scanner():
	if lobby_active or session_configured:
		return
	_stop_lan_discovery()
	var peer := PacketPeerUDP.new()
	if peer.bind(0, "0.0.0.0") != OK:
		return
	peer.set_broadcast_enabled(true)
	_lan_discovery_peer = peer
	_lan_discovery_mode = &"scanner"
	_lan_discovery_timer = 0.0


func _start_lobby_advertiser():
	_stop_lan_discovery()
	var peer := PacketPeerUDP.new()
	if peer.bind(DISCOVERY_PORT, "0.0.0.0") != OK:
		return
	_lan_discovery_peer = peer
	_lan_discovery_mode = &"advertiser"


func _stop_lan_discovery(clear_discovered := true):
	if is_instance_valid(_lan_discovery_peer):
		_lan_discovery_peer.close()
	_lan_discovery_peer = null
	_lan_discovery_mode = &"off"
	_lan_discovery_timer = 0.0
	if clear_discovered and not _discovered_lobbies.is_empty():
		_discovered_lobbies.clear()
		discovered_lobbies_changed.emit([])


func _process_lan_discovery(delta: float):
	if not is_instance_valid(_lan_discovery_peer):
		return
	match _lan_discovery_mode:
		&"scanner":
			_lan_discovery_timer -= delta
			if _lan_discovery_timer <= 0.0:
				_lan_discovery_timer = DISCOVERY_SCAN_INTERVAL
				_send_discovery_query()
			_receive_discovery_responses()
			_expire_discovered_lobbies()
		&"advertiser":
			_receive_discovery_queries()


func _send_discovery_query():
	if _lan_discovery_mode != &"scanner" or not is_instance_valid(_lan_discovery_peer):
		return
	var query := DISCOVERY_QUERY.to_utf8_buffer()
	for address in ["255.255.255.255", "127.0.0.1"]:
		if _lan_discovery_peer.set_dest_address(address, DISCOVERY_PORT) == OK:
			_lan_discovery_peer.put_packet(query)


func _receive_discovery_queries():
	if not hosting or not lobby_active or match_starting:
		return
	while _lan_discovery_peer.get_available_packet_count() > 0:
		var packet := _lan_discovery_peer.get_packet()
		var sender_address := _lan_discovery_peer.get_packet_ip()
		var sender_port := _lan_discovery_peer.get_packet_port()
		if packet.get_string_from_utf8() != DISCOVERY_QUERY or sender_address.is_empty() or sender_port <= 0:
			continue
		var response := {
			"protocol": DISCOVERY_RESPONSE,
			"game_port": int(lobby_settings.get("port", DEFAULT_PORT)),
			"host_name": str(lobby_players.get(1, {}).get("nickname", local_nickname)),
			"players": lobby_players.size(),
			"max_players": MAX_FACTIONS,
			"seed": int(lobby_settings.get("seed", 0)),
			"loaded_game": bool(lobby_settings.get("loaded_game", false)),
			"save_name": str(lobby_settings.get("save_name", "")),
		}
		if _lan_discovery_peer.set_dest_address(sender_address, sender_port) == OK:
			_lan_discovery_peer.put_packet(JSON.stringify(response).to_utf8_buffer())


func _receive_discovery_responses():
	while _lan_discovery_peer.get_available_packet_count() > 0:
		var packet := _lan_discovery_peer.get_packet()
		var sender_address := _lan_discovery_peer.get_packet_ip()
		if packet.size() <= 0 or packet.size() > 4096 or sender_address.is_empty():
			continue
		var parsed = JSON.parse_string(packet.get_string_from_utf8())
		if parsed is not Dictionary or str(parsed.get("protocol", "")) != DISCOVERY_RESPONSE:
			continue
		var game_port := int(parsed.get("game_port", 0))
		var players := int(parsed.get("players", 0))
		var maximum_players := int(parsed.get("max_players", MAX_FACTIONS))
		if game_port < 1024 or game_port > 65535 or players < 1 or maximum_players < players or maximum_players > MAX_FACTIONS:
			continue
		var key := "%s:%d" % [sender_address, game_port]
		var record := {
			"key": key,
			"address": sender_address,
			"port": game_port,
			"host_name": _sanitize_nickname(str(parsed.get("host_name", "Хост"))),
			"players": players,
			"max_players": maximum_players,
			"seed": int(parsed.get("seed", 0)),
			"loaded_game": bool(parsed.get("loaded_game", false)),
			"save_name": str(parsed.get("save_name", "")).strip_edges().left(64),
			"last_seen_msec": Time.get_ticks_msec(),
		}
		var changed := not _discovered_lobbies.has(key) or _discovery_record_changed(_discovered_lobbies[key], record)
		_discovered_lobbies[key] = record
		if changed:
			discovered_lobbies_changed.emit(get_discovered_lobbies())


func _discovery_record_changed(previous: Dictionary, current: Dictionary) -> bool:
	for field in ["address", "port", "host_name", "players", "max_players", "seed", "loaded_game", "save_name"]:
		if previous.get(field) != current.get(field):
			return true
	return false


func _expire_discovered_lobbies():
	var now := Time.get_ticks_msec()
	var removed := false
	for key in _discovered_lobbies.keys():
		if now - int(_discovered_lobbies[key].get("last_seen_msec", 0)) > DISCOVERY_LOBBY_TIMEOUT_MSEC:
			_discovered_lobbies.erase(key)
			removed = true
	if removed:
		discovered_lobbies_changed.emit(get_discovered_lobbies())


func consume_menu_notice() -> String:
	var result := menu_notice
	menu_notice = ""
	return result


@rpc("any_peer", "call_remote", "reliable")
func _server_register_player(nickname: String, player_id: String):
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
		"player_id": player_id.strip_edges().left(64),
		"ready": false,
		"join_order": order,
		"requested_faction_id": -1,
		"selected_faction_id": -1,
		"requires_faction_choice": false,
	}
	pending_peers.erase(sender)
	_reconcile_loaded_lobby_assignments()
	_broadcast_lobby_state()


@rpc("any_peer", "call_remote", "reliable")
func _server_set_ready(value: bool):
	if not multiplayer.is_server() or not lobby_active or match_starting:
		return
	_set_player_ready(multiplayer.get_remote_sender_id(), value)


@rpc("any_peer", "call_remote", "reliable")
func _server_choose_loaded_faction(faction_id: int):
	if not multiplayer.is_server() or not lobby_active or match_starting:
		return
	_set_loaded_faction_choice(multiplayer.get_remote_sender_id(), faction_id)


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
func _receive_start_session(raw_slots: Array, settings: Dictionary, saved_world: Dictionary):
	if session_configured:
		return
	_stop_lan_discovery()
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
	var loading_save := bool(lobby_settings.get("loaded_game", false)) and not saved_world.is_empty()
	var save_manager := get_node_or_null("/root/SaveManager")
	if is_instance_valid(save_manager) and loading_save:
		save_manager.pending_save_data = saved_world.duplicate(true)
	_set_world_seed(int(lobby_settings.get("seed", 12345)), not loading_save)
	connection_state_changed.emit("Все готовы. Запуск мира…")
	get_tree().call_deferred("change_scene_to_file", WORLD_SCENE)


@rpc("authority", "call_local", "reliable")
func _receive_session_slots(raw_slots: Array):
	session_slots.clear()
	for raw_slot in raw_slots:
		if raw_slot is Dictionary and session_slots.size() < MAX_FACTIONS:
			session_slots.append(raw_slot.duplicate(true))
	_apply_session_controllers_to_world()


@rpc("any_peer", "call_remote", "reliable")
func _server_request_unit_command(action: StringName, unit_ids: Array, payload: Dictionary):
	if not multiplayer.is_server() or not is_lan_session():
		return
	_handle_server_unit_command(multiplayer.get_remote_sender_id(), action, unit_ids, payload)


@rpc("any_peer", "call_remote", "reliable")
func _server_world_ready():
	if not multiplayer.is_server() or not is_lan_session():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _get_faction_controlled_by_peer(sender) < 0:
		return
	_world_ready_peers[sender] = true
	_send_full_world_state(sender)
	if _all_remote_worlds_ready():
		_authoritative_resource_amounts.clear()


@rpc("authority", "call_remote", "reliable")
func _receive_unit_command(faction_id: int, action: StringName, unit_ids: Array, payload: Dictionary):
	if multiplayer.is_server():
		return
	_apply_unit_command(faction_id, action, unit_ids, payload)


@rpc("any_peer", "call_remote", "reliable")
func _server_request_building_action(network_id: int, action: StringName, payload: Dictionary):
	if not multiplayer.is_server() or not is_lan_session():
		return
	_handle_server_building_action(multiplayer.get_remote_sender_id(), network_id, action, payload)


@rpc("authority", "call_remote", "reliable")
func _receive_building_action(faction_id: int, network_id: int, action: StringName, payload: Dictionary):
	if multiplayer.is_server():
		return
	_apply_building_action(faction_id, network_id, action, payload)


@rpc("any_peer", "call_remote", "reliable")
func _server_request_spawn_buildings(specifications: Array, builder_ids: Array):
	if not multiplayer.is_server() or not is_lan_session():
		return
	_handle_server_spawn_buildings(multiplayer.get_remote_sender_id(), specifications, builder_ids)


@rpc("authority", "call_remote", "reliable")
func _receive_spawn_buildings(specifications: Array, builder_ids: Array):
	if multiplayer.is_server():
		return
	var world := _get_world()
	if is_instance_valid(world) and world.has_method("spawn_network_buildings"):
		world.spawn_network_buildings(specifications, builder_ids)


@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_unit_states(states: Array):
	if multiplayer.is_server():
		return
	var world := _get_world()
	if is_instance_valid(world) and world.has_method("apply_network_unit_states"):
		world.apply_network_unit_states(states)


@rpc("authority", "call_remote", "reliable")
func _receive_building_states(states: Array):
	if multiplayer.is_server():
		return
	var world := _get_world()
	if is_instance_valid(world) and world.has_method("apply_network_building_states"):
		world.apply_network_building_states(states)


@rpc("authority", "call_remote", "reliable")
func _receive_resource_amount(record_id: int, amount: int):
	if multiplayer.is_server():
		return
	var world := _get_world()
	if not is_instance_valid(world):
		return
	var lod_manager := world.get_node_or_null("SimulationLODManager")
	if is_instance_valid(lod_manager) and lod_manager.has_method("update_resource_amount"):
		lod_manager.update_resource_amount(record_id, amount)


@rpc("authority", "call_remote", "reliable")
func _receive_resource_states(states: Array):
	if multiplayer.is_server():
		return
	var world := _get_world()
	if not is_instance_valid(world):
		return
	var lod_manager := world.get_node_or_null("SimulationLODManager")
	if not is_instance_valid(lod_manager) or not lod_manager.has_method("update_resource_amount"):
		return
	for state in states:
		if state is Dictionary:
			lod_manager.update_resource_amount(int(state.get("record_id", 0)), int(state.get("amount", 0)))


func _handle_server_unit_command(sender_peer_id: int, action: StringName, raw_unit_ids: Array, payload: Dictionary):
	var faction_id := _get_faction_controlled_by_peer(sender_peer_id)
	if faction_id < 0 or raw_unit_ids.is_empty() or raw_unit_ids.size() > MAX_UNITS_PER_COMMAND:
		return
	var accepted_ids: Array[int] = []
	for raw_id in raw_unit_ids:
		var network_id := int(raw_id)
		var unit := _find_unit(network_id, faction_id)
		if not is_instance_valid(unit) or unit.controller_peer_id != sender_peer_id or unit.ai_controlled:
			continue
		accepted_ids.append(network_id)
	if accepted_ids.is_empty() or not _is_valid_unit_command(action, accepted_ids, payload, faction_id):
		return
	_apply_unit_command(faction_id, action, accepted_ids, payload)
	_receive_unit_command.rpc(faction_id, action, accepted_ids, payload)


func _is_valid_unit_command(action: StringName, unit_ids: Array[int], payload: Dictionary, faction_id: int) -> bool:
	match action:
		&"move":
			var destinations: Array = payload.get("destinations", [])
			if destinations.size() != unit_ids.size():
				return false
			var world := _get_world()
			for destination in destinations:
				if destination is not Vector2 or not _is_finite_vector(destination) or (is_instance_valid(world) and world.has_method("is_network_position_valid") and not world.is_network_position_valid(destination)):
					return false
			return true
		&"harvest":
			return _resolve_resource(payload) != null
		&"build", &"enter_building":
			var building := _find_building(int(payload.get("building_id", 0)), faction_id)
			if not is_instance_valid(building):
				return false
			return building.under_construction if action == &"build" else building.is_completed()
		&"build_line":
			var building_ids: Array = payload.get("building_ids", [])
			if building_ids.is_empty() or building_ids.size() > MAX_BUILDINGS_PER_COMMAND:
				return false
			for building_id in building_ids:
				var segment := _find_building(int(building_id), faction_id)
				if not is_instance_valid(segment) or not segment.under_construction:
					return false
			return true
		&"squad_order":
			return StringName(payload.get("order", &"")) in [&"hold", &"spread_out", &"watch_directions", &"regroup", &"return_to_base"]
		_:
			return false


func _apply_unit_command(faction_id: int, action: StringName, unit_ids: Array, payload: Dictionary):
	var units: Array[Unit] = []
	for raw_id in unit_ids:
		var unit := _find_unit(int(raw_id), faction_id)
		if is_instance_valid(unit):
			units.append(unit)
	if units.is_empty():
		return
	match action:
		&"move":
			var destinations: Array = payload.get("destinations", [])
			for index in range(mini(units.size(), destinations.size())):
				if destinations[index] is Vector2:
					units[index].command_move(destinations[index])
		&"harvest":
			var resource := _resolve_resource(payload)
			if is_instance_valid(resource):
				for unit in units:
					unit.command_harvest(resource)
		&"build", &"enter_building":
			var building := _find_building(int(payload.get("building_id", 0)), faction_id)
			if not is_instance_valid(building):
				return
			for unit in units:
				if action == &"build":
					unit.command_build(building)
				else:
					unit.command_enter_building(building)
		&"build_line":
			var segments: Array[Building] = []
			for building_id in payload.get("building_ids", []):
				var segment := _find_building(int(building_id), faction_id)
				if is_instance_valid(segment):
					segments.append(segment)
			for unit in units:
				unit.command_build_line(segments)
		&"squad_order":
			units[0].issue_squad_order(StringName(payload.get("order", &"hold")))


func _handle_server_building_action(sender_peer_id: int, network_id: int, action: StringName, payload: Dictionary):
	var faction_id := _get_faction_controlled_by_peer(sender_peer_id)
	var building := _find_building(network_id, faction_id)
	if faction_id < 0 or not is_instance_valid(building) or not _is_valid_building_action(building, action, payload):
		return
	_apply_building_action(faction_id, network_id, action, payload)
	_receive_building_action.rpc(faction_id, network_id, action, payload)


func _is_valid_building_action(building: Building, action: StringName, payload: Dictionary) -> bool:
	match action:
		&"storage_limit":
			return building.is_warehouse() and StringName(payload.get("resource_type", &"")) in Building.RESOURCE_TYPES
		&"recipe":
			return building.is_factory() and StringName(payload.get("recipe", &"")) in building.get_available_recipe_types()
		&"worker_target":
			return building.is_factory()
		&"rename_road":
			return building is RoadSegment and not str(payload.get("name", "")).strip_edges().is_empty()
		&"migration_target", &"mobilization_target", &"organize_army":
			return building is GovernmentBuilding
		&"release_occupants", &"dismantle":
			return not building.placement_preview
		_:
			return false


func _apply_building_action(faction_id: int, network_id: int, action: StringName, payload: Dictionary):
	var building := _find_building(network_id, faction_id)
	if not is_instance_valid(building):
		return
	match action:
		&"storage_limit":
			building.set_storage_limit(StringName(payload.get("resource_type", &"wood")), int(payload.get("amount", 0)))
		&"recipe":
			building.set_recipe(StringName(payload.get("recipe", &"planks")))
		&"worker_target":
			building.set_worker_target(int(payload.get("amount", 0)))
		&"rename_road":
			var old_name: String = (building as RoadSegment).street_name
			var new_name := str(payload.get("name", old_name)).strip_edges().left(48)
			for road in get_tree().get_nodes_in_group("roads"):
				if road is RoadSegment and road.faction_id == faction_id and road.street_name == old_name:
					road.set_street_name(new_name)
			for candidate in get_tree().get_nodes_in_group("buildings"):
				if candidate is Building and candidate is not RoadSegment and candidate.faction_id == faction_id:
					candidate.rename_address_street(old_name, new_name)
		&"migration_target":
			(building as GovernmentBuilding).set_migration_target(int(payload.get("amount", 0)))
		&"mobilization_target":
			(building as GovernmentBuilding).set_mobilization_target(int(payload.get("amount", 0)))
		&"organize_army":
			(building as GovernmentBuilding).organize_army()
		&"release_occupants":
			for unit in building.occupants.duplicate():
				if is_instance_valid(unit):
					unit.force_exit_building(building)
		&"dismantle":
			building.dismantle()


func _handle_server_spawn_buildings(sender_peer_id: int, raw_specifications: Array, raw_builder_ids: Array):
	var faction_id := _get_faction_controlled_by_peer(sender_peer_id)
	var world := _get_world()
	if faction_id < 0 or not is_instance_valid(world) or not world.has_method("spawn_network_buildings") or raw_specifications.is_empty() or raw_specifications.size() > MAX_BUILDINGS_PER_COMMAND:
		return
	var specifications: Array = []
	for raw_spec in raw_specifications:
		if raw_spec is not Dictionary:
			continue
		var spec: Dictionary = raw_spec.duplicate(true)
		var kind := str(spec.get("kind", ""))
		var position: Variant = spec.get("position", Vector2.ZERO)
		if kind not in NETWORK_BUILDING_KINDS or position is not Vector2 or not _is_finite_vector(position):
			continue
		if world.has_method("is_network_position_valid") and not world.is_network_position_valid(position):
			continue
		spec["kind"] = kind
		spec["position"] = position
		spec["rotation"] = wrapf(float(spec.get("rotation", 0.0)), -PI, PI)
		spec["faction_id"] = faction_id
		spec["faction_name"] = str(get_faction_slot(faction_id).get("nickname", "Игрок"))
		spec["network_id"] = _allocate_server_entity_id()
		spec["street_name"] = str(spec.get("street_name", "Улица")).strip_edges().left(48)
		spec["address"] = str(spec.get("address", "")).strip_edges().left(96)
		if world.has_method("can_spawn_network_building") and not world.can_spawn_network_building(spec):
			continue
		var overlaps_pending := false
		for accepted_spec in specifications:
			if position.distance_to(accepted_spec.get("position", Vector2.ZERO)) < 8.0:
				overlaps_pending = true
				break
		if overlaps_pending:
			continue
		specifications.append(spec)
	if specifications.is_empty():
		return
	var builder_ids: Array[int] = []
	for raw_id in raw_builder_ids:
		var builder := _find_unit(int(raw_id), faction_id)
		if is_instance_valid(builder) and builder.controller_peer_id == sender_peer_id and not builder.ai_controlled:
			builder_ids.append(builder.network_id)
	world.spawn_network_buildings(specifications, builder_ids)
	_receive_spawn_buildings.rpc(specifications, builder_ids)


func _send_full_world_state(peer_id: int):
	var world := _get_world()
	if not is_instance_valid(world):
		return
	if world.has_method("get_network_unit_states"):
		_receive_unit_states.rpc_id(peer_id, world.get_network_unit_states())
	if world.has_method("get_network_building_states"):
		_receive_building_states.rpc_id(peer_id, world.get_network_building_states())
	if not _authoritative_resource_amounts.is_empty():
		var resource_states: Array = []
		for record_id in _authoritative_resource_amounts:
			resource_states.append({"record_id": int(record_id), "amount": int(_authoritative_resource_amounts[record_id])})
		_receive_resource_states.rpc_id(peer_id, resource_states)


func _all_remote_worlds_ready() -> bool:
	if not is_lan_session():
		return true
	for slot in session_slots:
		var peer_id := int(slot.get("controller_peer_id", 0))
		if bool(slot.get("is_ai", true)) or peer_id <= 1:
			continue
		if not _world_ready_peers.has(peer_id):
			return false
	return true


func _get_faction_controlled_by_peer(peer_id: int) -> int:
	for slot in session_slots:
		if not bool(slot.get("is_ai", true)) and int(slot.get("controller_peer_id", 0)) == peer_id:
			return int(slot.get("faction_id", -1))
	return -1


func _find_unit(network_id: int, faction_id: int) -> Unit:
	var world := _get_world()
	if network_id <= 0 or not is_instance_valid(world):
		return null
	for candidate in get_tree().get_nodes_in_group("units"):
		if candidate is Unit and world.is_ancestor_of(candidate) and candidate.network_id == network_id and candidate.faction_id == faction_id:
			return candidate
	return null


func _find_building(network_id: int, faction_id: int) -> Building:
	var world := _get_world()
	if network_id <= 0 or not is_instance_valid(world):
		return null
	for candidate in get_tree().get_nodes_in_group("buildings"):
		if candidate is Building and world.is_ancestor_of(candidate) and candidate.network_id == network_id and candidate.faction_id == faction_id:
			return candidate
	return null


func _resolve_resource(payload: Dictionary) -> Node2D:
	var world := _get_world()
	if not is_instance_valid(world):
		return null
	var lod_manager := world.get_node_or_null("SimulationLODManager")
	if not is_instance_valid(lod_manager):
		return null
	var record_id := int(payload.get("resource_id", 0))
	if record_id > 0:
		var record: Dictionary = lod_manager._resource_records_by_id.get(record_id, {})
		if not record.is_empty() and int(record.get("amount", 0)) > 0:
			return lod_manager._get_or_materialize_resource(record)
	var position: Variant = payload.get("position", Vector2.ZERO)
	var resource_type := StringName(payload.get("resource_type", &"wood"))
	if position is Vector2 and resource_type in [&"wood", &"stone"]:
		return lod_manager.find_resource_near_position(resource_type, position, 48.0)
	return null


func _allocate_server_entity_id() -> int:
	while _network_entity_id_exists(_next_server_entity_id):
		_next_server_entity_id += 1
	var result := _next_server_entity_id
	_next_server_entity_id += 1
	return result


func _network_entity_id_exists(network_id: int) -> bool:
	for candidate in get_tree().get_nodes_in_group("units"):
		if candidate is Unit and candidate.network_id == network_id:
			return true
	for candidate in get_tree().get_nodes_in_group("buildings"):
		if candidate is Building and candidate.network_id == network_id:
			return true
	return false


func _is_finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y) and absf(value.x) <= 1000000.0 and absf(value.y) <= 1000000.0


func _get_world() -> Node2D:
	var world := get_tree().current_scene
	return world as Node2D if is_instance_valid(world) and world is Node2D and world.has_method("get_network_unit_states") else null


func _set_player_ready(peer_id: int, value: bool):
	if not lobby_players.has(peer_id):
		return
	if value and bool(lobby_players[peer_id].get("requires_faction_choice", false)):
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
	if bool(lobby_settings.get("loaded_game", false)):
		var loaded_slots := _build_loaded_match_slots(ordered_players)
		var loaded_peer := multiplayer.multiplayer_peer
		if loaded_peer != null:
			loaded_peer.refuse_new_connections = true
		_receive_start_session.rpc(_slots_to_array(loaded_slots), lobby_settings.duplicate(true), loaded_world_data.duplicate(true))
		return
	var slots: Array[Dictionary] = []
	for player in ordered_players:
		if slots.size() >= MAX_FACTIONS:
			break
		slots.append(_make_slot(slots.size(), int(player.get("peer_id", 0)), str(player.get("nickname", "Игрок")), false, str(player.get("player_id", ""))))
	var free_slots := MAX_FACTIONS - slots.size()
	var bot_count := mini(int(lobby_settings.get("requested_ai_count", 0)), free_slots)
	for index in range(bot_count):
		slots.append(_make_slot(slots.size(), 0, "ИИ %d" % (index + 1), true))
	var current_peer := multiplayer.multiplayer_peer
	if current_peer != null:
		current_peer.refuse_new_connections = true
	_receive_start_session.rpc(_slots_to_array(slots), lobby_settings.duplicate(true), {})


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
	_world_ready_peers.erase(peer_id)
	if lobby_active and not session_configured:
		if lobby_players.erase(peer_id):
			_reconcile_loaded_lobby_assignments()
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
	_server_register_player.rpc_id(1, local_nickname, local_player_id)


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


func _set_loaded_faction_choice(peer_id: int, faction_id: int):
	if not lobby_players.has(peer_id) or not bool(lobby_settings.get("loaded_game", false)):
		return
	var valid_choice := false
	for slot in lobby_settings.get("saved_slots", []):
		if slot is Dictionary and int(slot.get("faction_id", -1)) == faction_id:
			valid_choice = true
			break
	if not valid_choice:
		return
	lobby_players[peer_id]["requested_faction_id"] = faction_id
	lobby_players[peer_id]["ready"] = false
	_reconcile_loaded_lobby_assignments()
	_broadcast_lobby_state()


func _reconcile_loaded_lobby_assignments():
	if not bool(lobby_settings.get("loaded_game", false)):
		return
	var saved_slots: Array = lobby_settings.get("saved_slots", [])
	var players: Array = lobby_players.values()
	players.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("join_order", 0)) < int(b.get("join_order", 0)))
	var previous := {}
	for player in players:
		var peer_id := int(player.get("peer_id", 0))
		previous[peer_id] = int(player.get("selected_faction_id", -1))
		player["selected_faction_id"] = -1
		player["requires_faction_choice"] = false
		player["owns_saved_faction"] = false
	var claimed := {}
	# Сначала безусловно возвращаем прежним владельцам их государства.
	for player in players:
		var owned_faction := _find_owned_faction_in_slots(saved_slots, str(player.get("player_id", "")), str(player.get("nickname", "Игрок")))
		if owned_faction < 0 or claimed.has(owned_faction):
			continue
		player["selected_faction_id"] = owned_faction
		player["owns_saved_faction"] = true
		claimed[owned_faction] = true
		for slot in saved_slots:
			if slot is Dictionary and int(slot.get("faction_id", -1)) == owned_faction and str(slot.get("owner_id", "")).is_empty():
				slot["owner_id"] = str(player.get("player_id", ""))
	# Затем сохраняем свободные ручные выборы игроков без прежней фракции.
	for player in players:
		if int(player.get("selected_faction_id", -1)) >= 0:
			continue
		var requested := int(player.get("requested_faction_id", -1))
		if requested >= 0 and not claimed.has(requested) and _slots_have_faction(saved_slots, requested):
			player["selected_faction_id"] = requested
			claimed[requested] = true
	# Несуществующие в сохранении фракции являются настоящими свободными местами.
	for player in players:
		if int(player.get("selected_faction_id", -1)) >= 0:
			continue
		for faction_id in range(MAX_FACTIONS):
			if claimed.has(faction_id) or _slots_have_faction(saved_slots, faction_id):
				continue
			player["selected_faction_id"] = faction_id
			claimed[faction_id] = true
			break
	for player in players:
		var peer_id := int(player.get("peer_id", 0))
		var selected := int(player.get("selected_faction_id", -1))
		player["requires_faction_choice"] = selected < 0
		if int(previous.get(peer_id, -1)) != selected:
			player["ready"] = false
	lobby_settings["saved_slots"] = saved_slots


func _build_loaded_match_slots(players: Array) -> Array[Dictionary]:
	var result := _normalize_saved_slots(lobby_settings.get("saved_slots", []))
	for index in range(result.size()):
		result[index]["controller_peer_id"] = 0
		result[index]["is_ai"] = true
		result[index]["nickname"] = _ai_display_name(str(result[index].get("nickname", "ИИ")))
	for player in players:
		var faction_id := int(player.get("selected_faction_id", -1))
		if faction_id < 0:
			continue
		var player_slot := _make_slot(faction_id, int(player.get("peer_id", 0)), str(player.get("nickname", "Игрок")), false, str(player.get("player_id", "")))
		var replaced := false
		for index in range(result.size()):
			if int(result[index].get("faction_id", -1)) == faction_id:
				result[index] = player_slot
				replaced = true
				break
		if not replaced:
			result.append(player_slot)
	result.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("faction_id", 0)) < int(b.get("faction_id", 0)))
	return result


func _normalize_saved_slots(raw_slots: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var used_factions := {}
	for raw_slot in raw_slots:
		if raw_slot is not Dictionary or result.size() >= MAX_FACTIONS:
			continue
		var faction_id := clampi(int(raw_slot.get("faction_id", result.size())), 0, MAX_FACTIONS - 1)
		if used_factions.has(faction_id):
			continue
		used_factions[faction_id] = true
		result.append(_make_slot(
			faction_id,
			int(raw_slot.get("controller_peer_id", 0)),
			str(raw_slot.get("nickname", "ИИ %d" % (faction_id + 1))),
			bool(raw_slot.get("is_ai", true)),
			str(raw_slot.get("owner_id", ""))
		))
	result.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("faction_id", 0)) < int(b.get("faction_id", 0)))
	return result


func _infer_saved_slots(world_data: Dictionary, known_slots: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in known_slots:
		result.append(slot.duplicate(true))
	var inferred_names := {}
	for unit_data in world_data.get("units", []):
		if unit_data is Dictionary:
			var faction_id := clampi(int(unit_data.get("faction_id", 0)), 0, MAX_FACTIONS - 1)
			inferred_names[faction_id] = str(unit_data.get("faction_name", "ИИ %d" % (faction_id + 1)))
	for building_data in world_data.get("buildings", []):
		if building_data is Dictionary:
			var faction_id := clampi(int(building_data.get("faction_id", 0)), 0, MAX_FACTIONS - 1)
			if not inferred_names.has(faction_id):
				inferred_names[faction_id] = "ИИ %d" % (faction_id + 1)
	for faction_id in inferred_names:
		if _slots_have_faction(result, int(faction_id)):
			continue
		var nickname := str(inferred_names[faction_id])
		var looked_human := not nickname.begins_with("ИИ ")
		result.append(_make_slot(int(faction_id), 0, nickname, not looked_human, ""))
	result.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("faction_id", 0)) < int(b.get("faction_id", 0)))
	return result


func _find_owned_faction_in_slots(slots: Array, player_id: String, nickname: String) -> int:
	if not player_id.is_empty():
		for slot in slots:
			if slot is Dictionary and str(slot.get("owner_id", "")) == player_id:
				return int(slot.get("faction_id", -1))
	var clean_nickname := _base_owner_nickname(nickname).to_lower()
	for slot in slots:
		if slot is not Dictionary or not str(slot.get("owner_id", "")).is_empty():
			continue
		var saved_nickname := str(slot.get("nickname", ""))
		var was_human := not bool(slot.get("is_ai", true)) or saved_nickname.ends_with(" (ИИ)")
		if was_human and _base_owner_nickname(saved_nickname).to_lower() == clean_nickname:
			return int(slot.get("faction_id", -1))
	return -1


func _slots_have_faction(slots: Array, faction_id: int) -> bool:
	for slot in slots:
		if slot is Dictionary and int(slot.get("faction_id", -1)) == faction_id:
			return true
	return false


func _base_owner_nickname(value: String) -> String:
	var result := value.strip_edges()
	while result.ends_with(" (ИИ)"):
		result = result.trim_suffix(" (ИИ)").strip_edges()
	return result


func _ai_display_name(value: String) -> String:
	var base := _base_owner_nickname(value)
	return base if base.begins_with("ИИ ") else "%s (ИИ)" % base


func _make_slot(faction_id: int, controller_peer_id: int, nickname: String, is_ai: bool, owner_id := "") -> Dictionary:
	return {
		"faction_id": faction_id,
		"controller_peer_id": controller_peer_id,
		"nickname": nickname,
		"is_ai": is_ai,
		"owner_id": owner_id,
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


func _set_world_seed(seed_value: int, clear_pending_save := true):
	var save_manager := get_node_or_null("/root/SaveManager")
	if is_instance_valid(save_manager):
		save_manager.current_seed = seed_value
		if clear_pending_save:
			save_manager.pending_save_data.clear()
	get_tree().paused = false


func _reset_runtime_state():
	lobby_players.clear()
	pending_peers.clear()
	lobby_settings = {"seed": 12345, "requested_ai_count": 0, "port": DEFAULT_PORT, "loaded_game": false, "saved_slots": []}
	loaded_world_data.clear()
	session_slots.clear()
	lobby_active = false
	session_configured = false
	lan_session = false
	hosting = false
	match_starting = false
	connection_pending = false
	join_order_counter = 0
	_unit_state_sync_accumulator = 0.0
	_building_state_sync_accumulator = 0.0
	_next_server_entity_id = SERVER_ENTITY_ID_START
	_authoritative_resource_amounts.clear()
	_world_ready_peers.clear()


func _load_profile():
	var config := ConfigFile.new()
	if config.load(PROFILE_PATH) == OK:
		local_nickname = _sanitize_nickname(str(config.get_value("player", "nickname", "Игрок")))
		local_player_id = str(config.get_value("player", "id", ""))
	if local_player_id.is_empty():
		local_player_id = Crypto.new().generate_random_bytes(16).hex_encode()
		_save_profile()


func _save_profile():
	var config := ConfigFile.new()
	config.set_value("player", "nickname", local_nickname)
	config.set_value("player", "id", local_player_id)
	config.save(PROFILE_PATH)
