extends SceneTree


func _init():
	call_deferred("_run")


func _run():
	var test_root := Node2D.new()
	root.add_child(test_root)
	var warehouse := preload("res://scenes/objects/buildings/warehouse.tscn").instantiate() as Building
	var factory := preload("res://scenes/objects/buildings/fabric.tscn").instantiate() as Building
	var residence := preload("res://scenes/objects/buildings/residence.tscn").instantiate() as Building
	test_root.add_child(warehouse)
	test_root.add_child(factory)
	test_root.add_child(residence)
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
	warehouse.set_storage_limit(&"wood", 0)
	assert(not warehouse.has_resource_space(&"wood"))
	warehouse.set_storage_limit(&"planks", 300)
	assert(warehouse.get_total_storage_limits() <= warehouse.storage_capacity)
	var unit := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
	test_root.add_child(unit)
	assert(not unit.unit_name.is_empty())
	assert(unit.health == unit.max_health)
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
	var build_manager = preload("res://scripts/controls/build_manager.gd").new()
	rotation_world.add_child(build_manager)
	build_manager._begin_building_placement(preload("res://scenes/objects/buildings/residence.tscn"))
	assert(build_manager.ghost.placement_preview)
	assert(not build_manager.ghost.is_completed())
	assert(not build_manager.ghost.try_enter(unit))
	build_manager._cancel_building_placement()
	var road := preload("res://scenes/objects/buildings/road.tscn").instantiate() as RoadSegment
	road.global_position = Vector2(1100, 1100)
	rotation_roads.add_child(road)
	road.setup("Тестовая", 0.0)
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
	rotation_world.queue_free()

	var save_world := _make_minimal_world()
	var saved_warehouse := preload("res://scenes/objects/buildings/warehouse.tscn").instantiate() as Building
	saved_warehouse.position = Vector2(120, 240)
	save_world.get_node("buildings").add_child(saved_warehouse)
	saved_warehouse.store_resource(&"wood", 25)
	var saved_unit := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
	saved_unit.unit_name = "Тестовый житель"
	saved_unit.position = Vector2(300, 320)
	save_world.add_child(saved_unit)
	var saved_tree = preload("res://scenes/objects/tree.tscn").instantiate()
	saved_tree.position = Vector2(420, 440)
	saved_tree.wood_amount = 7
	save_world.get_node("trees").add_child(saved_tree)
	var save_manager := root.get_node("SaveManager")
	save_manager.current_seed = 24680
	var test_save_name := "__sovereign_smoke_test__"
	assert(save_manager.save_game(test_save_name, save_world).is_empty())
	var saved_entry: Dictionary = {}
	for entry in save_manager.list_saves():
		if entry.get("name", "") == test_save_name:
			saved_entry = entry
			break
	assert(not saved_entry.is_empty())
	var saved_file: Dictionary = save_manager._read_save(str(saved_entry.path))
	assert(saved_file.world.buildings.size() == 1)
	assert(saved_file.world.units.size() == 1)
	assert(saved_file.world.resources.size() == 1)
	var restored_world := _make_minimal_world()
	restored_world.apply_save_data(saved_file.world)
	assert(restored_world.get_node("buildings").get_child_count() == 1)
	assert(restored_world.get_node("trees").get_child_count() == 1)
	assert(restored_world.get_tree().get_nodes_in_group("units").any(func(candidate): return restored_world.is_ancestor_of(candidate) and candidate.unit_name == "Тестовый житель"))
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
