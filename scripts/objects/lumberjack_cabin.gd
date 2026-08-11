class_name LumberjackCabin
extends Building

const TREE_SCENE := preload("res://scenes/objects/tree.tscn")
const WORLD_SIZE := Vector2(12800.0, 12800.0)
const WORLD_MARGIN := 80.0

@export_range(5.0, 300.0, 1.0) var tree_growth_time := 45.0
@export_range(0.1, 10.0, 0.05) var harvest_interval := 1.0
@export_range(1, 4, 1) var plots_per_worker := 1
@export_range(80.0, 600.0, 10.0) var planting_min_radius := 180.0
@export_range(100.0, 900.0, 10.0) var planting_max_radius := 360.0
@export_range(24.0, 100.0, 1.0) var planting_clearance := 48.0
@export_range(1, 100, 1) var tree_wood_amount := 20

var forestry_plots: Array[Dictionary] = []
var planting_sequence := 0
var planting_retry_timer := 0.0


func _ready():
	selected_recipe = &"forestry"
	super._ready()


func _exit_tree():
	_clear_forestry_plots()
	super._exit_tree()


func _process(delta: float):
	super._process(delta)
	_update_plot_visibility()
	if placement_preview or under_construction or not is_completed() or _is_remote_client():
		return
	_cleanup_occupants()
	var active_plot_count := occupants.size() * plots_per_worker
	if active_plot_count <= 0:
		return
	planting_retry_timer = maxf(planting_retry_timer - delta, 0.0)
	while forestry_plots.size() < active_plot_count and planting_retry_timer <= 0.0:
		if not _plant_new_tree():
			planting_retry_timer = 3.0
			break
	for plot_index in range(mini(active_plot_count, forestry_plots.size())):
		_process_plot(forestry_plots[plot_index], delta)


func is_lumberjack_cabin() -> bool:
	return true


func can_produce_selected_recipe() -> bool:
	# Производственный таймер юнита здесь не используется: весь лесной цикл
	# просчитывает сама хижина, пока рабочий находится внутри.
	return false


func produce_selected_recipe() -> bool:
	return false


func get_production_time() -> float:
	return 1.0


func get_factory_status_text() -> String:
	if not is_completed():
		return "Лесничество начнёт работать после завершения строительства."
	if get_worker_target() <= 0:
		return "Лесничество остановлено: назначено 0 работников."
	if occupants.is_empty():
		return "Хижина ожидает дровосеков."
	var growing := 0
	var mature := 0
	for plot in forestry_plots:
		if bool(plot.get("mature", false)):
			mature += 1
		else:
			growing += 1
	if mature > 0 and _get_network_space(&"wood") <= 0:
		return "Рубка приостановлена: на складах нет места для древесины."
	return "Лесничество работает: растёт %d, рубится %d, работников %d/%d." % [growing, mature, occupants.size(), get_worker_target()]


func _process_plot(plot: Dictionary, delta: float):
	var tree := plot.get("tree") as Node2D
	if not is_instance_valid(tree):
		_spawn_plot_tree(plot)
		tree = plot.get("tree") as Node2D
	if not bool(plot.get("mature", false)):
		var growth_remaining := maxf(float(plot.get("growth_remaining", tree_growth_time)) - delta, 0.0)
		plot["growth_remaining"] = growth_remaining
		_update_sapling_scale(plot)
		if growth_remaining <= 0.0:
			plot["mature"] = true
			if is_instance_valid(tree):
				tree.scale = Vector2.ONE
				tree.set("wood_amount", tree_wood_amount)
				_set_tree_interaction(tree, true)
		return
	if not is_instance_valid(tree):
		_reset_plot_for_replanting(plot)
		return
	var wood_left := int(tree.get("wood_amount"))
	if wood_left <= 0:
		_reset_plot_for_replanting(plot)
		return
	var harvest_timer := float(plot.get("harvest_timer", harvest_interval)) - delta
	while harvest_timer <= 0.0 and wood_left > 0:
		var warehouse := _find_wood_warehouse()
		if not is_instance_valid(warehouse):
			harvest_timer = 0.0
			break
		var harvested := int(tree.call("harvest", 1, faction_id))
		if harvested <= 0:
			break
		warehouse.store_resource(&"wood", harvested)
		wood_left -= harvested
		harvest_timer += harvest_interval
	plot["harvest_timer"] = harvest_timer
	if wood_left <= 0:
		plot["tree"] = null
		_reset_plot_for_replanting(plot)


func _plant_new_tree() -> bool:
	var position := _find_planting_position()
	if position == Vector2.INF:
		return false
	var plot := {
		"position": position,
		"growth_remaining": tree_growth_time,
		"harvest_timer": harvest_interval,
		"mature": false,
		"variant": planting_sequence % 3,
		"tree": null,
	}
	planting_sequence += 1
	forestry_plots.append(plot)
	_spawn_plot_tree(plot)
	return true


func _find_planting_position() -> Vector2:
	var cabin_seed := network_id if network_id > 0 else int(get_instance_id() % 100000)
	for attempt in range(72):
		var sample_index := planting_sequence * 72 + attempt
		var angle := fmod(float(cabin_seed) * 0.61803398875 + float(sample_index) * 2.39996323, TAU)
		var radius_ratio := fmod(float(sample_index) * 0.754877666, 1.0)
		var radius := lerpf(planting_min_radius, planting_max_radius, radius_ratio)
		var candidate := global_position + Vector2.from_angle(angle) * radius
		if is_planting_position_safe(candidate):
			return candidate
	return Vector2.INF


func is_planting_position_safe(position: Vector2) -> bool:
	if position.x < WORLD_MARGIN or position.y < WORLD_MARGIN or position.x > WORLD_SIZE.x - WORLD_MARGIN or position.y > WORLD_SIZE.y - WORLD_MARGIN:
		return false
	for candidate in get_tree().get_nodes_in_group("buildings"):
		if candidate is not Building or not is_instance_valid(candidate) or candidate.placement_preview:
			continue
		if candidate.contains_world_point(position, planting_clearance):
			return false
	for plot in forestry_plots:
		if position.distance_squared_to(plot.get("position", Vector2.ZERO)) < planting_clearance * planting_clearance:
			return false
	for resource in get_tree().get_nodes_in_group("resources"):
		if resource is Node2D and is_instance_valid(resource) and position.distance_squared_to(resource.global_position) < planting_clearance * planting_clearance:
			return false
	var lod_manager := get_tree().get_first_node_in_group("simulation_lod_manager")
	if is_instance_valid(lod_manager) and lod_manager.has_method("has_resource_near") and lod_manager.has_resource_near(position, planting_clearance):
		return false
	return true


func _spawn_plot_tree(plot: Dictionary):
	var container := _get_tree_container()
	if not is_instance_valid(container):
		return
	var tree := TREE_SCENE.instantiate() as Node2D
	tree.set_meta("managed_forestry_tree", true)
	tree.set("tree_variant", int(plot.get("variant", 0)))
	tree.set("wood_amount", tree_wood_amount if bool(plot.get("mature", false)) else tree_wood_amount)
	container.add_child(tree)
	tree.add_to_group("managed_forestry_trees")
	tree.global_position = plot.get("position", global_position)
	plot["tree"] = tree
	if bool(plot.get("mature", false)):
		tree.scale = Vector2.ONE
		_set_tree_interaction(tree, true)
	else:
		_update_sapling_scale(plot)
		_set_tree_interaction(tree, false)


func _reset_plot_for_replanting(plot: Dictionary):
	var old_tree := plot.get("tree") as Node2D
	if is_instance_valid(old_tree):
		old_tree.queue_free()
	plot["tree"] = null
	plot["mature"] = false
	plot["growth_remaining"] = tree_growth_time
	plot["harvest_timer"] = harvest_interval
	_spawn_plot_tree(plot)


func _update_sapling_scale(plot: Dictionary):
	var tree := plot.get("tree") as Node2D
	if not is_instance_valid(tree):
		return
	var progress := 1.0 - clampf(float(plot.get("growth_remaining", tree_growth_time)) / maxf(tree_growth_time, 0.001), 0.0, 1.0)
	var sapling_scale := lerpf(0.25, 0.9, progress)
	tree.scale = Vector2.ONE * sapling_scale


func _set_tree_interaction(tree: Node2D, enabled: bool):
	if not is_instance_valid(tree):
		return
	tree.set("input_pickable", enabled and tree.visible)
	tree.set("monitoring", enabled)
	var collision := tree.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if is_instance_valid(collision):
		collision.set_deferred("disabled", not enabled)


func _update_plot_visibility():
	var camera := get_viewport().get_camera_2d()
	if not is_instance_valid(camera):
		return
	var safe_zoom := Vector2(maxf(absf(camera.zoom.x), 0.001), maxf(absf(camera.zoom.y), 0.001))
	var world_size := camera.get_viewport_rect().size / safe_zoom
	var visible_rect := Rect2(camera.global_position - world_size * 0.5, world_size).grow(160.0)
	for plot in forestry_plots:
		var tree := plot.get("tree") as Node2D
		if not is_instance_valid(tree):
			continue
		var should_render := visible_rect.has_point(tree.global_position)
		tree.visible = should_render
		tree.set("input_pickable", should_render and bool(plot.get("mature", false)))


func _find_wood_warehouse() -> Building:
	for warehouse in _get_warehouses():
		if warehouse.has_resource_space(&"wood"):
			return warehouse
	return null


func _get_tree_container() -> Node:
	var world := get_parent().get_parent() if is_instance_valid(get_parent()) and is_instance_valid(get_parent().get_parent()) else null
	if is_instance_valid(world):
		var container := world.get_node_or_null("trees")
		if is_instance_valid(container):
			return container
	return get_tree().current_scene.get_node_or_null("trees") if is_instance_valid(get_tree().current_scene) else null


func _is_remote_client() -> bool:
	var network_manager := get_node_or_null("/root/NetworkManager")
	return is_instance_valid(network_manager) and network_manager.has_method("is_remote_client") and network_manager.is_remote_client()


func get_forestry_save_data() -> Array:
	var result: Array = []
	for plot in forestry_plots:
		var tree := plot.get("tree") as Node2D
		result.append({
			"position": [float(plot.get("position", Vector2.ZERO).x), float(plot.get("position", Vector2.ZERO).y)],
			"growth_remaining": float(plot.get("growth_remaining", tree_growth_time)),
			"harvest_timer": float(plot.get("harvest_timer", harvest_interval)),
			"mature": bool(plot.get("mature", false)),
			"variant": int(plot.get("variant", 0)),
			"wood_amount": int(tree.get("wood_amount")) if is_instance_valid(tree) else 0,
		})
	return result


func restore_forestry_save_data(raw_plots: Variant):
	_clear_forestry_plots()
	if raw_plots is not Array:
		return
	for raw_plot in raw_plots:
		if raw_plot is not Dictionary:
			continue
		var position_data: Variant = raw_plot.get("position", [global_position.x, global_position.y])
		var position := Vector2(float(position_data[0]), float(position_data[1])) if position_data is Array and position_data.size() >= 2 else global_position
		var plot := {
			"position": position,
			"growth_remaining": maxf(float(raw_plot.get("growth_remaining", tree_growth_time)), 0.0),
			"harvest_timer": float(raw_plot.get("harvest_timer", harvest_interval)),
			"mature": bool(raw_plot.get("mature", false)),
			"variant": int(raw_plot.get("variant", 0)),
			"tree": null,
		}
		forestry_plots.append(plot)
		_spawn_plot_tree(plot)
		var tree := plot.get("tree") as Node2D
		if is_instance_valid(tree) and bool(plot.mature):
			tree.set("wood_amount", maxi(int(raw_plot.get("wood_amount", tree_wood_amount)), 1))
	planting_sequence = forestry_plots.size()


func apply_forestry_network_state(raw_plots: Variant):
	if raw_plots is not Array:
		return
	if raw_plots.size() != forestry_plots.size():
		restore_forestry_save_data(raw_plots)
		return
	for plot_index in range(raw_plots.size()):
		var raw_plot: Dictionary = raw_plots[plot_index]
		var plot: Dictionary = forestry_plots[plot_index]
		var was_mature := bool(plot.get("mature", false))
		plot["growth_remaining"] = maxf(float(raw_plot.get("growth_remaining", plot.get("growth_remaining", tree_growth_time))), 0.0)
		plot["harvest_timer"] = float(raw_plot.get("harvest_timer", plot.get("harvest_timer", harvest_interval)))
		plot["mature"] = bool(raw_plot.get("mature", was_mature))
		if was_mature != bool(plot.mature) or not is_instance_valid(plot.get("tree") as Node2D):
			var old_tree := plot.get("tree") as Node2D
			if is_instance_valid(old_tree):
				old_tree.queue_free()
			plot["tree"] = null
			_spawn_plot_tree(plot)
		var tree := plot.get("tree") as Node2D
		if is_instance_valid(tree):
			tree.set("wood_amount", maxi(int(raw_plot.get("wood_amount", tree_wood_amount)), 1))
			if bool(plot.mature):
				tree.scale = Vector2.ONE
				_set_tree_interaction(tree, true)
			else:
				_update_sapling_scale(plot)


func _clear_forestry_plots():
	for plot in forestry_plots:
		var tree := plot.get("tree") as Node2D
		if is_instance_valid(tree):
			tree.queue_free()
	forestry_plots.clear()
