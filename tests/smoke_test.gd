extends SceneTree


func _init():
	call_deferred("_run")


func _run():
	var test_root := Node2D.new()
	root.add_child(test_root)
	var warehouse := preload("res://scenes/objects/buildings/warehouse.tscn").instantiate() as Building
	var factory := preload("res://scenes/objects/buildings/fabric.tscn").instantiate() as Building
	var food_factory := preload("res://scenes/objects/buildings/food_fabric.tscn").instantiate() as Building
	var mine := preload("res://scenes/objects/buildings/mine.tscn").instantiate() as Building
	var power_plant := preload("res://scenes/objects/buildings/power_plant.tscn").instantiate() as Building
	var residence := preload("res://scenes/objects/buildings/residence.tscn").instantiate() as Building
	test_root.add_child(warehouse)
	test_root.add_child(factory)
	test_root.add_child(food_factory)
	test_root.add_child(mine)
	test_root.add_child(power_plant)
	test_root.add_child(residence)
	assert(residence.max_occupants == 8)
	assert(factory.max_workers == 5)
	assert(food_factory.max_workers == 5)
	assert(mine.max_workers == 5)
	assert(power_plant.max_workers == 2)
	assert(power_plant.electricity_capacity == 20)
	assert(warehouse.storage_capacity == 300)
	assert(warehouse.get_total_stored() == 0)
	assert(warehouse.store_resource(&"wood", 10) == 10)
	assert(warehouse.store_resource(&"stone", 10) == 10)
	assert(factory.can_produce_selected_recipe())
	assert(factory.produce_selected_recipe())
	assert(warehouse.get_stored_resource(&"wood") == 8)
	assert(warehouse.get_stored_resource(&"planks") == 1)
	factory.set_recipe(&"tools")
	assert(factory.produce_selected_recipe())
	assert(warehouse.get_stored_resource(&"tools") == 1)
	assert(food_factory.is_food_factory())
	assert(food_factory.selected_recipe == &"food")
	food_factory.set_recipe(&"tools")
	assert(food_factory.selected_recipe == &"food")
	assert(food_factory.produce_selected_recipe())
	assert(warehouse.get_stored_resource(&"food") == 1)
	assert(mine.is_mine())
	assert(mine.selected_recipe == &"mine_stone")
	assert(is_equal_approx(mine.get_production_time(), 3.0))
	assert(mine.produce_selected_recipe())
	mine.set_recipe(&"mine_coal")
	assert(mine.produce_selected_recipe())
	mine.set_recipe(&"mine_both")
	assert(is_equal_approx(mine.get_production_time(), 6.0))
	assert(mine.produce_selected_recipe())
	assert(warehouse.get_stored_resource(&"stone") == 10)
	assert(warehouse.get_stored_resource(&"coal") == 2)
	assert(warehouse.store_resource(&"coal", 8) == 8)
	assert(power_plant.is_power_plant())
	assert(power_plant.selected_recipe == &"electricity")
	assert(power_plant.produce_selected_recipe())
	assert(power_plant.stored_electricity == 4)
	assert(warehouse.get_stored_resource(&"coal") == 9)
	for production_cycle in range(4):
		assert(power_plant.produce_selected_recipe())
	assert(power_plant.stored_electricity == power_plant.electricity_capacity)
	assert(not power_plant.can_produce_selected_recipe())
	assert(power_plant.take_electricity(6) == 6)
	assert(power_plant.stored_electricity == 14)
	var label_worker := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
	test_root.add_child(label_worker)
	assert(factory.try_enter(label_worker))
	factory._process(0.0)
	assert(factory.status_label.text.is_empty())
	assert(not factory.status_label.visible)
	factory.leave(label_worker)
	assert(food_factory.try_enter(label_worker))
	food_factory._process(0.0)
	assert(food_factory.status_label.text.is_empty())
	assert(not food_factory.status_label.visible)
	food_factory.leave(label_worker)
	assert(factory.try_enter(label_worker))
	label_worker.inside_building = factory
	label_worker.target_building = factory
	label_worker.task = Unit.Task.FACTORY_WORK
	label_worker.production_timer = 0.0
	factory.set_recipe(&"tools")
	label_worker._process_factory_work(3.0)
	assert(label_worker.inside_building == factory)
	assert(label_worker.task == Unit.Task.FACTORY_WORK)
	assert(is_equal_approx(label_worker.production_timer, 1.0))
	factory.set_worker_target(0)
	assert(factory.get_worker_target() == 0)
	assert(label_worker.inside_building == null)
	assert(factory.occupants.is_empty())
	factory.set_worker_target(5)
	var reserved_worker := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
	test_root.add_child(reserved_worker)
	reserved_worker.command_enter_building(factory)
	assert(label_worker._get_reserved_entry_count(factory) == 1)
	var previous_factory_capacity := factory.max_workers
	factory.max_workers = 1
	assert(label_worker._find_available_factory() != factory)
	factory.max_workers = previous_factory_capacity
	var move_waiter := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
	test_root.add_child(move_waiter)
	move_waiter.command_move(Vector2(600, 600))
	move_waiter.global_position = move_waiter.target_position
	move_waiter.path_points = PackedVector2Array()
	move_waiter._physics_process(0.1)
	assert(move_waiter.task == Unit.Task.IDLE)
	assert(is_equal_approx(move_waiter.idle_check_timer, Unit.AUTO_WORK_DELAY_AFTER_MANUAL_ORDER))
	move_waiter._process_idle(4.9)
	assert(move_waiter.task == Unit.Task.IDLE)
	move_waiter._process_idle(0.2)
	assert(move_waiter.task != Unit.Task.IDLE)
	var migration_world := Node2D.new()
	root.add_child(migration_world)
	var migration_buildings := Node2D.new()
	migration_buildings.name = "buildings"
	migration_world.add_child(migration_buildings)
	var migrant_home := preload("res://scenes/objects/buildings/residence.tscn").instantiate() as Building
	migrant_home.faction_id = 3
	migration_buildings.add_child(migrant_home)
	var government := preload("res://scenes/objects/buildings/government.tscn").instantiate() as GovernmentBuilding
	government.faction_id = 3
	migration_buildings.add_child(government)
	government.set_migration_target(20)
	assert(government.get_total_residence_count() == 1)
	assert(government.get_housing_capacity() == 8)
	for attempt in range(10):
		government._attempt_migration()
	assert(government.get_population_count() == 8)
	assert(government.get_free_housing() == 0)
	assert(migrant_home.occupants.size() == 8)
	assert(migrant_home.occupants.all(func(migrant): return migrant.inside_building == migrant_home))
	assert(not government._attempt_migration())
	migration_world.queue_free()
	await process_frame
	warehouse.set_storage_limit(&"wood", 0)
	assert(not warehouse.has_resource_space(&"wood"))
	warehouse.set_storage_limit(&"planks", 300)
	assert(warehouse.get_total_storage_limits() <= warehouse.storage_capacity)
	var unit := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
	test_root.add_child(unit)
	assert(not unit.unit_name.is_empty())
	assert(unit.health == unit.max_health)
	unit.food_timer = 0.0
	unit._process_food_needs(0.1)
	assert(warehouse.get_stored_resource(&"food") == 0)
	assert(unit.health == unit.max_health)
	assert(unit.missed_meals == 0)
	unit.food_timer = 0.0
	unit._process_food_needs(0.1)
	assert(unit.health == unit.max_health - Unit.STARVATION_DAMAGE)
	assert(unit.missed_meals == 1)
	assert(residence.try_enter(unit))
	residence.leave(unit)
	unit.global_position = residence.get_approach_position(unit.global_position)
	unit.command_enter_building(residence)
	for frame in range(20):
		await physics_frame
		if unit.inside_building == residence:
			break
	assert(unit.inside_building == residence)
	assert(unit.task == Unit.Task.REST)
	unit.force_exit_building(residence)
	assert(unit.inside_building == null)
	assert(unit.task == Unit.Task.IDLE)
	assert(is_equal_approx(unit.idle_check_timer, Unit.AUTO_WORK_DELAY_AFTER_MANUAL_ORDER))
	unit.command_move(Vector2(500, 500))
	assert(unit.inside_building == null)
	assert(unit.visible)
	unit.command_enter_building(factory)
	assert(unit.get_profession_text() == "Рабочий завода")
	unit.command_move(Vector2(500, 500))
	var construction := preload("res://scenes/objects/buildings/residence.tscn").instantiate() as Building
	construction.global_position = Vector2(700, 700)
	test_root.add_child(construction)
	var trapped_unit := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
	trapped_unit.global_position = construction.global_position
	test_root.add_child(trapped_unit)
	construction.begin_construction()
	assert(construction.building_sprite.modulate.a < 1.0)
	assert(construction.contains_world_point(trapped_unit.global_position))
	trapped_unit.command_move(Vector2(900, 700))
	for frame in range(50):
		await physics_frame
	assert(not construction.contains_world_point(trapped_unit.global_position))
	construction.deliver_resource(&"wood", 100)
	construction.add_build_progress(construction.build_time + 1.0)
	assert(is_equal_approx(construction.building_sprite.modulate.a, 1.0))

	var rotation_world := Node2D.new()
	root.add_child(rotation_world)
	var rotation_buildings := Node2D.new()
	rotation_buildings.name = "buildings"
	rotation_world.add_child(rotation_buildings)
	var rotation_roads := Node2D.new()
	rotation_roads.name = "roads"
	rotation_world.add_child(rotation_roads)
	var road_navigation := WorldNavigation.new()
	road_navigation.name = "WorldNavigation"
	rotation_world.add_child(road_navigation)
	var build_manager = preload("res://scripts/controls/build_manager.gd").new()
	rotation_world.add_child(build_manager)
	assert(build_manager.build_buttons.size() == 11)
	for build_button in build_manager.build_buttons:
		assert(build_button.icon != null)
		assert(build_button.alignment == HORIZONTAL_ALIGNMENT_LEFT)
	build_manager._begin_building_placement(preload("res://scenes/objects/buildings/residence.tscn"))
	assert(build_manager.ghost.placement_preview)
	assert(not build_manager.ghost.is_completed())
	assert(not build_manager.ghost.try_enter(unit))
	build_manager._cancel_building_placement()
	var road := preload("res://scenes/objects/buildings/road.tscn").instantiate() as RoadSegment
	road.global_position = Vector2(1100, 1100)
	rotation_roads.add_child(road)
	road.setup("Тестовая", 0.0)
	build_manager.road_start_segment = road
	assert(build_manager._road_name_for_start(Vector2.RIGHT) == "Тестовая")
	var branch_street_name: String = build_manager._road_name_for_start(Vector2.DOWN)
	assert(branch_street_name != "Тестовая")
	var road_walker := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
	road_walker.global_position = road.global_position
	rotation_world.add_child(road_walker)
	await physics_frame
	assert(road_walker._is_on_completed_road())
	road_walker._update_road_movement_state(1.0)
	assert(road_walker.is_on_road)
	assert(is_equal_approx(road_walker._get_current_movement_speed(), road_walker.speed * Unit.ROAD_SPEED_MULTIPLIER))
	road_navigation.invalidate()
	road_navigation._ensure_grid()
	assert(road_navigation._grid.get_point_weight_scale(road_navigation.world_to_cell(road.global_position)) < 1.0)
	var endpoint_snap: Dictionary = build_manager._nearest_road_endpoint(Vector2(1131, 1102), 40.0)
	assert(endpoint_snap.road == road)
	assert(endpoint_snap.position.is_equal_approx(Vector2(1132, 1100)))
	assert(endpoint_snap.outward_direction.is_equal_approx(Vector2.RIGHT))
	build_manager.road_start_segment = road
	build_manager.road_start_direction = endpoint_snap.outward_direction
	var continued_end: Vector2 = build_manager._snap_road_end(endpoint_snap.position, Vector2(1230, 1115))
	assert(is_equal_approx(continued_end.y, 1100.0))
	assert(continued_end.x > endpoint_snap.position.x)
	assert(not build_manager._road_line_has_parallel_conflict(endpoint_snap.position, Vector2(1196, 1100)))
	assert(build_manager._road_segment_overlaps_existing(Vector2(1100, 1159), 0.0))
	assert(not build_manager._road_segment_overlaps_existing(Vector2(1100, 1160), 0.0))
	assert(not build_manager._road_segment_overlaps_existing(Vector2(1164, 1100), 0.0))
	assert(not build_manager._road_segment_overlaps_existing(Vector2(1100, 1100), PI * 0.5))
	var same_street_segment := preload("res://scenes/objects/buildings/road.tscn").instantiate() as RoadSegment
	same_street_segment.position = Vector2(1164, 1100)
	rotation_roads.add_child(same_street_segment)
	same_street_segment.setup("Тестовая", 0.0)
	var addressed_building := preload("res://scenes/objects/buildings/residence.tscn").instantiate() as Building
	addressed_building.position = Vector2(1100, 1040)
	rotation_buildings.add_child(addressed_building)
	addressed_building.set_address("Тестовая", 7)
	build_manager._open_building_menu(road)
	assert(build_manager.road_settings.visible)
	assert(build_manager.road_name_input.text == "Тестовая")
	build_manager.road_name_input.text = "Портовая"
	build_manager._on_road_rename_requested()
	assert(road.street_name == "Портовая")
	assert(same_street_segment.street_name == "Портовая")
	assert("Портовая, 7" in addressed_building.address)
	assert(road.hover_label.text == "Портовая")
	build_manager._close_building_menu()
	var crew_road_a := preload("res://scenes/objects/buildings/road.tscn").instantiate() as RoadSegment
	var crew_road_b := preload("res://scenes/objects/buildings/road.tscn").instantiate() as RoadSegment
	crew_road_a.position = Vector2(1300, 1100)
	crew_road_b.position = Vector2(1364, 1100)
	rotation_roads.add_child(crew_road_a)
	rotation_roads.add_child(crew_road_b)
	crew_road_a.begin_construction()
	crew_road_b.begin_construction()
	var crew_a := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
	var crew_b := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
	rotation_world.add_child(crew_a)
	rotation_world.add_child(crew_b)
	crew_a.command_build_line([crew_road_a, crew_road_b])
	crew_b.command_build_line([crew_road_a, crew_road_b])
	assert(crew_a.target_building != crew_b.target_building)
	crew_a.carried_stone = 2
	assert(crew_b._get_collection_target(&"stone") == 1)
	var rotating_building := preload("res://scenes/objects/buildings/residence.tscn").instantiate() as Building
	rotation_buildings.add_child(rotating_building)
	build_manager.ghost = rotating_building
	build_manager._snap_building_to_road(Vector2(1100, 1050))
	assert(is_zero_approx(rotating_building.rotation))
	build_manager._snap_building_to_road(Vector2(1100, 1150))
	assert(is_equal_approx(absf(rotating_building.rotation), PI))
	build_manager.building_rotation_offset = PI * 0.5
	build_manager._snap_building_to_road(Vector2(1100, 1150))
	assert(is_equal_approx(absf(rotating_building.rotation), PI * 0.5))
	build_manager.ghost = null
	build_manager._open_building_menu(rotating_building)
	assert(Building.selected_building == rotating_building)
	assert(build_manager.building_panel.visible)
	assert(build_manager.residents_settings.visible)
	build_manager._close_building_menu()
	assert(not build_manager.building_panel.visible)
	await physics_frame
	assert(build_manager._try_open_building_menu(rotating_building.global_position))
	assert(Building.selected_building == rotating_building)
	build_manager._close_building_menu()
	assert(not factory.get_factory_status_text().is_empty())
	build_manager._open_building_menu(factory)
	assert(build_manager.factory_settings.visible)
	assert(int(build_manager.factory_worker_target_input.value) == factory.get_worker_target())
	build_manager._on_factory_worker_target_changed(3.0)
	assert(factory.get_worker_target() == 3)
	factory.set_worker_target(5)
	build_manager._close_building_menu()
	rotation_world.queue_free()

	var save_world := _make_minimal_world()
	var saved_warehouse := preload("res://scenes/objects/buildings/warehouse.tscn").instantiate() as Building
	saved_warehouse.position = Vector2(120, 240)
	save_world.get_node("buildings").add_child(saved_warehouse)
	saved_warehouse.store_resource(&"wood", 25)
	saved_warehouse.store_resource(&"food", 8)
	saved_warehouse.store_resource(&"coal", 6)
	var saved_government := preload("res://scenes/objects/buildings/government.tscn").instantiate() as GovernmentBuilding
	saved_government.position = Vector2(220, 240)
	saved_government.migration_target = 12
	save_world.get_node("buildings").add_child(saved_government)
	var saved_factory := preload("res://scenes/objects/buildings/fabric.tscn").instantiate() as Building
	saved_factory.position = Vector2(320, 240)
	save_world.get_node("buildings").add_child(saved_factory)
	saved_factory.set_worker_target(2)
	var saved_mine := preload("res://scenes/objects/buildings/mine.tscn").instantiate() as Building
	saved_mine.position = Vector2(420, 240)
	save_world.get_node("buildings").add_child(saved_mine)
	saved_mine.set_recipe(&"mine_both")
	var saved_power_plant := preload("res://scenes/objects/buildings/power_plant.tscn").instantiate() as Building
	saved_power_plant.position = Vector2(520, 240)
	save_world.get_node("buildings").add_child(saved_power_plant)
	saved_power_plant.stored_electricity = 12
	saved_power_plant.set_worker_target(1)
	var saved_unit := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
	saved_unit.unit_name = "Тестовый житель"
	saved_unit.position = Vector2(300, 320)
	saved_unit.food_timer = 12.5
	saved_unit.missed_meals = 1
	save_world.add_child(saved_unit)
	var saved_tree = preload("res://scenes/objects/tree.tscn").instantiate()
	saved_tree.position = Vector2(420, 440)
	saved_tree.wood_amount = 7
	save_world.get_node("trees").add_child(saved_tree)
	var save_manager := root.get_node("SaveManager")
	var network_manager := root.get_node("NetworkManager")
	network_manager.prepare_singleplayer(24680, 0)
	assert(network_manager.get_session_slots().size() == 1)
	network_manager.prepare_singleplayer(24680, 1)
	assert(network_manager.get_session_slots().size() == 2)
	assert(str(network_manager.get_session_slots()[0].owner_id) == network_manager.local_player_id)
	var test_save_name := "__sovereign_smoke_test__"
	assert(save_manager.save_game(test_save_name, save_world).is_empty())
	var saved_entry: Dictionary = {}
	for entry in save_manager.list_saves():
		if entry.get("name", "") == test_save_name:
			saved_entry = entry
			break
	assert(not saved_entry.is_empty())
	var saved_file: Dictionary = save_manager._read_save(str(saved_entry.path))
	assert(saved_file.world.buildings.size() == 5)
	assert(saved_file.world.units.size() == 1)
	assert(saved_file.world.resources.size() == 1)
	assert(saved_file.world.session_slots.size() == 2)
	assert(str(saved_file.world.session_slots[0].owner_id) == network_manager.local_player_id)
	assert(saved_file.world.buildings[0].stored.food == 8)
	assert(saved_file.world.buildings[0].stored.coal == 6)
	assert(is_equal_approx(float(saved_file.world.units[0].food_timer), 12.5))
	var restored_world := _make_minimal_world()
	restored_world.apply_save_data(saved_file.world)
	assert(restored_world.get_node("buildings").get_child_count() == 5)
	assert(restored_world.get_node("trees").get_child_count() == 1)
	var restored_units := restored_world.get_tree().get_nodes_in_group("units").filter(func(candidate): return restored_world.is_ancestor_of(candidate) and candidate.unit_name == "Тестовый житель")
	assert(restored_units.size() == 1)
	assert(is_equal_approx(restored_units[0].food_timer, 12.5))
	assert(restored_units[0].missed_meals == 1)
	var restored_warehouse := restored_world.get_node("buildings").get_child(0) as Building
	assert(restored_warehouse.get_stored_resource(&"food") == 8)
	assert(restored_warehouse.get_stored_resource(&"coal") == 6)
	var restored_governments := restored_world.get_node("buildings").get_children().filter(func(candidate): return candidate is GovernmentBuilding)
	assert(restored_governments.size() == 1)
	assert(restored_governments[0].migration_target == 12)
	var restored_factories := restored_world.get_node("buildings").get_children().filter(func(candidate): return candidate is Building and candidate.building_kind == "factory")
	assert(restored_factories.size() == 1)
	assert(restored_factories[0].get_worker_target() == 2)
	var restored_mines := restored_world.get_node("buildings").get_children().filter(func(candidate): return candidate is Building and candidate.is_mine())
	assert(restored_mines.size() == 1)
	assert(restored_mines[0].selected_recipe == &"mine_both")
	var restored_power_plants := restored_world.get_node("buildings").get_children().filter(func(candidate): return candidate is Building and candidate.is_power_plant())
	assert(restored_power_plants.size() == 1)
	assert(restored_power_plants[0].stored_electricity == 12)
	assert(restored_power_plants[0].get_worker_target() == 1)
	var full_saved_slots: Array = [
		network_manager._make_slot(0, 0, "ИИ 1", true, ""),
		network_manager._make_slot(1, 0, "Борис (ИИ)", true, "owner-b"),
		network_manager._make_slot(2, 0, "Анна (ИИ)", true, "owner-a"),
		network_manager._make_slot(3, 0, "ИИ 2", true, ""),
	]
	var inferred_slots: Array[Dictionary] = network_manager._infer_saved_slots({"units": [{"faction_id": 3, "faction_name": "Старое государство"}], "buildings": []}, [])
	assert(inferred_slots.size() == 1)
	assert(int(inferred_slots[0].faction_id) == 3)
	assert(network_manager._find_owned_faction_in_slots([network_manager._make_slot(1, 0, "Старый игрок (ИИ)", true, "")], "unknown-id", "Старый игрок") == 1)
	network_manager.lobby_settings = {"loaded_game": true, "saved_slots": [network_manager._make_slot(0, 0, "Хозяин", false, "owner-host")]}
	network_manager.lobby_players = {
		1: {"peer_id": 1, "nickname": "Хозяин", "player_id": "owner-host", "ready": false, "join_order": 0, "requested_faction_id": -1},
		2: {"peer_id": 2, "nickname": "Свободный игрок", "player_id": "free-owner", "ready": false, "join_order": 1, "requested_faction_id": -1},
	}
	network_manager._reconcile_loaded_lobby_assignments()
	assert(int(network_manager.lobby_players[1].selected_faction_id) == 0)
	assert(int(network_manager.lobby_players[2].selected_faction_id) == 1)
	assert(not bool(network_manager.lobby_players[2].requires_faction_choice))
	network_manager.lobby_settings = {"loaded_game": true, "saved_slots": full_saved_slots}
	network_manager.lobby_players = {
		1: {"peer_id": 1, "nickname": "Анна", "player_id": "owner-a", "ready": false, "join_order": 0, "requested_faction_id": -1},
		2: {"peer_id": 2, "nickname": "Новый игрок", "player_id": "new-owner", "ready": false, "join_order": 1, "requested_faction_id": -1},
	}
	network_manager._reconcile_loaded_lobby_assignments()
	assert(int(network_manager.lobby_players[1].selected_faction_id) == 2)
	assert(not bool(network_manager.lobby_players[1].requires_faction_choice))
	assert(bool(network_manager.lobby_players[2].requires_faction_choice))
	network_manager.lobby_players[2].requested_faction_id = 1
	network_manager._reconcile_loaded_lobby_assignments()
	assert(int(network_manager.lobby_players[2].selected_faction_id) == 1)
	assert(not bool(network_manager.lobby_players[2].requires_faction_choice))
	var replacement_slots: Array[Dictionary] = network_manager._build_loaded_match_slots(network_manager.lobby_players.values())
	assert(str(replacement_slots[1].owner_id) == "new-owner")
	network_manager.lobby_players[3] = {"peer_id": 3, "nickname": "Борис", "player_id": "owner-b", "ready": false, "join_order": 2, "requested_faction_id": -1}
	network_manager._reconcile_loaded_lobby_assignments()
	assert(int(network_manager.lobby_players[3].selected_faction_id) == 1)
	assert(bool(network_manager.lobby_players[2].requires_faction_choice))
	network_manager.shutdown_network()
	assert(save_manager.delete_save(str(saved_entry.path)))
	save_world.queue_free()
	restored_world.queue_free()
	print("SMOKE_TEST_OK")
	quit()


func _make_minimal_world() -> Node2D:
	var minimal_world = preload("res://scripts/land/generation.gd").new()
	minimal_world.generate_world_on_ready = false
	for node_name in ["ground", "trees", "rocks", "roads", "buildings"]:
		var container := Node2D.new()
		container.name = node_name
		minimal_world.add_child(container)
	root.add_child(minimal_world)
	return minimal_world
