class_name Unit
extends CharacterBody2D

enum Task { IDLE, MOVE, HARVEST, BUILD, DELIVER_TO_WAREHOUSE, FETCH_FROM_WAREHOUSE, ENTER_BUILDING, FACTORY_WORK, REST }
enum SimulationLOD { FULL, REDUCED, STRATEGIC, BACKGROUND }

@export var speed := 100.0
@export var carry_capacity := 10
@export var interaction_distance := 20.0
@export var harvest_interval := 0.5
@export var unit_name := ""
@export var max_health := 100
@export var health := 100
@export var faction_id := 0
@export var controller_peer_id := 1
@export var ai_controlled := false
@export var faction_name := "Игрок"
@export var network_id := 0
@export_range(0, 2) var simulation_importance := 0

const UNIT_NAMES: Array[String] = [
	"Алексей", "Борис", "Виктор", "Григорий", "Даниил", "Егор",
	"Иван", "Кирилл", "Лев", "Максим", "Николай", "Олег",
	"Павел", "Роман", "Семён", "Тимофей", "Фёдор", "Юрий",
	"Анна", "Вера", "Дарья", "Елена", "Ирина", "Мария",
	"Надежда", "Ольга", "Полина", "София", "Татьяна", "Юлия",
]
const FOOD_CONSUMPTION_INTERVAL := 45.0
const STARVATION_DAMAGE := 10
const AUTO_WORK_DELAY_AFTER_MANUAL_ORDER := 5.0
const ROAD_SPEED_MULTIPLIER := 1.5
const ROAD_PATH_WEIGHT := 1.0 / ROAD_SPEED_MULTIPLIER
const ROAD_SPEED_CHECK_INTERVAL := 0.12
const ROAD_PATH_MARGIN := 8.0

static var selected_unit: Unit
static var selected_units: Array[Unit] = []
static var continuous_harvest_mode := false
static var next_name_index := 0

var target_position := Vector2.ZERO
var selected := false
var task := Task.IDLE
var carried_wood := 0
var carried_stone := 0
var profession := "Безработный"
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
var inside_building: Building
var idle_check_timer := 1.0
var production_timer := 0.0
var produced_items := 0
var food_timer := FOOD_CONSUMPTION_INTERVAL
var missed_meals := 0
var last_motion_position := Vector2.ZERO
var stuck_timer := 0.0
var simulation_lod := SimulationLOD.FULL
var lod_render_enabled := true
var lod_pending_level := SimulationLOD.FULL
var lod_pending_time := 0.0
var lod_last_simulation_time := 0.0
var lod_manager: Node
var is_on_road := false
var road_speed_check_timer := 0.0
var road_segments_by_cell := {}

const PATH_CELL_SIZE := 32.0
const PATH_MAP_SIZE := Vector2i(400, 400)
const BUILDING_AVOIDANCE_WEIGHT := 9.0
const FACTION_COLORS: Array[Color] = [
	Color(1.0, 1.0, 1.0),
	Color(1.0, 0.62, 0.62),
	Color(0.62, 0.78, 1.0),
	Color(1.0, 0.86, 0.48),
]

@onready var selection: Sprite2D = $selection
@onready var body: Sprite2D = $body
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready():
	add_to_group("units")
	if unit_name.is_empty():
		var base_name := UNIT_NAMES[next_name_index % UNIT_NAMES.size()]
		var duplicate_number := next_name_index / UNIT_NAMES.size() + 1
		unit_name = base_name if duplicate_number == 1 else "%s %d" % [base_name, duplicate_number]
		next_name_index += 1
	health = clampi(health, 0, max_health)
	target_position = global_position
	last_motion_position = global_position
	selection.visible = false
	lod_manager = get_tree().get_first_node_in_group("simulation_lod_manager")
	_update_faction_visual()


func configure_faction(new_faction_id: int, new_controller_peer_id: int, is_ai: bool, new_faction_name: String):
	faction_id = clampi(new_faction_id, 0, 3)
	controller_peer_id = new_controller_peer_id
	ai_controlled = is_ai
	faction_name = new_faction_name
	if is_node_ready():
		_update_faction_visual()
		if selected and not can_be_controlled_locally():
			deselect()


func can_be_controlled_locally() -> bool:
	if ai_controlled:
		return false
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		return network_manager.can_edit_faction(faction_id)
	return faction_id == 0


func _update_faction_visual():
	if is_instance_valid(body):
		body.modulate = FACTION_COLORS[faction_id % FACTION_COLORS.size()]


func _exit_tree():
	if is_instance_valid(target_tree):
		target_tree.stop_harvest(self)
	if is_instance_valid(inside_building):
		inside_building.leave(self)
	_release_warehouse()


func _physics_process(delta: float):
	if simulation_lod != SimulationLOD.FULL:
		return
	_process_food_needs(delta)
	if health <= 0:
		return
	_update_road_movement_state(delta)
	match task:
		Task.MOVE:
			if _follow_path():
				_finish_manual_move()
		Task.HARVEST:
			_process_harvest(delta)
		Task.BUILD:
			_process_build(delta)
		Task.DELIVER_TO_WAREHOUSE:
			_process_warehouse_delivery()
		Task.FETCH_FROM_WAREHOUSE:
			_process_warehouse_fetch()
		Task.ENTER_BUILDING:
			_process_enter_building()
		Task.FACTORY_WORK:
			_process_factory_work(delta)
		Task.REST:
			_process_rest(delta)
		_:
			_process_idle(delta)
	_update_motion_recovery(delta)


func set_simulation_lod(level: int, render_enabled: bool):
	var previous_lod := simulation_lod
	simulation_lod = clampi(level, SimulationLOD.FULL, SimulationLOD.BACKGROUND)
	lod_render_enabled = render_enabled
	set_physics_process(simulation_lod == SimulationLOD.FULL)
	if previous_lod != SimulationLOD.FULL and simulation_lod == SimulationLOD.FULL:
		# После прямолинейного стратегического перемещения подробный маршрут
		# строится заново от сохранённой позиции, а не от старой точки пути.
		path_points = PackedVector2Array()
		path_index = 0
		path_destination = Vector2(INF, INF)
	_refresh_lod_presentation()


func set_lod_render_enabled(enabled: bool):
	lod_render_enabled = enabled
	_refresh_lod_presentation()


func _refresh_lod_presentation():
	visible = lod_render_enabled and not is_instance_valid(inside_building)
	var collision_enabled := simulation_lod == SimulationLOD.FULL and not is_instance_valid(inside_building)
	if is_instance_valid(collision_shape):
		collision_shape.set_deferred("disabled", not collision_enabled)


func simulate_lod(delta: float):
	# Низкие LOD вызываются общим менеджером редко и крупными порциями времени.
	# Узел юнита не уничтожается: здоровье, груз, приказ и ссылки на цели остаются
	# теми же, поэтому возврат камеры не пересоздаёт и не разбрасывает людей.
	if delta <= 0.0 or simulation_lod == SimulationLOD.FULL:
		return
	_process_food_needs(delta)
	if health <= 0:
		return
	_update_road_movement_state(delta)
	match task:
		Task.MOVE:
			_lod_process_move(delta)
		Task.HARVEST:
			_lod_process_harvest(delta)
		Task.BUILD:
			_lod_process_build(delta)
		Task.DELIVER_TO_WAREHOUSE:
			_lod_process_warehouse_delivery(delta)
		Task.FETCH_FROM_WAREHOUSE:
			_lod_process_warehouse_fetch(delta)
		Task.ENTER_BUILDING:
			_lod_process_enter_building(delta)
		Task.FACTORY_WORK:
			_process_factory_work(delta)
		Task.REST:
			_process_rest(delta)
		_:
			_process_idle(delta)
	last_motion_position = global_position
	stuck_timer = 0.0


func _process_food_needs(delta: float):
	if delta <= 0.0 or health <= 0:
		return
	food_timer -= delta
	var meal_events := 0
	while food_timer <= 0.0 and meal_events < 64:
		if _consume_food_from_storage():
			missed_meals = 0
		else:
			missed_meals += 1
			health = maxi(health - STARVATION_DAMAGE, 0)
			if health <= 0:
				_die_from_starvation()
				return
		food_timer += FOOD_CONSUMPTION_INTERVAL
		meal_events += 1
	if meal_events >= 64 and food_timer <= 0.0:
		food_timer = FOOD_CONSUMPTION_INTERVAL


func _consume_food_from_storage() -> bool:
	var warehouses: Array[Building] = []
	for building in get_tree().get_nodes_in_group("buildings"):
		if building is Building and building.faction_id == faction_id and building.is_warehouse() and building.is_completed() and building.has_stored_resource(&"food"):
			warehouses.append(building)
	warehouses.sort_custom(func(a: Building, b: Building): return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	for warehouse in warehouses:
		if warehouse.take_resource(&"food", 1) == 1:
			return true
	return false


func _die_from_starvation():
	velocity = Vector2.ZERO
	if selected:
		deselect()
	queue_free()


func get_food_status_text() -> String:
	if missed_meals > 0:
		return "Голодает: пропущено приёмов пищи — %d" % missed_meals
	return "Сыт: следующий приём пищи через %d сек." % maxi(ceili(food_timer), 0)


func has_lod_focus_in(rect: Rect2) -> bool:
	if is_instance_valid(target_tree) and rect.has_point(target_tree.global_position):
		return true
	if is_instance_valid(target_building) and rect.has_point(target_building.global_position):
		return true
	if is_instance_valid(target_warehouse) and rect.has_point(target_warehouse.global_position):
		return true
	return task == Task.MOVE and rect.has_point(target_position)


func _move_toward(destination: Vector2, stop_distance := 3.0) -> bool:
	if global_position.distance_to(destination) <= stop_distance:
		velocity = Vector2.ZERO
		return true
	var direction := global_position.direction_to(destination)
	direction = (direction + _get_separation_force(direction) * 0.75).normalized()
	if direction.is_zero_approx():
		direction = global_position.direction_to(destination)
	velocity = direction * _get_current_movement_speed()
	move_and_slide()
	return false


func _get_current_movement_speed() -> float:
	return speed * ROAD_SPEED_MULTIPLIER if is_on_road else speed


func _update_road_movement_state(delta: float):
	if is_instance_valid(inside_building):
		is_on_road = false
		road_speed_check_timer = 0.0
		return
	road_speed_check_timer -= delta
	if road_speed_check_timer > 0.0:
		return
	road_speed_check_timer = ROAD_SPEED_CHECK_INTERVAL
	is_on_road = _is_on_completed_road()


func _is_on_completed_road() -> bool:
	if not is_inside_tree():
		return false
	# У дорог вне области отрисовки физическая форма отключена системой LOD.
	# Кэш клеток маршрута позволяет всё равно корректно учитывать такую дорогу.
	var nearby_roads: Array = road_segments_by_cell.get(_world_to_cell(global_position), [])
	for road in nearby_roads:
		if is_instance_valid(road) and road is RoadSegment and not road.under_construction and road.contains_world_point(global_position, ROAD_PATH_MARGIN):
			return true
	var query := PhysicsPointQueryParameters2D.new()
	query.position = global_position
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 1
	for hit in get_world_2d().direct_space_state.intersect_point(query, 16):
		var collider = hit.collider
		if collider is RoadSegment and not collider.under_construction:
			return true
	return false


func _get_separation_force(desired_direction: Vector2) -> Vector2:
	var force := Vector2.ZERO
	var nearby_units: Array = lod_manager.get_nearby_units(global_position) if is_instance_valid(lod_manager) and lod_manager.has_method("get_nearby_units") else get_tree().get_nodes_in_group("units")
	for other in nearby_units:
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


func _lod_process_move(delta: float):
	_lod_navigate_toward(target_position, delta, 3.0)
	if global_position.distance_to(target_position) <= 3.0:
		_finish_manual_move()


func _finish_manual_move():
	velocity = Vector2.ZERO
	idle_check_timer = AUTO_WORK_DELAY_AFTER_MANUAL_ORDER
	task = Task.IDLE


func _lod_navigate_toward(destination: Vector2, delta: float, stop_distance := 3.0) -> float:
	var remaining_time := delta
	# Уже рассчитанный маршрут сохраняется и проходится по тем же точкам. Для
	# далёкого приказа новый AStar не строится: стратегический LOD идёт напрямую.
	var path_matches := path_destination.distance_to(destination) <= 8.0
	if not path_matches:
		path_points = PackedVector2Array()
		path_index = 0
		path_destination = destination
	if path_matches and not path_points.is_empty() and path_index < path_points.size():
		while path_index < path_points.size() and remaining_time > 0.0:
			remaining_time = _lod_move_direct(path_points[path_index], remaining_time, 5.0)
			if global_position.distance_to(path_points[path_index]) <= 5.0:
				path_index += 1
			else:
				return 0.0
	return _lod_move_direct(destination, remaining_time, stop_distance)


func _lod_move_direct(destination: Vector2, delta: float, stop_distance: float) -> float:
	var distance := global_position.distance_to(destination)
	if distance <= stop_distance:
		velocity = Vector2.ZERO
		return delta
	var direction := global_position.direction_to(destination)
	if simulation_lod != SimulationLOD.FULL:
		# Крупный LOD-шаг может пройти несколько точек маршрута, поэтому статус
		# дороги обновляется у каждой точки, а не только один раз за весь тик.
		is_on_road = _is_on_completed_road()
	var movement_speed := _get_current_movement_speed()
	var travel_distance := minf(movement_speed * delta, distance - stop_distance)
	global_position += direction * travel_distance
	velocity = direction * movement_speed if travel_distance > 0.0 else Vector2.ZERO
	if travel_distance + stop_distance >= distance - 0.001:
		velocity = Vector2.ZERO
		return maxf(delta - travel_distance / maxf(movement_speed, 0.001), 0.0)
	return 0.0


func _update_motion_recovery(delta: float):
	var is_moving_task := task in [Task.MOVE, Task.HARVEST, Task.BUILD, Task.DELIVER_TO_WAREHOUSE, Task.FETCH_FROM_WAREHOUSE, Task.ENTER_BUILDING]
	if not is_moving_task or is_instance_valid(inside_building) or velocity.is_zero_approx():
		stuck_timer = 0.0
		last_motion_position = global_position
		return
	if global_position.distance_to(last_motion_position) < 0.35:
		stuck_timer += delta
	else:
		stuck_timer = 0.0
		last_motion_position = global_position
	if stuck_timer < 1.0:
		return

	# Перестраиваем маршрут и слегка смещаем юнита вбок, чтобы разорвать
	# взаимную блокировку нескольких CharacterBody2D в узком проходе.
	stuck_timer = 0.0
	var desired := velocity.normalized()
	if desired.is_zero_approx():
		desired = global_position.direction_to(path_destination)
	global_position += desired.orthogonal() * (10.0 if get_instance_id() % 2 == 0 else -10.0)
	path_points = PackedVector2Array()
	path_index = 0
	path_destination = Vector2(INF, INF)
	last_motion_position = global_position
func _calculate_path(destination: Vector2):
	path_destination = destination
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, PATH_MAP_SIZE)
	grid.cell_size = Vector2.ONE * PATH_CELL_SIZE
	grid.offset = Vector2.ONE * PATH_CELL_SIZE * 0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	_apply_road_path_weights(grid)

	for building in get_tree().get_nodes_in_group("buildings"):
		if building is not Building or building.building_kind == "road":
			continue
		var collision := building.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collision == null or collision.shape is not RectangleShape2D:
			continue
		var half_size: Vector2 = collision.shape.size * 0.5
		var world_minimum := Vector2(INF, INF)
		var world_maximum := Vector2(-INF, -INF)
		for corner in [Vector2(-half_size.x, -half_size.y), Vector2(half_size.x, -half_size.y), Vector2(half_size.x, half_size.y), Vector2(-half_size.x, half_size.y)]:
			var world_corner: Vector2 = collision.global_transform * corner
			world_minimum = world_minimum.min(world_corner)
			world_maximum = world_maximum.max(world_corner)
		var minimum := _world_to_cell(world_minimum - Vector2.ONE * 12.0)
		var maximum := _world_to_cell(world_maximum + Vector2.ONE * 12.0)
		for x in range(minimum.x, maximum.x + 1):
			for y in range(minimum.y, maximum.y + 1):
				var cell := Vector2i(x, y)
				if grid.region.has_point(cell):
					grid.set_point_weight_scale(cell, BUILDING_AVOIDANCE_WEIGHT)

	var start := _world_to_cell(global_position)
	var finish := _world_to_cell(destination)
	if not grid.region.has_point(start) or not grid.region.has_point(finish):
		path_points = PackedVector2Array()
		return
	grid.set_point_weight_scale(start, 1.0)
	grid.set_point_weight_scale(finish, 1.0)
	path_points = grid.get_point_path(start, finish)
	path_index = 0


func _apply_road_path_weights(grid: AStarGrid2D):
	road_segments_by_cell.clear()
	for road in get_tree().get_nodes_in_group("roads"):
		if road is not RoadSegment or road.under_construction:
			continue
		var collision := road.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collision == null or collision.shape is not RectangleShape2D:
			continue
		var rectangle := collision.shape as RectangleShape2D
		var half_size := rectangle.size * 0.5
		var world_minimum := Vector2(INF, INF)
		var world_maximum := Vector2(-INF, -INF)
		for corner in [Vector2(-half_size.x, -half_size.y), Vector2(half_size.x, -half_size.y), Vector2(half_size.x, half_size.y), Vector2(-half_size.x, half_size.y)]:
			var world_corner: Vector2 = collision.global_transform * corner
			world_minimum = world_minimum.min(world_corner)
			world_maximum = world_maximum.max(world_corner)
		var minimum := _world_to_cell(world_minimum - Vector2.ONE * ROAD_PATH_MARGIN)
		var maximum := _world_to_cell(world_maximum + Vector2.ONE * ROAD_PATH_MARGIN)
		var inverse_transform := collision.global_transform.affine_inverse()
		for x in range(minimum.x, maximum.x + 1):
			for y in range(minimum.y, maximum.y + 1):
				var cell := Vector2i(x, y)
				if not grid.region.has_point(cell):
					continue
				var cell_center := (Vector2(cell) + Vector2.ONE * 0.5) * PATH_CELL_SIZE
				var local_point := inverse_transform * cell_center
				if absf(local_point.x) <= half_size.x + ROAD_PATH_MARGIN and absf(local_point.y) <= half_size.y + ROAD_PATH_MARGIN:
					grid.set_point_weight_scale(cell, ROAD_PATH_WEIGHT)
					if not road_segments_by_cell.has(cell):
						road_segments_by_cell[cell] = []
					road_segments_by_cell[cell].append(road)


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


func _lod_process_harvest(delta: float):
	if not is_instance_valid(target_tree):
		_finish_harvest()
		return
	if is_instance_valid(target_building) and get_carried_resource_amount() >= _get_collection_target(harvest_resource_type):
		_finish_harvest()
		return
	var work_delta := _lod_navigate_toward(target_tree.global_position, delta, interaction_distance)
	if global_position.distance_to(target_tree.global_position) > interaction_distance + 0.01:
		target_tree.set_harvest_progress(self, 0.0)
		return
	work_timer -= work_delta
	var event_limit := mini(int(ceil(maxf(work_delta, 0.0) / maxf(harvest_interval, 0.01))) + 1, 64)
	for event_index in range(event_limit):
		if work_timer > 0.0 or not is_instance_valid(target_tree):
			break
		var harvested: int = target_tree.harvest(1)
		if harvest_resource_type == &"stone":
			carried_stone += harvested
		else:
			carried_wood += harvested
		work_timer += maxf(harvest_interval, 0.01)
		var enough_for_build := is_instance_valid(target_building) and get_carried_resource_amount() >= _get_collection_target(harvest_resource_type)
		if get_carried_total() >= carry_capacity or enough_for_build or harvested <= 0 or target_tree.is_depleted():
			_finish_harvest()
			break
	if is_instance_valid(target_tree):
		target_tree.set_harvest_progress(self, 1.0 - clampf(work_timer / maxf(harvest_interval, 0.01), 0.0, 1.0))


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


func _lod_process_build(delta: float):
	if not is_instance_valid(target_building) or target_building.is_completed():
		_advance_build_queue()
		return
	if target_building.needs_materials():
		var needed_type := target_building.get_needed_resource_type()
		harvest_resource_type = needed_type
		if get_carried_resource_amount() > 0:
			_lod_navigate_toward(target_building.get_approach_position(global_position), delta, 6.0)
			if global_position.distance_to(target_building.get_approach_position(global_position)) <= 6.01:
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
		var nearest_resource: Node2D = _find_nearest_resource(needed_type)
		if is_instance_valid(nearest_resource):
			_start_harvesting(nearest_resource)
		else:
			velocity = Vector2.ZERO
		return
	var approach := target_building.get_approach_position(global_position)
	var build_delta := _lod_navigate_toward(approach, delta, 6.0)
	if global_position.distance_to(approach) <= 6.01:
		target_building.add_build_progress(build_delta)


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


func _lod_process_warehouse_delivery(delta: float):
	if not is_instance_valid(target_warehouse) or not target_warehouse.has_resource_space(harvest_resource_type):
		_release_warehouse()
		task = Task.IDLE
		return
	var approach := target_warehouse.get_approach_position(global_position)
	_lod_navigate_toward(approach, delta, 6.0)
	if global_position.distance_to(approach) > 6.01:
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


func _lod_process_warehouse_fetch(delta: float):
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
	var approach := target_warehouse.get_approach_position(global_position)
	_lod_navigate_toward(approach, delta, 6.0)
	if global_position.distance_to(approach) > 6.01:
		return
	var needed := maxi(_get_collection_target(harvest_resource_type) - get_carried_resource_amount(), 0)
	var taken := target_warehouse.take_resource(harvest_resource_type, needed)
	if harvest_resource_type == &"stone":
		carried_stone += taken
	else:
		carried_wood += taken
	target_warehouse = null
	task = Task.BUILD


func _process_idle(delta: float):
	velocity = Vector2.ZERO
	idle_check_timer -= delta
	if idle_check_timer > 0.0:
		return
	idle_check_timer = 1.5 + float(get_instance_id() % 7) * 0.1
	_assign_automatic_job(true)


func _assign_automatic_job(allow_residence: bool) -> bool:
	var construction := _find_auto_construction()
	if is_instance_valid(construction):
		command_build(construction)
		return true

	var factory := _find_available_factory()
	if is_instance_valid(factory):
		command_enter_building(factory)
		return true

	if ai_controlled and _assign_ai_harvest_job():
		return true

	if allow_residence:
		var residence := _find_available_residence()
		if is_instance_valid(residence):
			command_enter_building(residence)
			return true
	return false


func _assign_ai_harvest_job() -> bool:
	var resource_types: Array[StringName] = [&"wood", &"stone"]
	if network_id % 3 == 0:
		resource_types.reverse()
	for resource_type in resource_types:
		var warehouse := _find_free_warehouse(resource_type)
		var resource: Node2D = _find_nearest_resource(resource_type)
		if not is_instance_valid(warehouse) or not is_instance_valid(resource) or not warehouse.assign_worker(self):
			continue
		target_warehouse = warehouse
		continuous_harvest = true
		harvest_resource_type = resource_type
		mining_job_resource_type = resource_type
		profession = "Каменотёс" if resource_type == &"stone" else "Лесоруб"
		_start_harvesting(resource)
		return true
	return false


func _find_auto_construction() -> Building:
	var nearest: Building
	var nearest_distance := INF
	for building in get_tree().get_nodes_in_group("buildings"):
		if building is not Building or building.faction_id != faction_id or not building.under_construction:
			continue
		var limit: int = 1 if building.building_kind == "road" else building.max_builders
		if building.active_builders.size() >= limit:
			continue
		var distance := global_position.distance_squared_to(building.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = building
	return nearest


func _find_available_factory() -> Building:
	var nearest: Building
	var nearest_distance := INF
	for building in get_tree().get_nodes_in_group("buildings"):
		if building is not Building or building.faction_id != faction_id or not building.is_factory() or not building.is_completed():
			continue
		if building.occupants.size() + _get_reserved_entry_count(building) >= building.get_worker_target() or not building.can_produce_selected_recipe():
			continue
		var distance := global_position.distance_squared_to(building.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = building
	return nearest


func _find_available_residence() -> Building:
	var nearest: Building
	var nearest_distance := INF
	for building in get_tree().get_nodes_in_group("buildings"):
		if building is not Building or building.faction_id != faction_id or not building.is_residence() or not building.is_completed():
			continue
		if building.occupants.size() + _get_reserved_entry_count(building) >= building.max_occupants:
			continue
		var distance := global_position.distance_squared_to(building.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = building
	return nearest


func _get_reserved_entry_count(building: Building) -> int:
	var reserved := 0
	for unit in get_tree().get_nodes_in_group("units"):
		if unit == self or unit is not Unit or unit.faction_id != faction_id:
			continue
		if unit.task == Task.ENTER_BUILDING and unit.target_building == building and not is_instance_valid(unit.inside_building):
			reserved += 1
	return reserved


func _process_enter_building():
	if not is_instance_valid(target_building) or not target_building.is_completed():
		target_building = null
		task = Task.IDLE
		return
	var entrance := target_building.get_approach_position(global_position)
	if not _navigate_toward(entrance, 6.0):
		return
	if not target_building.try_enter(self):
		target_building = null
		task = Task.IDLE
		return
	inside_building = target_building
	global_position = inside_building.global_position
	velocity = Vector2.ZERO
	_refresh_lod_presentation()
	if inside_building.is_factory():
		production_timer = inside_building.get_production_time()
		task = Task.FACTORY_WORK
	else:
		idle_check_timer = 2.0
		task = Task.REST


func _lod_process_enter_building(delta: float):
	if not is_instance_valid(target_building) or not target_building.is_completed():
		target_building = null
		task = Task.IDLE
		return
	var entrance := target_building.get_approach_position(global_position)
	_lod_navigate_toward(entrance, delta, 6.0)
	if global_position.distance_to(entrance) > 6.01:
		return
	if not target_building.try_enter(self):
		target_building = null
		task = Task.IDLE
		return
	inside_building = target_building
	global_position = inside_building.global_position
	velocity = Vector2.ZERO
	_refresh_lod_presentation()
	if inside_building.is_factory():
		production_timer = inside_building.get_production_time()
		task = Task.FACTORY_WORK
	else:
		idle_check_timer = 2.0
		task = Task.REST


func _process_factory_work(delta: float):
	velocity = Vector2.ZERO
	if not is_instance_valid(inside_building) or not inside_building.is_factory():
		_exit_current_building()
		task = Task.IDLE
		return
	production_timer -= delta
	var production_events := 0
	while production_timer <= 0.0 and production_events < 64:
		if not inside_building.can_produce_selected_recipe():
			# Закреплённый рабочий ждёт сырьё или место на складе внутри завода.
			# Он покинет рабочее место только по прямому приказу игрока.
			production_timer = 1.0
			return
		if inside_building.produce_selected_recipe():
			produced_items += 1
		production_timer += maxf(inside_building.get_production_time(), 0.01)
		production_events += 1


func _process_rest(delta: float):
	velocity = Vector2.ZERO
	if not is_instance_valid(inside_building) or not inside_building.is_residence():
		_exit_current_building()
		task = Task.IDLE
		return
	idle_check_timer -= delta
	if idle_check_timer > 0.0:
		return
	idle_check_timer = 2.0
	if _has_automatic_work():
		_exit_current_building()
		task = Task.IDLE
		_assign_automatic_job(false)


func _has_automatic_work() -> bool:
	return is_instance_valid(_find_auto_construction()) or is_instance_valid(_find_available_factory())


func command_enter_building(building: Building):
	if not is_instance_valid(building) or building.faction_id != faction_id or not building.is_completed():
		return
	_cancel_task()
	if building.is_factory():
		profession = "Рабочий завода"
	target_building = building
	path_destination = Vector2(INF, INF)
	task = Task.ENTER_BUILDING


func settle_in_residence(residence: Building) -> bool:
	if not is_instance_valid(residence) or not residence.is_residence() or residence.faction_id != faction_id or not residence.is_completed():
		return false
	_cancel_task()
	if not residence.try_enter(self):
		return false
	inside_building = residence
	target_building = residence
	global_position = residence.global_position
	velocity = Vector2.ZERO
	idle_check_timer = 2.0
	task = Task.REST
	_refresh_lod_presentation()
	return true


func _exit_current_building():
	if not is_instance_valid(inside_building):
		inside_building = null
		_refresh_lod_presentation()
		return
	var building := inside_building
	var exit_position := building.get_exit_position(self)
	building.leave(self)
	inside_building = null
	global_position = exit_position
	target_position = global_position
	path_points = PackedVector2Array()
	path_index = 0
	path_destination = Vector2(INF, INF)
	_refresh_lod_presentation()
	last_motion_position = global_position


func force_exit_building(building: Building):
	if inside_building != building:
		return
	_exit_current_building()
	target_building = null
	idle_check_timer = AUTO_WORK_DELAY_AFTER_MANUAL_ORDER
	task = Task.IDLE


func on_building_dismantled(building: Building):
	for index in range(build_queue.size() - 1, -1, -1):
		if build_queue[index] == building:
			build_queue.remove_at(index)
	var affected := inside_building == building or target_building == building or target_warehouse == building
	if not affected:
		return
	_cancel_task()
	velocity = Vector2.ZERO
	target_position = global_position
	path_points = PackedVector2Array()
	path_index = 0
	path_destination = Vector2(INF, INF)
	idle_check_timer = AUTO_WORK_DELAY_AFTER_MANUAL_ORDER
	task = Task.IDLE


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


func _find_nearest_resource(resource_type: StringName) -> Node2D:
	if is_instance_valid(lod_manager) and lod_manager.has_method("find_nearest_resource"):
		var indexed_resource = lod_manager.find_nearest_resource(resource_type, global_position)
		if is_instance_valid(indexed_resource):
			return indexed_resource
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
		if building is not Building or building.faction_id != faction_id or not building.can_accept_worker(resource_type):
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
		if building is not Building or building.faction_id != faction_id or not building.has_stored_resource(resource_type):
			continue
		var distance := global_position.distance_squared_to(building.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = building
	return nearest


func _get_collection_target(resource_type: StringName) -> int:
	if not is_instance_valid(target_building):
		return 0
	var total_remaining := target_building.get_remaining_resource(resource_type)

	var carried_by_others := 0
	for unit in get_tree().get_nodes_in_group("units"):
		if unit == self or unit is not Unit or unit.faction_id != faction_id:
			continue
		# Материалы резервируются только внутри одной стройки. Раньше груз
		# одного дорожного строителя блокировал всех строителей той же линии.
		if unit.target_building != target_building:
			continue
		carried_by_others += unit.carried_stone if resource_type == &"stone" else unit.carried_wood

	var available_capacity := carry_capacity - (get_carried_total() - get_carried_resource_amount())
	return mini(maxi(total_remaining - carried_by_others, 0), available_capacity)


func _cancel_task():
	if is_instance_valid(inside_building):
		_exit_current_building()
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
	target_position = _get_reachable_destination(destination)
	_calculate_path(target_position)
	task = Task.MOVE


func _get_reachable_destination(destination: Vector2) -> Vector2:
	for building in get_tree().get_nodes_in_group("buildings"):
		if building is Building and building.building_kind != "road" and building.contains_world_point(destination, 4.0):
			return building.get_approach_position(global_position)
	return destination


func command_harvest(tree: Node2D):
	_cancel_task()
	harvest_resource_type = tree.get_resource_type()
	mining_job_resource_type = harvest_resource_type
	profession = "Каменотёс" if harvest_resource_type == &"stone" else "Лесоруб"
	var warehouse := _find_free_warehouse(harvest_resource_type)
	if continuous_harvest_mode and is_instance_valid(warehouse) and warehouse.assign_worker(self):
		target_warehouse = warehouse
		continuous_harvest = true
	_start_harvesting(tree)


func command_build(building: Building):
	if not is_instance_valid(building) or building.faction_id != faction_id:
		return
	_cancel_task()
	profession = "Строитель"
	build_job_kind = building.building_kind
	if building.try_assign_builder(self):
		target_building = building
		task = Task.BUILD
	else:
		_advance_build_queue()


func command_build_line(segments: Array[Building]):
	_cancel_task()
	var own_segments: Array[Building] = []
	for segment in segments:
		if is_instance_valid(segment) and segment.faction_id == faction_id:
			own_segments.append(segment)
	if own_segments.is_empty():
		return
	profession = "Строитель"
	build_job_kind = own_segments[0].building_kind
	for segment in own_segments:
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
			if building is not Building or building.faction_id != faction_id or building.building_kind != build_job_kind or not building.under_construction:
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
	if not can_be_controlled_locally():
		return
	if not additive:
		clear_selection()
	Building.selected_building = null
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
		Task.HARVEST: return "Добывает камень" if harvest_resource_type == &"stone" else "Рубит дерево"
		Task.BUILD: return "Строит"
		Task.DELIVER_TO_WAREHOUSE: return "Несёт ресурс на склад"
		Task.FETCH_FROM_WAREHOUSE: return "Берёт материал со склада"
		Task.ENTER_BUILDING: return "Заходит в здание"
		Task.FACTORY_WORK: return "Работает на заводе"
		Task.REST: return "Находится дома"
		_: return "Свободен"


func get_profession_text() -> String:
	return profession


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
	var controllable_units: Array[Unit] = []
	for unit in units:
		if is_instance_valid(unit) and unit.can_be_controlled_locally():
			controllable_units.append(unit)
	if not controllable_units.is_empty():
		Building.selected_building = null
	for unit in controllable_units:
		unit.selected = true
		unit.selection.visible = true
		selected_units.append(unit)
	selected_unit = selected_units.back() if not selected_units.is_empty() else null
