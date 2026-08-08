class_name Unit
extends CharacterBody2D

enum Task { IDLE, MOVE, HARVEST, BUILD, DELIVER_TO_WAREHOUSE, FETCH_FROM_WAREHOUSE }

@export var speed := 100.0
@export var carry_capacity := 10
@export var interaction_distance := 20.0
@export var harvest_interval := 0.5

static var selected_unit: Unit
static var continuous_harvest_mode := false

var target_position := Vector2.ZERO
var selected := false
var task := Task.IDLE
var carried_wood := 0
var carried_stone := 0
var harvest_resource_type: StringName = &"wood"
var work_timer := 0.0
var target_tree: Node2D
var target_building: Building
var target_warehouse: Building
var continuous_harvest := false
var build_queue: Array[Building] = []
var build_job_kind := ""

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
			if _move_toward(target_position):
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
	velocity = global_position.direction_to(destination) * speed
	move_and_slide()
	return false


func _process_harvest(delta: float):
	if not is_instance_valid(target_tree):
		_finish_harvest()
		return
	if is_instance_valid(target_building) and get_carried_resource_amount() >= _get_collection_target(harvest_resource_type):
		_finish_harvest()
		return
	if not _move_toward(target_tree.global_position, interaction_distance):
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
			if _move_toward(target_building.global_position, interaction_distance):
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

	if _move_toward(target_building.global_position, interaction_distance):
		target_building.add_build_progress(delta)


func _process_warehouse_delivery():
	if not is_instance_valid(target_warehouse) or not target_warehouse.has_resource_space(harvest_resource_type):
		_release_warehouse()
		task = Task.IDLE
		return
	if not _move_toward(target_warehouse.global_position, interaction_distance):
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
	if not _move_toward(target_warehouse.global_position, interaction_distance):
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
	var nearest_resource: Node2D = _find_nearest_resource(harvest_resource_type)
	if is_instance_valid(nearest_resource) and is_instance_valid(target_warehouse) and target_warehouse.has_resource_space(harvest_resource_type):
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
	task = Task.MOVE


func command_harvest(tree: Node2D):
	_cancel_task()
	harvest_resource_type = tree.get_resource_type()
	var warehouse := _find_free_warehouse(harvest_resource_type)
	if continuous_harvest_mode and is_instance_valid(warehouse) and warehouse.assign_worker(self):
		target_warehouse = warehouse
		continuous_harvest = true
	_start_harvesting(tree)


func command_build(building: Building):
	_cancel_task()
	build_job_kind = building.building_kind
	target_building = building
	task = Task.BUILD


func command_build_line(segments: Array[Building]):
	_cancel_task()
	if not segments.is_empty():
		build_job_kind = segments[0].building_kind
	build_queue = segments.duplicate()
	_advance_build_queue()


func _advance_build_queue():
	target_building = null
	while not build_queue.is_empty():
		var next_building: Building = build_queue.pop_front()
		if is_instance_valid(next_building) and not next_building.is_completed():
			target_building = next_building
			task = Task.BUILD
			return
	var nearest: Building
	var nearest_distance := INF
	if not build_job_kind.is_empty():
		for building in get_tree().get_nodes_in_group("buildings"):
			if building is not Building or building.building_kind != build_job_kind or not building.under_construction:
				continue
			var distance := global_position.distance_squared_to(building.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = building
	if is_instance_valid(nearest):
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

	for hit in hits:
		var collider = hit.collider
		if collider is Node and collider.is_in_group("resources"):
			if continuous_harvest_mode:
				command_harvest(collider)
			else:
				command_move(collider.global_position)
			return

	command_move(mouse_position)


func select():
	if is_instance_valid(selected_unit) and selected_unit != self:
		selected_unit.deselect()
	selected_unit = self
	selected = true
	selection.visible = true


func deselect():
	selected = false
	selection.visible = false
	if selected_unit == self:
		selected_unit = null


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
