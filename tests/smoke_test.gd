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
	print("SMOKE_TEST_OK")
	quit()
