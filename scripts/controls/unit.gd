class_name Unit
extends CharacterBody2D

enum Task { IDLE, MOVE, HARVEST, BUILD, DELIVER_TO_WAREHOUSE, FETCH_FROM_WAREHOUSE }

@export var speed := 100.0
@export var carry_capacity := 10
@export var interaction_distance := 20.0
@export var harvest_interval := 0.5

static var selected_unit: Unit
static var selected_units: Array[Unit] = []
static var continuous_harvest_mode := false

var target_position := Vector2.ZERO
var selected := false
var task := Task.IDLE
var carried_wood := 0
var carried_stone := 0
var harvest_resource_type: StringName = &"wood"
var mining_job_resource_type: StringName = &"wood"
var work_timer := 0.0
var target_tree: Node2D
var target_building: Building
var target_warehouse: Building
var continuous_harvest := false
var build_queue: Array[Building] = []
var build_job_kind := ""
var path_points := PackedVector2Array()
var path_index := 0
var path_destination := Vector2(INF, INF)

const PATH_CELL_SIZE := 32.0
const PATH_MAP_SIZE := Vector2i(400, 400)

@onready var selection: Sprite2D = $selection


func _ready():
	add_to_group("units")
	target_position = global_position
	selection.visible = false


func _exit_tree():
	if is_instance_valid(target_tree):
		target_tree.stop_harvest(self)
	_release_warehouse()


func _physics_process(delta: float):
	match task:
		Task.MOVE:
			if _follow_path():
				task = Task.IDLE
		Task.HARVEST:
			_process_harvest(delta)
		Task.BUILD:
			_process_build(delta)
		Task.DELIVER_TO_WAREHOUSE:
			_process_warehouse_delivery()
		Task.FETCH_FROM_WAREHOUSE:
			_process_warehouse_fetch()
		_:
			velocity = Vector2.ZERO


func _move_toward(destination: Vector2, stop_distance := 3.0) -> bool:
	if global_position.distance_to(destination) <= stop_distance:
		velocity = Vector2.ZERO
		return true
	var direction := global_position.direction_to(destination)
	direction = (direction + _get_separation_force(direction) * 0.75).normalized()
	if direction.is_zero_approx():
		direction = global_position.direction_to(destination)
	velocity = direction * speed
	move_and_slide()
	return false


func _get_separation_force(desired_direction: Vector2) -> Vector2:
	var force := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("units"):
		if other == self or other is not Unit:
			continue
		var distance: float = global_position.distance_to(other.global_position)
		if distance > 0.01 and distance < 24.0:
			var strength := 1.0 - distance / 24.0
			var away: Vector2 = other.global_position.direction_to(global_position)
			force += away * strength * 0.45
			# Встречные юниты смещаются вправо относительно своего движения.
			if not other.velocity.is_zero_approx() and desired_direction.dot(other.velocity.normalized()) < -0.4:
				force += desired_direction.orthogonal() * strength * 0.8
	return force


func _follow_path() -> bool:
	if path_points.is_empty() or path_index >= path_points.size():
		return _move_toward(target_position)
	if _move_toward(path_points[path_index], 5.0):
		path_index += 1
	if path_index >= path_points.size():
		return _move_toward(target_position)
	return false


func _navigate_toward(destination: Vector2, stop_distance := 3.0) -> bool:
	if path_destination.distance_to(destination) > 8.0:
		_calculate_path(destination)
	if not path_points.is_empty() and path_index < path_points.size():
		if _move_toward(path_points[path_index], 5.0):
			path_index += 1
		return false
	return _move_toward(destination, stop_distance)


func _calculate_path(destination: Vector2):
	path_destination = destination
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, PATH_MAP_SIZE)
	grid.cell_size = Vector2.ONE * PATH_CELL_SIZE
	grid.offset = Vector2.ONE * PATH_CELL_SIZE * 0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()

	for building in get_tree().get_nodes_in_group("buildings"):
		if building is not Building or building.building_kind == "road":
			continue
		var collision := building.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collision == null or collision.shape is not RectangleShape2D:
			continue
		var half_size: Vector2 = collision.shape.size * building.global_scale.abs() * 0.5 + Vector2.ONE * 12.0
		var minimum := _world_to_cell(collision.global_position - half_size)
		var maximum := _world_to_cell(collision.global_position + half_size)
		for x in range(minimum.x, maximum.x + 1):
			for y in range(minimum.y, maximum.y + 1):
				var cell := Vector2i(x, y)
				if grid.region.has_point(cell):
					grid.set_point_solid(cell, true)

	var start := _world_to_cell(global_position)
	var finish := _world_to_cell(destination)
	if not grid.region.has_point(start) or not grid.region.has_point(finish):
		path_points = PackedVector2Array()
		return
	grid.set_point_solid(start, false)
	grid.set_point_solid(finish, false)
	path_points = grid.get_point_path(start, finish)
	path_index = 0


func _world_to_cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / PATH_CELL_SIZE), floori(point.y / PATH_CELL_SIZE))


func _process_harvest(delta: float):
	if not is_instance_valid(target_tree):
		_finish_harvest()
		return
	if is_instance_valid(target_building) and get_carried_resource_amount() >= _get_collection_target(harvest_resource_type):
		_finish_harvest()
		return
	if not _navigate_toward(target_tree.global_position, interaction_distance):
		target_tree.set_harvest_progress(self, 0.0)
		return

	work_timer -= delta
	target_tree.set_harvest_progress(self, 1.0 - clampf(work_timer / harvest_interval, 0.0, 1.0))
	if work_timer > 0.0:
		return

	work_timer = harvest_interval
	var harvested: int = target_tree.harvest(1)
	if harvest_resource_type == &"stone":
		carried_stone += harvested
	else:
		carried_wood += harvested
	var enough_for_build := is_instance_valid(target_building) and get_carried_resource_amount() >= _get_collection_target(harvest_resource_type)
	if get_carried_total() >= carry_capacity or enough_for_build or not is_instance_valid(target_tree) or target_tree.is_depleted():
		_finish_harvest()


func _finish_harvest():
	if is_instance_valid(target_tree):
		target_tree.stop_harvest(self)
	target_tree = null
	if is_instance_valid(target_building):
		task = Task.BUILD
	elif continuous_harvest and is_instance_valid(target_warehouse) and get_carried_resource_amount() > 0:
		task = Task.DELIVER_TO_WAREHOUSE
	elif continuous_harvest:
		_start_next_tree()
	else:
		task = Task.IDLE


func _process_build(delta: float):
	if not is_instance_valid(target_building) or target_building.is_completed():
		_advance_build_queue()
		return

	if target_building.needs_materials():
		var needed_type := target_building.get_needed_resource_type()
		harvest_resource_type = needed_type
		if get_carried_resource_amount() > 0:
			if _navigate_toward(target_building.get_approach_position(global_position), 6.0):
				var accepted := target_building.deliver_resource(needed_type, get_carried_resource_amount())
				_remove_carried_resource(accepted)
			return
		if _get_collection_target(needed_type) <= 0:
			velocity = Vector2.ZERO
			return
		var resource_warehouse := _find_warehouse_with_resource(needed_type)
		if is_instance_valid(resource_warehouse):
			target_warehouse = resource_warehouse
			task = Task.FETCH_FROM_WAREHOUSE
			return

		var nearest_tree: Node2D = _find_nearest_resource(needed_type)
		if is_instance_valid(nearest_tree):
			_start_harvesting(nearest_tree)
		else:
			velocity = Vector2.ZERO
		return

	if _navigate_toward(target_building.get_approach_position(global_position), 6.0):
		target_building.add_build_progress(delta)


func _process_warehouse_delivery():
	if not is_instance_valid(target_warehouse) or not target_warehouse.has_resource_space(harvest_resource_type):
		_release_warehouse()
		task = Task.IDLE
		return
	if not _navigate_toward(target_warehouse.get_approach_position(global_position), 6.0):
		return
	var delivered := target_warehouse.store_resource(harvest_resource_type, get_carried_resource_amount())
	_remove_carried_resource(delivered)
	if get_carried_resource_amount() > 0:
		_release_warehouse()
		task = Task.IDLE
	else:
		_start_next_tree()


func _process_warehouse_fetch():
	if not is_instance_valid(target_building) or target_building.is_completed():
		target_warehouse = null
		_advance_build_queue()
		return
	if not is_instance_valid(target_warehouse) or not target_warehouse.has_stored_resource(harvest_resource_type):
		target_warehouse = null
		task = Task.BUILD
		return
	if _get_collection_target(harvest_resource_type) <= get_carried_resource_amount():
		target_warehouse = null
		task = Task.BUILD
		return
	if not _navigate_toward(target_warehouse.get_approach_position(global_position), 6.0):
		return

	var needed := maxi(_get_collection_target(harvest_resource_type) - get_carried_resource_amount(), 0)
	var taken := target_warehouse.take_resource(harvest_resource_type, needed)
	if harvest_resource_type == &"stone":
		carried_stone += taken
	else:
		carried_wood += taken
	target_warehouse = null
	task = Task.BUILD


func _start_next_tree():
	var nearest_resource: Node2D = _find_nearest_resource(mining_job_resource_type)
	if is_instance_valid(nearest_resource) and is_instance_valid(target_warehouse) and target_warehouse.has_resource_space(mining_job_resource_type):
		_start_harvesting(nearest_resource)
	else:
		_release_warehouse()
		task = Task.IDLE


func _start_harvesting(tree: Node2D):
	target_tree = tree
	harvest_resource_type = target_tree.get_resource_type()
	target_tree.set_harvest_progress(self, 0.0)
	work_timer = harvest_interval
	task = Task.HARVEST


func _find_nearest_tree():
	return _find_nearest_resource(&"wood")


func _find_nearest_resource(resource_type: StringName):
	var nearest_tree: Node2D
	var nearest_distance := INF
	var fewest_workers := 2147483647
	for tree in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(tree) or tree.is_depleted() or tree.get_resource_type() != resource_type:
			continue
		fewest_workers = mini(fewest_workers, tree.get_harvester_count())

	for tree in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(tree) or tree.is_depleted() or tree.get_resource_type() != resource_type:
			continue
		if tree.get_harvester_count() > fewest_workers:
			continue
		var distance := global_position.distance_squared_to(tree.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_tree = tree
	return nearest_tree


func _find_free_warehouse(resource_type: StringName) -> Building:
	var nearest: Building
	var nearest_distance := INF
	for building in get_tree().get_nodes_in_group("buildings"):
		if building is not Building or not building.can_accept_worker(resource_type):
			continue
		var distance := global_position.distance_squared_to(building.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = building
	return nearest


func _find_warehouse_with_resource(resource_type: StringName) -> Building:
	var nearest: Building
	var nearest_distance := INF
	for building in get_tree().get_nodes_in_group("buildings"):
		if building is not Building or not building.has_stored_resource(resource_type):
			continue
		var distance := global_position.distance_squared_to(building.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = building
	return nearest


func _get_collection_target(resource_type: StringName) -> int:
	var total_remaining := 0
	if not build_job_kind.is_empty():
		for building in get_tree().get_nodes_in_group("buildings"):
			if building is Building and building.under_construction and building.building_kind == build_job_kind:
				total_remaining += building.get_remaining_resource(resource_type)
	elif is_instance_valid(target_building):
		total_remaining = target_building.get_remaining_resource(resource_type)

	var carried_by_others := 0
	for unit in get_tree().get_nodes_in_group("units"):
		if unit == self or unit is not Unit or unit.build_job_kind != build_job_kind:
			continue
		carried_by_others += unit.carried_stone if resource_type == &"stone" else unit.carried_wood

	var available_capacity := carry_capacity - (get_carried_total() - get_carried_resource_amount())
	return mini(maxi(total_remaining - carried_by_others, 0), available_capacity)


func _cancel_task():
	if is_instance_valid(target_tree):
		target_tree.stop_harvest(self)
	target_tree = null
	if is_instance_valid(target_building):
		target_building.release_builder(self)
	target_building = null
	build_queue.clear()
	build_job_kind = ""
	continuous_harvest = false
	_release_warehouse()


func _release_warehouse():
	if is_instance_valid(target_warehouse):
		target_warehouse.release_worker(self)
	target_warehouse = null


func command_move(destination: Vector2):
	_cancel_task()
	target_position = destination
	_calculate_path(destination)
	task = Task.MOVE


func command_harvest(tree: Node2D):
	_cancel_task()
	harvest_resource_type = tree.get_resource_type()
	mining_job_resource_type = harvest_resource_type
	var warehouse := _find_free_warehouse(harvest_resource_type)
	if continuous_harvest_mode and is_instance_valid(warehouse) and warehouse.assign_worker(self):
		target_warehouse = warehouse
		continuous_harvest = true
	_start_harvesting(tree)


func command_build(building: Building):
	_cancel_task()
	build_job_kind = building.building_kind
	if building.try_assign_builder(self):
		target_building = building
		task = Task.BUILD
	else:
		_advance_build_queue()


func command_build_line(segments: Array[Building]):
	_cancel_task()
	if not segments.is_empty():
		build_job_kind = segments[0].building_kind
	for segment in segments:
		build_queue.append(segment)
	_advance_build_queue()


func _advance_build_queue():
	if is_instance_valid(target_building):
		target_building.release_builder(self)
	target_building = null
	while not build_queue.is_empty():
		var next_building: Building = build_queue.pop_front()
		if is_instance_valid(next_building) and not next_building.is_completed() and next_building.try_assign_builder(self):
			target_building = next_building
			task = Task.BUILD
			return
	var nearest: Building
	var nearest_distance := INF
	if not build_job_kind.is_empty():
		for building in get_tree().get_nodes_in_group("buildings"):
			if building is not Building or building.building_kind != build_job_kind or not building.under_construction:
				continue
			if building.building_kind == "road" and not building.active_builders.is_empty():
				continue
			var distance := global_position.distance_squared_to(building.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = building
	if is_instance_valid(nearest):
		if nearest.try_assign_builder(self):
			target_building = nearest
			task = Task.BUILD
			return
	build_job_kind = ""
	task = Task.IDLE


func _input_event(_viewport: Node, event: InputEvent, _shape_idx: int):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		select()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent):
	if selected and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_issue_context_command(get_global_mouse_position())
		get_viewport().set_input_as_handled()


func _issue_context_command(mouse_position: Vector2):
	var query := PhysicsPointQueryParameters2D.new()
	query.position = mouse_position
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hits := get_world_2d().direct_space_state.intersect_point(query, 32)

	# Недостроенное здание имеет приоритет, если объекты перекрываются.
	for hit in hits:
		var collider = hit.collider
		if collider is Building and collider.under_construction:
			command_build(collider)
			return

	var selected_resource: Node2D
	var nearest_resource_distance := INF
	for hit in hits:
		var collider = hit.collider
		if collider is Node and collider.is_in_group("resources"):
			var distance: float = mouse_position.distance_squared_to(collider.global_position)
			if distance < nearest_resource_distance:
				nearest_resource_distance = distance
				selected_resource = collider
	if is_instance_valid(selected_resource):
		if continuous_harvest_mode:
			command_harvest(selected_resource)
		else:
			command_move(selected_resource.global_position)
		return

	command_move(mouse_position)


func select(additive := false):
	if not additive:
		clear_selection()
	selected_unit = self
	if self not in selected_units:
		selected_units.append(self)
	selected = true
	selection.visible = true


func deselect():
	selected = false
	selection.visible = false
	selected_units.erase(self)
	if selected_unit == self:
		selected_unit = selected_units.back() if not selected_units.is_empty() else null


func get_task_text() -> String:
	match task:
		Task.MOVE: return "Идёт"
		Task.HARVEST: return "Рубит дерево"
		Task.BUILD: return "Строит"
		Task.DELIVER_TO_WAREHOUSE: return "Несёт древесину"
		Task.FETCH_FROM_WAREHOUSE: return "Берёт древесину со склада"
		_: return "Свободен"


func get_carried_total() -> int:
	return carried_wood + carried_stone


func get_carried_resource_amount() -> int:
	return carried_stone if harvest_resource_type == &"stone" else carried_wood


func _remove_carried_resource(amount: int):
	if harvest_resource_type == &"stone":
		carried_stone -= amount
	else:
		carried_wood -= amount


static func get_selected_unit() -> Unit:
	return selected_unit if is_instance_valid(selected_unit) else null


static func get_selected_units() -> Array[Unit]:
	for index in range(selected_units.size() - 1, -1, -1):
		if not is_instance_valid(selected_units[index]):
			selected_units.remove_at(index)
	return selected_units


static func clear_selection():
	for unit in selected_units.duplicate():
		if is_instance_valid(unit):
			unit.selected = false
			unit.selection.visible = false
	selected_units.clear()
	selected_unit = null


static func set_selection(units: Array[Unit]):
	clear_selection()
	for unit in units:
		if is_instance_valid(unit):
			unit.selected = true
			unit.selection.visible = true
			selected_units.append(unit)
	selected_unit = selected_units.back() if not selected_units.is_empty() else null
