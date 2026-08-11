extends SceneTree


func _init():
	call_deferred("_run")


func _run():
	var network_manager = root.get_node("NetworkManager")
	network_manager.shutdown_network()
	network_manager.session_configured = true
	network_manager.lan_session = true
	network_manager.hosting = true
	network_manager.session_slots.clear()
	network_manager.session_slots.append({"faction_id": 0, "controller_peer_id": 1, "nickname": "Хост", "is_ai": false, "owner_id": "host"})
	network_manager.session_slots.append({"faction_id": 1, "controller_peer_id": 7, "nickname": "Клиент", "is_ai": false, "owner_id": "client"})

	var world = preload("res://scripts/land/generation.gd").new()
	world.generate_world_on_ready = false
	for node_name in ["ground", "trees", "rocks", "roads", "buildings"]:
		var container := Node2D.new()
		container.name = node_name
		world.add_child(container)
	root.add_child(world)
	current_scene = world
	await process_frame

	var host_unit := _spawn_unit(world, 1001, 0, 1, Vector2(100, 100))
	var client_unit := _spawn_unit(world, 2001, 1, 7, Vector2(200, 100))
	await process_frame

	network_manager._handle_server_unit_command(7, &"move", [client_unit.network_id], {"destinations": [Vector2(420, 180)]})
	assert(client_unit.task == Unit.Task.MOVE)
	assert(client_unit.target_position.distance_to(Vector2(420, 180)) < 0.01)
	var accepted_target := client_unit.target_position
	network_manager._handle_server_unit_command(7, &"move", [client_unit.network_id], {"destinations": [Vector2(13000, 13000)]})
	assert(client_unit.target_position == accepted_target)

	var host_target_before := host_unit.target_position
	network_manager._handle_server_unit_command(7, &"move", [host_unit.network_id], {"destinations": [Vector2(900, 900)]})
	assert(host_unit.target_position == host_target_before)
	assert(host_unit.task == Unit.Task.IDLE)

	var road := preload("res://scenes/objects/buildings/road.tscn").instantiate() as RoadSegment
	road.faction_id = 1
	road.faction_name = "Клиент"
	road.network_id = 5001
	road.position = Vector2(300, 300)
	world.get_node("roads").add_child(road)
	road.setup("Тестовая", 0.0)
	road.under_construction = false
	await physics_frame

	var building_count_before := get_nodes_in_group("buildings").size()
	network_manager._handle_server_spawn_buildings(7, [{
		"kind": "residence",
		"position": Vector2(300, 260),
		"rotation": PI,
		"street_name": "Тестовая",
		"address": "Тестовая, 1",
	}], [client_unit.network_id])
	await process_frame
	assert(get_nodes_in_group("buildings").size() == building_count_before + 1)
	var spawned := _find_building(world, 1, "residence")
	assert(is_instance_valid(spawned))
	assert(spawned.network_id >= network_manager.SERVER_ENTITY_ID_START)
	assert(spawned.under_construction)
	assert(client_unit.task == Unit.Task.BUILD)
	assert(client_unit.target_building == spawned)

	network_manager._handle_server_building_action(7, road.network_id, &"rename_road", {"name": "Сетевая"})
	assert(road.street_name == "Сетевая")
	var unit_states: Array = world.get_network_unit_states()
	var building_states: Array = world.get_network_building_states()
	world.apply_network_unit_states(unit_states)
	world.apply_network_building_states(building_states)
	assert(client_unit.network_position_target.distance_to(client_unit.global_position) < 0.01)
	assert(spawned.address == "Тестовая, 1")

	print("NETWORK_AUTHORITY_TEST_OK")
	world.queue_free()
	await process_frame
	network_manager.shutdown_network()
	quit()


func _spawn_unit(world: Node2D, network_id: int, faction_id: int, controller_peer_id: int, position: Vector2) -> Unit:
	var unit := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
	unit.network_id = network_id
	unit.position = position
	unit.configure_faction(faction_id, controller_peer_id, false, "Фракция %d" % faction_id)
	world.add_child(unit)
	return unit


func _find_building(world: Node2D, faction_id: int, kind: String) -> Building:
	for candidate in get_nodes_in_group("buildings"):
		if candidate is Building and world.is_ancestor_of(candidate) and candidate.faction_id == faction_id and candidate.building_kind == kind:
			return candidate
	return null
