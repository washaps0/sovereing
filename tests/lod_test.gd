extends SceneTree


func _init():
	call_deferred("_run")


func _run():
	await _test_coarse_unit_movement()
	await _test_coarse_route_movement()
	await _test_coarse_harvest()
	await _test_lod_catch_up_stays_sliced()
	await _test_local_front_advance()
	await _test_harvester_returns_while_offscreen()
	await _test_offscreen_construction_uses_full_simulation()
	await _test_streamed_world()
	print("LOD_TEST_OK")
	quit()


func _test_coarse_unit_movement():
	var holder := Node2D.new()
	root.add_child(holder)
	var unit := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
	holder.add_child(unit)
	unit.speed = 100.0
	unit.target_position = Vector2(100, 0)
	unit.task = Unit.Task.MOVE
	unit.set_simulation_lod(Unit.SimulationLOD.STRATEGIC, false)
	unit.simulate_lod(0.5)
	assert(is_equal_approx(unit.global_position.x, 50.0))
	assert(unit.task == Unit.Task.MOVE)
	unit.simulate_lod(0.5)
	assert(unit.global_position.distance_to(Vector2(100, 0)) <= 3.01)
	assert(unit.task == Unit.Task.IDLE)
	var stable_position := unit.global_position
	unit.set_simulation_lod(Unit.SimulationLOD.FULL, true)
	assert(unit.global_position == stable_position)
	holder.queue_free()
	await process_frame


func _test_lod_catch_up_stays_sliced():
	var holder := Node2D.new()
	root.add_child(holder)
	var manager := SimulationLODManager.new()
	holder.add_child(manager)
	var unit := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
	holder.add_child(unit)
	unit.ai_controlled = true
	unit.set_simulation_lod(Unit.SimulationLOD.BACKGROUND, false)
	unit.food_timer = 1.0
	manager._clock = 120.0
	unit.lod_last_simulation_time = 0.0
	manager._simulate_pending_time(unit)
	assert(is_equal_approx(unit.lod_last_simulation_time, manager.LOD_CATCH_UP_SLICE * manager.MAX_LOD_CATCH_UP_STEPS))
	assert(unit.missed_meals == 1)
	assert(unit.health == unit.max_health)
	holder.queue_free()
	await process_frame


func _test_coarse_route_movement():
	var holder := Node2D.new()
	root.add_child(holder)
	var unit := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
	holder.add_child(unit)
	unit.speed = 100.0
	unit.target_position = Vector2(100, 0)
	unit.path_destination = unit.target_position
	unit.path_points = PackedVector2Array([Vector2.ZERO, Vector2(50, 50), unit.target_position])
	unit.path_index = 1
	unit.task = Unit.Task.MOVE
	unit.set_simulation_lod(Unit.SimulationLOD.STRATEGIC, false)
	unit.simulate_lod(2.0)
	assert(unit.global_position.distance_to(unit.target_position) <= 3.01)
	assert(unit.task == Unit.Task.IDLE)
	holder.queue_free()
	await process_frame


func _test_local_front_advance():
	var world = preload("res://scripts/land/generation.gd").new()
	world.generate_world_on_ready = false
	root.add_child(world)
	var front: Array[Vector2] = [Vector2(0, 0), Vector2(0, 1000)]
	var offensive: Array[Vector2] = [Vector2(220, 700), Vector2(220, 900)]
	var restored_points := world._coerce_military_line_points([[0.0, 0.0], [0.0, 1000.0]])
	assert(restored_points == front)
	var advanced := world._merge_offensive_into_front(front, offensive)
	assert(advanced.size() >= 12)
	assert(advanced[0].distance_to(front[0]) < 1.0)
	assert(advanced.back().distance_to(front.back()) < 1.0)
	var northern_x := 0.0
	var southern_x := 0.0
	for point in advanced:
		if point.y < 400.0:
			northern_x = maxf(northern_x, point.x)
		if point.y > 700.0 and point.y < 900.0:
			southern_x = maxf(southern_x, point.x)
	assert(northern_x < 1.0)
	assert(southern_x > 180.0)
	for index in range(3):
		var commander := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
		world.add_child(commander)
		commander.faction_id = 0
		commander.is_mobilized = true
		commander.squad_id = index + 1
		commander.platoon_id = 1
		commander.network_id = 100 + index
		commander.squad_commander_network_id = commander.network_id
		commander.military_order = &"front_line"
		commander.target_position = Vector2(0, index * 500.0)
	var local_attackers := world._select_local_offensive_commanders({
		"faction_id": 0,
		"squad_ids": [1, 2, 3],
		"offensive_points": offensive,
	})
	assert(local_attackers.size() == 1)
	assert(local_attackers[0].squad_id == 3)
	world.queue_free()
	await process_frame


func _test_coarse_harvest():
	var holder := Node2D.new()
	root.add_child(holder)
	var unit := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
	var tree = preload("res://scenes/objects/tree.tscn").instantiate()
	holder.add_child(unit)
	holder.add_child(tree)
	unit.set_simulation_lod(Unit.SimulationLOD.BACKGROUND, false)
	unit.command_harvest(tree)
	unit.simulate_lod(2.0)
	assert(unit.carried_wood == 4)
	assert(tree.wood_amount == 16)
	assert(unit.global_position == Vector2.ZERO)
	holder.queue_free()
	await process_frame


func _test_harvester_returns_while_offscreen():
	var world := Node2D.new()
	for node_name in ["trees", "rocks", "roads", "buildings"]:
		var container := Node2D.new()
		container.name = node_name
		world.add_child(container)
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.zoom = Vector2.ONE * 4.0
	world.add_child(camera)
	var manager := SimulationLODManager.new()
	manager.name = "SimulationLODManager"
	world.add_child(manager)
	var warehouse := preload("res://scenes/objects/buildings/warehouse.tscn").instantiate() as Building
	warehouse.position = Vector2(200, 0)
	world.get_node("buildings").add_child(warehouse)
	var unit := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
	unit.position = Vector2(280, 0)
	unit.carry_capacity = 3
	unit.harvest_interval = 0.1
	unit.food_timer = 10000.0
	world.add_child(unit)
	root.add_child(world)
	await process_frame
	await process_frame
	var record_id := manager.register_resource_data("tree", Vector2(600, 0), 0, unit.carry_capacity)
	var tree = manager._get_or_materialize_resource(manager._resource_records_by_id[record_id])
	unit.command_harvest(tree)
	var left_full_simulation := false
	var furthest_x := unit.global_position.x
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 2.0
	for frame_index in range(300):
		await physics_frame
		left_full_simulation = left_full_simulation or unit.simulation_lod != Unit.SimulationLOD.FULL
		furthest_x = maxf(furthest_x, unit.global_position.x)
		if warehouse.get_stored_resource(&"wood") >= unit.carry_capacity:
			break
	Engine.time_scale = previous_time_scale
	assert(left_full_simulation)
	assert(warehouse.get_stored_resource(&"wood") == unit.carry_capacity)
	assert(unit.global_position.x < 310.0)
	world.queue_free()
	await process_frame


func _test_offscreen_construction_uses_full_simulation():
	var world := Node2D.new()
	for node_name in ["trees", "rocks", "roads", "buildings"]:
		var container := Node2D.new()
		container.name = node_name
		world.add_child(container)
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.zoom = Vector2.ONE * 4.0
	world.add_child(camera)
	var manager := SimulationLODManager.new()
	manager.name = "SimulationLODManager"
	world.add_child(manager)
	var construction := preload("res://scenes/objects/buildings/residence.tscn").instantiate() as Building
	construction.position = Vector2(1200, 1200)
	construction.build_time = 0.2
	world.get_node("buildings").add_child(construction)
	construction.begin_construction()
	construction.delivered_wood = construction.wood_required
	construction.delivered_stone = construction.stone_required
	var builder := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
	builder.position = construction.get_approach_position(Vector2(1100, 1200))
	builder.food_timer = 10000.0
	world.add_child(builder)
	root.add_child(world)
	await process_frame
	await process_frame
	builder.command_build(construction)
	for frame_index in range(30):
		await physics_frame
		if construction.is_completed():
			break
	assert(builder.simulation_lod == Unit.SimulationLOD.FULL)
	assert(not builder.visible)
	assert(construction.is_completed())
	world.queue_free()
	await process_frame


func _test_streamed_world():
	var started := Time.get_ticks_msec()
	var world = preload("res://scripts/land/generation.gd").new()
	world.generate_world_on_ready = false
	for node_name in ["ground", "trees", "rocks", "roads", "buildings"]:
		var container := Node2D.new()
		container.name = node_name
		world.add_child(container)
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	world.add_child(camera)
	var manager := SimulationLODManager.new()
	manager.name = "SimulationLODManager"
	world.add_child(manager)
	root.add_child(world)
	world.rng.seed = 12345
	world.forest_noise.seed = 12345
	world.forest_noise.frequency = world.FOREST_NOISE_FREQUENCY
	world.generate_ground()
	world.generate_forest()
	world.generate_rock_deposits()
	await process_frame
	await process_frame
	var load_time := Time.get_ticks_msec() - started
	var ground := world.get_node("ground/GroundTiles") as TileMapLayer
	var lod_manager := world.get_node("SimulationLODManager") as SimulationLODManager
	assert(ground != null)
	assert(ground.get_used_cells().size() == 40000)
	var saved_resources := lod_manager.get_resource_save_data()
	assert(saved_resources.size() > 40000)
	_assert_rocks_do_not_overlap(saved_resources, lod_manager.ROCK_MIN_SPACING)
	var loaded_resources := 0
	for resource in get_nodes_in_group("resources"):
		if world.is_ancestor_of(resource):
			loaded_resources += 1
	assert(loaded_resources < saved_resources.size() / 4)
	assert(load_time < 15000)
	var distant_tree = lod_manager.find_nearest_resource(&"wood", Vector2(12000, 12000))
	assert(is_instance_valid(distant_tree))
	assert(not distant_tree.visible)
	var distant_record_id: int = distant_tree.lod_record_id
	var original_amount: int = distant_tree.wood_amount
	assert(distant_tree.harvest(3) == 3)
	assert(int(lod_manager._resource_records_by_id[distant_record_id].amount) == original_amount - 3)
	var unit := preload("res://scenes/objects/unit.tscn").instantiate() as Unit
	world.add_child(unit)
	lod_manager._refresh_lods(true, 0.0)
	assert(unit.simulation_lod == Unit.SimulationLOD.FULL)
	camera.position = Vector2(12000, 12000)
	lod_manager._refresh_lods(false, 1.0)
	assert(distant_tree.visible)
	assert(unit.simulation_lod == Unit.SimulationLOD.FULL)
	lod_manager._refresh_lods(false, 1.1)
	assert(unit.simulation_lod == Unit.SimulationLOD.FULL)
	lod_manager._refresh_lods(false, 1.0)
	assert(unit.simulation_lod == Unit.SimulationLOD.FULL)
	assert(not unit.visible)
	camera.position = Vector2.ZERO
	lod_manager._refresh_lods(false, 0.2)
	assert(unit.simulation_lod == Unit.SimulationLOD.FULL)
	world.queue_free()
	await process_frame


func _assert_rocks_do_not_overlap(resources: Array, minimum_spacing: float):
	var rock_cells := {}
	for resource in resources:
		if str(resource.get("type", "")) != "rock":
			continue
		var raw_position: Array = resource.get("position", [])
		assert(raw_position.size() >= 2)
		var position := Vector2(float(raw_position[0]), float(raw_position[1]))
		var cell := Vector2i(floori(position.x / minimum_spacing), floori(position.y / minimum_spacing))
		for x in range(cell.x - 1, cell.x + 2):
			for y in range(cell.y - 1, cell.y + 2):
				for other_position in rock_cells.get(Vector2i(x, y), []):
					assert(position.distance_to(other_position) >= minimum_spacing - 0.001)
		if not rock_cells.has(cell):
			rock_cells[cell] = []
		rock_cells[cell].append(position)
