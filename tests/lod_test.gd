extends SceneTree


func _init():
	call_deferred("_run")


func _run():
	await _test_coarse_unit_movement()
	await _test_coarse_harvest()
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
	assert(unit.simulation_lod == Unit.SimulationLOD.STRATEGIC)
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
