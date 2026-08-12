class_name Unit
extends CharacterBody2D

const TREE_HARVEST_SOUND := preload("res://assets/sounds/tree harvest.mp3")
const ROCK_HARVEST_SOUND := preload("res://assets/sounds/rock harvest.mp3")

enum Task { IDLE, MOVE, HARVEST, BUILD, DELIVER_TO_WAREHOUSE, FETCH_FROM_WAREHOUSE, ENTER_BUILDING, FACTORY_WORK, REST }
enum SimulationLOD { FULL, REDUCED, STRATEGIC, BACKGROUND }

@export var speed := 100.0
@export var carry_capacity := 10
@export var interaction_distance := 20.0
@export var harvest_interval := 0.5
@export_range(100.0, 1200.0, 10.0) var harvest_sound_max_distance := 480.0
@export_range(-30.0, 6.0, 0.5) var harvest_sound_volume_db := -7.0
@export_range(0.5, 1.5, 0.01) var harvest_pitch_min := 0.9
@export_range(0.5, 1.5, 0.01) var harvest_pitch_max := 1.1
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
const AI_STARVATION_GRACE_MEALS := 3
const AUTO_WORK_DELAY_AFTER_MANUAL_ORDER := 5.0
const ROAD_SPEED_MULTIPLIER := 1.5
const ROAD_SPEED_CHECK_INTERVAL := 0.12
const ROAD_PATH_MARGIN := 8.0
const SQUAD_COMMAND_INTERVAL := 0.3
const SQUAD_COMMAND_TIMEOUT := 5.0
const SQUAD_FOLLOW_STOP_DISTANCE := 2.0
const SQUAD_FOLLOW_SPEED_MULTIPLIER := 1.12
const SQUAD_FOLLOW_CORRECTION_RATE := 2.2
const SQUAD_FOLLOW_VELOCITY_RESPONSE := 7.0
const SQUAD_SPREAD_RADIUS := 140.0
const SQUAD_SPREAD_MIN_DISTANCE := 36.0
const SQUAD_DEFAULT_OFFSET_RADIUS := 78.0
const SQUAD_LINE_DEPTH_JITTER := 18.0
const PLATOON_COMMANDER_REAR_DISTANCE := 112.0
const PLATOON_COMMANDER_THREAT_DISTANCE := 520.0
const PLATOON_COMMANDER_REPATH_DISTANCE := 18.0
const MILITARY_ROLE_TEMPLATES := {
	&"rifleman": {"name": "Стрелок", "equipment": {&"rifles": 1, &"armor": 1}},
	&"medic": {"name": "Медик", "equipment": {&"rifles": 1, &"armor": 1}},
	&"grenadier": {"name": "Гранатомётчик", "equipment": {&"rifles": 1, &"armor": 1}},
	&"commander": {"name": "Командир", "equipment": {&"rifles": 1, &"armor": 1}},
	&"platoon_commander": {"name": "Командир взвода", "equipment": {&"armor": 1}},
}

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
var is_mobilized := false
var military_role: StringName = &"rifleman"
var military_rank := "Гражданский"
var squad_id := 0
var platoon_id := 0
var squad_commander_network_id := 0
var platoon_commander_network_id := 0
var military_order: StringName = &"hold"
var squad_formation_offset := Vector2.ZERO
var squad_follow_target := Vector2.ZERO
var squad_commander_unit: Unit
var squad_follow_active := false
var squad_independent_order := false
var squad_line_direction := Vector2.ZERO
var squad_command_timer := 0.0
var squad_command_timeout := 0.0
var platoon_rear_direction := Vector2.ZERO
var has_platoon_front_line := false
var platoon_front_start := Vector2.ZERO
var platoon_front_end := Vector2.ZERO
var has_platoon_offensive_line := false
var platoon_offensive_start := Vector2.ZERO
var platoon_offensive_end := Vector2.ZERO
var has_armor := false
var has_rifle := false
var facing_direction := Vector2.DOWN
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
var world_index: Node
var world_navigation: WorldNavigation
var world_audio_pool: Node
var is_on_road := false
var road_speed_check_timer := 0.0
var muzzle_flash_until_msec := 0

const FACTION_COLORS: Array[Color] = [
	Color(1.0, 1.0, 1.0),
	Color(1.0, 0.62, 0.62),
	Color(0.62, 0.78, 1.0),
	Color(1.0, 0.86, 0.48),
]

@onready var selection: Sprite2D = $selection
@onready var body: Sprite2D = $body
@onready var armor_sprite: Sprite2D = $armor
@onready var weapon_sprite: Sprite2D = $weapon
@onready var beret_sprite: Sprite2D = $beret
@onready var green_beret_sprite: Sprite2D = $greenberet
@onready var muzzle_flash_sprite: Sprite2D = $muzzleflash
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
	# Новые жители не принимают решения и не едят в одном кадре. Средняя
	# частота остаётся прежней, исчезают периодические пики большой толпы.
	if is_equal_approx(idle_check_timer, 1.0):
		idle_check_timer = 0.35 + float(get_instance_id() % 17) * 0.08
	if is_equal_approx(food_timer, FOOD_CONSUMPTION_INTERVAL):
		food_timer = FOOD_CONSUMPTION_INTERVAL * (0.9 + float(get_instance_id() % 21) * 0.01)
	selection.visible = false
	lod_manager = get_tree().get_first_node_in_group("simulation_lod_manager")
	world_index = get_tree().get_first_node_in_group("world_index")
	world_navigation = get_tree().get_first_node_in_group("world_navigation") as WorldNavigation
	world_audio_pool = get_tree().get_first_node_in_group("world_audio_pool")
	if is_instance_valid(world_index):
		world_index.register_unit(self)
	_update_faction_visual()
	_update_equipment_visuals()
	_set_facing_direction(facing_direction)


func configure_faction(new_faction_id: int, new_controller_peer_id: int, is_ai: bool, new_faction_name: String):
	var previous_faction_id := faction_id
	faction_id = clampi(new_faction_id, 0, 3)
	controller_peer_id = new_controller_peer_id
	ai_controlled = is_ai
	faction_name = new_faction_name
	if is_instance_valid(world_index):
		world_index.refresh_unit_faction(self, previous_faction_id)
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


func _update_equipment_visuals():
	if is_instance_valid(armor_sprite):
		armor_sprite.visible = has_armor
	if is_instance_valid(weapon_sprite):
		weapon_sprite.visible = has_rifle
	if is_instance_valid(beret_sprite):
		beret_sprite.visible = is_squad_commander() and not is_dedicated_platoon_commander()
	if is_instance_valid(green_beret_sprite):
		green_beret_sprite.visible = is_dedicated_platoon_commander()
	if is_instance_valid(muzzle_flash_sprite) and not has_rifle:
		muzzle_flash_sprite.visible = false


func set_military_equipment(armor_equipped: bool, rifle_equipped: bool):
	has_armor = armor_equipped
	has_rifle = rifle_equipped
	if is_node_ready():
		_update_equipment_visuals()


func refresh_military_visuals():
	if is_node_ready():
		_update_equipment_visuals()


func _set_facing_direction(direction: Vector2):
	if direction.is_zero_approx():
		return
	facing_direction = direction.normalized()
	var equipment_rotation := facing_direction.angle() - PI * 0.5
	if is_instance_valid(weapon_sprite):
		weapon_sprite.rotation = equipment_rotation
	if is_instance_valid(muzzle_flash_sprite):
		muzzle_flash_sprite.rotation = equipment_rotation


func play_weapon_muzzle_flash(duration := 0.07):
	if not has_rifle or not is_instance_valid(muzzle_flash_sprite):
		return
	muzzle_flash_sprite.visible = true
	muzzle_flash_until_msec = Time.get_ticks_msec() + int(maxf(duration, 0.01) * 1000.0)


func _hide_muzzle_flash():
	muzzle_flash_until_msec = 0
	if is_instance_valid(muzzle_flash_sprite):
		muzzle_flash_sprite.visible = false


func _update_muzzle_flash():
	if muzzle_flash_until_msec > 0 and Time.get_ticks_msec() >= muzzle_flash_until_msec:
		_hide_muzzle_flash()


func _exit_tree():
	if is_instance_valid(world_index):
		world_index.unregister_unit(self)
	if is_instance_valid(target_tree):
		target_tree.stop_harvest(self)
	if is_instance_valid(inside_building):
		inside_building.leave(self)
	_release_warehouse()


func _physics_process(delta: float):
	if simulation_lod != SimulationLOD.FULL:
		return
	_update_muzzle_flash()
	_process_food_needs(delta)
	if health <= 0:
		return
	_update_road_movement_state(delta)
	_process_squad_leadership(delta)
	if _process_squad_following(delta):
		_update_motion_recovery(delta)
		return
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
	if not visible or (muzzle_flash_until_msec > 0 and Time.get_ticks_msec() >= muzzle_flash_until_msec):
		_hide_muzzle_flash()
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
	_process_squad_leadership(delta)
	if _lod_process_squad_following(delta):
		last_motion_position = global_position
		stuck_timer = 0.0
		return
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


func apply_network_motion(server_position: Vector2, server_velocity: Vector2):
	var position_error := global_position.distance_to(server_position)
	if position_error > 96.0:
		global_position = server_position
	elif position_error > 4.0:
		global_position = global_position.lerp(server_position, 0.35)
	velocity = server_velocity
	if not server_velocity.is_zero_approx():
		_set_facing_direction(server_velocity)


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
			if not ai_controlled or missed_meals > AI_STARVATION_GRACE_MEALS:
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
	for building in _get_indexed_buildings("warehouse"):
		if building is Building and building.faction_id == faction_id and building.is_warehouse() and building.is_completed() and building.has_stored_resource(&"food"):
			warehouses.append(building)
	warehouses.sort_custom(func(a: Building, b: Building): return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	for warehouse in warehouses:
		if warehouse.take_resource(&"food", 1) == 1:
			return true
	return false


func _get_indexed_buildings(building_kind := "") -> Array:
	if not is_instance_valid(world_index):
		world_index = get_tree().get_first_node_in_group("world_index")
	if is_instance_valid(world_index):
		return world_index.get_buildings(faction_id, building_kind)
	var result: Array[Building] = []
	for candidate in get_tree().get_nodes_in_group("buildings"):
		if candidate is Building and candidate.faction_id == faction_id and (building_kind.is_empty() or candidate.building_kind == building_kind):
			result.append(candidate)
	return result


func _get_indexed_units() -> Array:
	if not is_instance_valid(world_index):
		world_index = get_tree().get_first_node_in_group("world_index")
	if is_instance_valid(world_index):
		return world_index.get_units(faction_id)
	var result: Array[Unit] = []
	for candidate in get_tree().get_nodes_in_group("units"):
		if candidate is Unit and candidate.faction_id == faction_id:
			result.append(candidate)
	return result


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


func is_lod_exempt_worker() -> bool:
	# Добытчики и активные строители всегда используют полную симуляцию.
	# Проверяются все промежуточные задачи рабочего цикла: путь к ресурсу,
	# доставка на склад, получение материалов и непосредственно строительство.
	if continuous_harvest:
		return true
	if task in [Task.HARVEST, Task.DELIVER_TO_WAREHOUSE, Task.FETCH_FROM_WAREHOUSE, Task.BUILD]:
		return true
	return is_instance_valid(target_building) and target_building.under_construction


func needs_frequent_offscreen_simulation() -> bool:
	# Постоянный приказ добычи должен продолжать весь цикл за камерой:
	# дойти до ресурса, заполнить инвентарь, разгрузиться и выбрать следующую
	# цель. Активные работы ИИ также нельзя оставлять на редком фоновом тике.
	if continuous_harvest:
		return true
	# Any unit that is physically travelling must keep the reduced tick rate.
	# Otherwise a manual move or an entrance order can spend long periods on a
	# strategic tick and appear to stop whenever the camera leaves the area.
	if task in [Task.MOVE, Task.HARVEST, Task.BUILD, Task.DELIVER_TO_WAREHOUSE, Task.FETCH_FROM_WAREHOUSE, Task.ENTER_BUILDING]:
		return true
	return squad_follow_active and _can_follow_squad_commander()


func needs_reliable_offscreen_simulation() -> bool:
	# Даже без текущего пути ИИ должен продолжать выбирать работу, производить
	# ресурсы и выходить из дома. Для этого достаточно стратегической частоты.
	return ai_controlled or needs_frequent_offscreen_simulation()


func _move_toward(destination: Vector2, stop_distance := 3.0) -> bool:
	if global_position.distance_to(destination) <= stop_distance:
		velocity = Vector2.ZERO
		return true
	var destination_direction := global_position.direction_to(destination)
	var separation := _get_separation_force(destination_direction) * 0.75
	# Расхождение с соседями должно уводить юнита в сторону, но не обратно от
	# текущей точки маршрута. В плотной группе сумма сил раньше могла полностью
	# развернуть направление движения и вызывать заметный рывок назад.
	var backward_component := separation.dot(destination_direction)
	if backward_component < 0.0:
		separation -= destination_direction * backward_component
	var direction := (destination_direction + separation).normalized()
	if direction.is_zero_approx():
		direction = destination_direction
	_set_facing_direction(direction)
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
	if not is_instance_valid(world_navigation):
		world_navigation = get_tree().get_first_node_in_group("world_navigation") as WorldNavigation
	if is_instance_valid(world_navigation) and world_navigation.has_completed_road_at(global_position, ROAD_PATH_MARGIN):
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
		if not is_instance_valid(other) or other == self or other is not Unit:
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
	_spread_squad_after_arrival()


func _lod_navigate_toward(destination: Vector2, delta: float, stop_distance := 3.0, repath_distance := 8.0) -> float:
	var remaining_time := delta
	# Уже рассчитанный маршрут сохраняется и проходится по тем же точкам. Новый
	# AStar строится только при заметном изменении цели, а не на каждом LOD-тике.
	var path_matches := path_destination.distance_to(destination) <= repath_distance
	if not path_matches:
		# Jobs can change their destination while already off-screen (resource ->
		# warehouse -> construction, or home -> factory). Build a real route at
		# that transition instead of walking straight through buildings and then
		# becoming stuck when FULL simulation is restored.
		_calculate_path(destination)
		path_matches = true
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
	_set_facing_direction(direction)
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
	if not is_instance_valid(world_navigation):
		world_navigation = get_tree().get_first_node_in_group("world_navigation") as WorldNavigation
	if not is_instance_valid(world_navigation):
		path_points = PackedVector2Array()
		return
	path_points = world_navigation.find_path(global_position, destination)
	# AStarGrid2D всегда возвращает центр стартовой клетки первой точкой. Юнит
	# уже находится внутри этой клетки, и движение к её центру иногда выглядит
	# как короткий рывок назад при создании или перестроении маршрута.
	path_index = 1 if path_points.size() > 1 else path_points.size()


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
	var harvested: int = target_tree.harvest(1, faction_id)
	if harvested > 0:
		_play_harvest_sound()
	if harvest_resource_type == &"stone":
		carried_stone += harvested
	else:
		carried_wood += harvested
	var enough_for_build := is_instance_valid(target_building) and get_carried_resource_amount() >= _get_collection_target(harvest_resource_type)
	if get_carried_total() >= carry_capacity or enough_for_build or not is_instance_valid(target_tree) or target_tree.is_depleted():
		_finish_harvest()


func _play_harvest_sound():
	if not is_instance_valid(world_audio_pool):
		world_audio_pool = get_tree().get_first_node_in_group("world_audio_pool")
	if not is_instance_valid(world_audio_pool):
		return
	var minimum_pitch := minf(harvest_pitch_min, harvest_pitch_max)
	var maximum_pitch := maxf(harvest_pitch_min, harvest_pitch_max)
	world_audio_pool.play_spatial(
		ROCK_HARVEST_SOUND if harvest_resource_type == &"stone" else TREE_HARVEST_SOUND,
		global_position,
		harvest_sound_max_distance,
		harvest_sound_volume_db + randf_range(-1.5, 1.0),
		randf_range(minimum_pitch, maximum_pitch)
	)


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
		var harvested: int = target_tree.harvest(1, faction_id)
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
	elif continuous_harvest:
		_resume_priority_harvest_order()
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
	if is_mobilized:
		_set_automatic_guard_direction()
	idle_check_timer -= delta
	if idle_check_timer > 0.0:
		return
	idle_check_timer = 1.5 + float(get_instance_id() % 7) * 0.1
	_assign_automatic_job(true)


func _set_automatic_guard_direction():
	if not squad_formation_offset.is_zero_approx():
		_set_facing_direction(squad_formation_offset)
		return
	var direction_index := posmod(network_id * 5 + squad_id * 3, 16)
	_set_facing_direction(Vector2.from_angle(-PI * 0.5 + TAU * float(direction_index) / 16.0))


func _assign_automatic_job(allow_residence: bool) -> bool:
	# Выданный приказ добычи остаётся главным заданием, даже если ресурс
	# закончился или на складе временно нет места. Автоматические стройка,
	# завод и возвращение домой не могут его перезаписать.
	if continuous_harvest and not is_mobilized:
		return _resume_priority_harvest_order()
	if is_mobilized:
		# Полевые отряды не возвращаются в казарму самостоятельно. Возврат
		# выполняется только после приказа командира через меню войск.
		if military_order == &"return_to_base":
			var barracks := _find_available_barracks()
			if is_instance_valid(barracks):
				command_enter_building(barracks)
				return true
		return false

	# Для ИИ уже запущенная шахта/энергетика/еда важнее новой стройки.
	# Стратегия ограничивает число мест, поэтому строители всё равно остаются.
	var factory: Building = _find_available_factory() if ai_controlled else null
	if is_instance_valid(factory):
		command_enter_building(factory)
		return true

	var construction := _find_auto_construction()
	if is_instance_valid(construction):
		command_build(construction)
		return true

	if not ai_controlled:
		factory = _find_available_factory()
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
	var nearest_priority := 100
	var active_road_builders := 0
	if ai_controlled:
		for candidate in _get_indexed_buildings("road"):
			if candidate is Building and candidate.under_construction:
				active_road_builders += candidate.active_builders.size()
	for building in _get_indexed_buildings():
		if building is not Building or building.faction_id != faction_id or not building.under_construction:
			continue
		if ai_controlled and building.building_kind == "road" and active_road_builders >= 2:
			continue
		var limit: int = 1 if building.building_kind == "road" else building.max_builders
		if building.active_builders.size() >= limit:
			continue
		var priority := _get_ai_construction_priority(building) if ai_controlled else 0
		var distance := global_position.distance_squared_to(building.global_position)
		if priority < nearest_priority or (priority == nearest_priority and distance < nearest_distance):
			nearest_priority = priority
			nearest_distance = distance
			nearest = building
	return nearest


func _get_ai_construction_priority(building: Building) -> int:
	match building.building_kind:
		"power_plant": return 0
		"food_factory": return 1
		"mine": return 2
		"lumberjack_cabin": return 3
		"residence": return 4
		"road": return 5
		_: return 6


func _find_available_factory() -> Building:
	var nearest: Building
	var nearest_distance := INF
	var nearest_priority := 100
	for building in _get_indexed_buildings():
		if building is not Building or building.faction_id != faction_id or not building.is_factory() or not building.is_completed():
			continue
		if building.occupants.size() + _get_reserved_entry_count(building) >= building.get_worker_target():
			continue
		# The cabin owns its long-running forestry cycle, so it intentionally does
		# not report a factory recipe as immediately producible.
		if not building.is_lumberjack_cabin() and not building.can_produce_selected_recipe():
			continue
		var priority := 0 if building.is_mine() else (1 if building.is_power_plant() else (2 if building.is_food_factory() else (3 if building.is_lumberjack_cabin() else 4)))
		var distance := global_position.distance_squared_to(building.global_position)
		if priority < nearest_priority or (priority == nearest_priority and distance < nearest_distance):
			nearest_priority = priority
			nearest_distance = distance
			nearest = building
	return nearest


func _find_available_residence() -> Building:
	var nearest: Building
	var nearest_distance := INF
	for building in _get_indexed_buildings("residence"):
		if building is not Building or building.faction_id != faction_id or not building.is_residence() or not building.is_completed():
			continue
		if building.occupants.size() + _get_reserved_entry_count(building) >= building.max_occupants:
			continue
		var distance := global_position.distance_squared_to(building.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = building
	return nearest


func _find_available_barracks() -> Building:
	var nearest: Building
	var nearest_distance := INF
	for building in _get_indexed_buildings("barracks"):
		if building is not Building or building.faction_id != faction_id or not building.is_barracks() or not building.is_completed():
			continue
		if building.occupants.size() + _get_reserved_entry_count(building) >= building.max_occupants:
			continue
		var distance := global_position.distance_squared_to(building.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = building
	return nearest


func _get_reserved_entry_count(building: Building) -> int:
	if is_instance_valid(world_index):
		return world_index.get_reserved_entry_count(building, self)
	var reserved := 0
	for unit in _get_indexed_units():
		if not is_instance_valid(unit) or unit == self or unit is not Unit or unit.faction_id != faction_id:
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
	if not is_instance_valid(inside_building):
		_exit_current_building()
		task = Task.IDLE
		return
	if inside_building.is_barracks():
		if not is_mobilized:
			_exit_current_building()
			task = Task.IDLE
		return
	if not inside_building.is_residence() or is_mobilized:
		_exit_current_building()
		task = Task.IDLE
		return
	idle_check_timer -= delta
	if idle_check_timer > 0.0:
		return
	idle_check_timer = 2.0
	# Житель остаётся закреплённым за домом, пока для него действительно не
	# найдено и не зарезервировано место на стройке или заводе.
	_assign_automatic_job(false)


func command_enter_building(building: Building):
	if not is_instance_valid(building) or building.faction_id != faction_id or not building.is_completed():
		return
	if is_mobilized and not building.is_barracks():
		return
	if not is_mobilized and building.is_barracks():
		return
	_cancel_task()
	if building.is_factory():
		profession = "Рабочий завода"
	target_building = building
	path_destination = Vector2(INF, INF)
	task = Task.ENTER_BUILDING


func settle_in_residence(residence: Building) -> bool:
	if is_mobilized or not is_instance_valid(residence) or not residence.is_residence() or residence.faction_id != faction_id or not residence.is_completed():
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


func settle_in_barracks(barracks: Building) -> bool:
	if not is_mobilized or not is_instance_valid(barracks) or not barracks.is_barracks() or barracks.faction_id != faction_id or not barracks.is_completed():
		return false
	_cancel_task()
	if not barracks.try_enter(self):
		return false
	inside_building = barracks
	target_building = barracks
	global_position = barracks.global_position
	velocity = Vector2.ZERO
	idle_check_timer = 2.0
	task = Task.REST
	_refresh_lod_presentation()
	return true


func restore_inside_building(building: Building, saved_production_timer: float) -> bool:
	if not is_instance_valid(building) or building.faction_id != faction_id or not building.is_completed():
		return false
	_cancel_task()
	if not building.try_enter(self):
		return false
	inside_building = building
	target_building = building
	global_position = building.global_position
	velocity = Vector2.ZERO
	target_position = global_position
	path_points = PackedVector2Array()
	path_index = 0
	path_destination = Vector2(INF, INF)
	if building.is_factory():
		production_timer = saved_production_timer if saved_production_timer > 0.0 else building.get_production_time()
		task = Task.FACTORY_WORK
	else:
		idle_check_timer = 2.0
		task = Task.REST
	_refresh_lod_presentation()
	return true


func mobilize(barracks: Building = null) -> bool:
	if health <= 0:
		return false
	_cancel_task()
	is_mobilized = true
	simulation_importance = maxi(simulation_importance, 1)
	profession = "Военнослужащий"
	military_role = &"rifleman"
	military_rank = "Солдат"
	squad_id = 0
	platoon_id = 0
	squad_commander_network_id = 0
	platoon_commander_network_id = 0
	military_order = &"hold"
	squad_formation_offset = Vector2.ZERO
	squad_independent_order = false
	squad_line_direction = Vector2.ZERO
	platoon_rear_direction = Vector2.ZERO
	has_platoon_front_line = false
	has_platoon_offensive_line = false
	_stop_following_squad_commander()
	refresh_military_visuals()
	if is_instance_valid(barracks) and settle_in_barracks(barracks):
		return true
	idle_check_timer = AUTO_WORK_DELAY_AFTER_MANUAL_ORDER
	task = Task.IDLE
	return true


func demobilize():
	_cancel_task()
	is_mobilized = false
	simulation_importance = 0
	profession = "Безработный"
	military_role = &"rifleman"
	military_rank = "Гражданский"
	squad_id = 0
	platoon_id = 0
	squad_commander_network_id = 0
	platoon_commander_network_id = 0
	military_order = &"hold"
	squad_formation_offset = Vector2.ZERO
	squad_independent_order = false
	squad_line_direction = Vector2.ZERO
	platoon_rear_direction = Vector2.ZERO
	has_platoon_front_line = false
	has_platoon_offensive_line = false
	_stop_following_squad_commander()
	refresh_military_visuals()
	velocity = Vector2.ZERO
	target_position = global_position
	idle_check_timer = AUTO_WORK_DELAY_AFTER_MANUAL_ORDER
	task = Task.IDLE


func is_squad_commander() -> bool:
	return is_mobilized and squad_id > 0 and network_id == squad_commander_network_id


func is_platoon_commander() -> bool:
	return is_mobilized and platoon_id > 0 and network_id == platoon_commander_network_id


func is_dedicated_platoon_commander() -> bool:
	return is_platoon_commander() and military_role == &"platoon_commander"


func _process_squad_leadership(delta: float):
	if is_dedicated_platoon_commander():
		_process_platoon_commander_position(delta)
		return
	if not is_squad_commander():
		return
	squad_command_timer -= delta
	if squad_command_timer > 0.0:
		return
	squad_command_timer = SQUAD_COMMAND_INTERVAL
	_broadcast_squad_follow_targets()


func _process_platoon_commander_position(delta: float):
	if military_order in [&"move", &"return_to_base"]:
		return
	squad_command_timer -= delta
	if squad_command_timer > 0.0:
		return
	squad_command_timer = SQUAD_COMMAND_INTERVAL
	var squad_commanders := _get_platoon_squad_commanders()
	for index in range(squad_commanders.size() - 1, -1, -1):
		if is_instance_valid(squad_commanders[index].inside_building):
			squad_commanders.remove_at(index)
	if squad_commanders.is_empty():
		return
	var center := Vector2.ZERO
	var advance_direction := Vector2.ZERO
	for commander in squad_commanders:
		center += commander.global_position
		if commander.task == Task.MOVE:
			advance_direction += commander.global_position.direction_to(commander.target_position)
	center /= float(squad_commanders.size())
	var nearest_enemy := _find_nearest_enemy_to_platoon(center)
	if is_instance_valid(nearest_enemy) and nearest_enemy.global_position.distance_to(center) <= PLATOON_COMMANDER_THREAT_DISTANCE:
		# Keep the soldiers between the enemy and their platoon commander.
		platoon_rear_direction = nearest_enemy.global_position.direction_to(center)
	elif not advance_direction.is_zero_approx():
		platoon_rear_direction = -advance_direction.normalized()
	elif platoon_rear_direction.is_zero_approx():
		platoon_rear_direction = center.direction_to(global_position)
		if platoon_rear_direction.is_zero_approx():
			platoon_rear_direction = Vector2.DOWN
	var rear_position := center + platoon_rear_direction.normalized() * PLATOON_COMMANDER_REAR_DISTANCE
	if is_instance_valid(inside_building):
		_exit_current_building()
	if global_position.distance_to(rear_position) <= 8.0:
		velocity = Vector2.ZERO
		task = Task.IDLE
		target_position = rear_position
		_set_facing_direction(global_position.direction_to(center))
		return
	if target_position.distance_to(rear_position) >= PLATOON_COMMANDER_REPATH_DISTANCE or task != Task.MOVE:
		target_position = _get_reachable_destination(rear_position)
		_calculate_path(target_position)
		task = Task.MOVE
		military_order = &"platoon_command"


func _find_nearest_enemy_to_platoon(center: Vector2) -> Unit:
	var nearest: Unit
	var nearest_distance := INF
	var candidates: Array = world_index.get_units() if is_instance_valid(world_index) else get_tree().get_nodes_in_group("units")
	for candidate in candidates:
		if candidate is not Unit or candidate.faction_id == faction_id or not candidate.is_mobilized or candidate.health <= 0:
			continue
		var distance := center.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate
	return nearest


func _broadcast_squad_follow_targets():
	if not is_squad_commander():
		return
	var commander_available := not is_instance_valid(inside_building) and military_order != &"return_to_base"
	for member in _get_squad_members():
		if member == self:
			continue
		# Личный приказ бойца важнее периодического построения отряда. Без этой
		# проверки командир каждые несколько кадров возвращал бы его на своё место.
		if member.squad_independent_order:
			continue
		if not commander_available:
			member._stop_following_squad_commander()
			continue
		if member.squad_formation_offset.is_zero_approx():
			member.squad_formation_offset = member._make_default_squad_offset()
		if is_instance_valid(member.inside_building):
			member._exit_current_building()
			member.target_building = null
			member.task = Task.IDLE
		member.military_order = military_order
		member.squad_commander_unit = self
		member.squad_follow_target = global_position + member.squad_formation_offset
		member.squad_follow_active = true
		member.squad_command_timeout = SQUAD_COMMAND_TIMEOUT


func _process_squad_following(delta: float) -> bool:
	if squad_follow_active and not is_instance_valid(squad_commander_unit):
		_stop_following_squad_commander()
	if not _can_follow_squad_commander():
		return false
	squad_command_timeout -= delta
	if squad_command_timeout <= 0.0:
		_stop_following_squad_commander()
		return false
	squad_follow_target = squad_commander_unit.global_position + squad_formation_offset
	target_position = squad_follow_target
	_follow_squad_commander(delta)
	return true


func _lod_process_squad_following(delta: float) -> bool:
	if squad_follow_active and not is_instance_valid(squad_commander_unit):
		_stop_following_squad_commander()
	if not _can_follow_squad_commander():
		return false
	squad_command_timeout -= delta
	if squad_command_timeout <= 0.0:
		_stop_following_squad_commander()
		return false
	squad_follow_target = squad_commander_unit.global_position + squad_formation_offset
	target_position = squad_follow_target
	task = Task.MOVE
	# The formation target moves every tick. A wider repath threshold keeps the
	# route useful without rebuilding AStar for every few pixels of commander
	# movement.
	_lod_navigate_toward(squad_follow_target, delta, SQUAD_FOLLOW_STOP_DISTANCE, 48.0)
	if global_position.distance_to(squad_follow_target) <= SQUAD_FOLLOW_STOP_DISTANCE + 0.01:
		task = Task.IDLE
		if not squad_formation_offset.is_zero_approx():
			_set_facing_direction(squad_formation_offset)
	return true


func _can_follow_squad_commander() -> bool:
	return is_mobilized and not is_squad_commander() and not squad_independent_order and squad_id > 0 and squad_follow_active and is_instance_valid(squad_commander_unit) and not is_instance_valid(squad_commander_unit.inside_building) and military_order != &"return_to_base" and not is_instance_valid(inside_building)


func _follow_squad_commander(delta: float):
	var offset_to_target := squad_follow_target - global_position
	var distance := offset_to_target.length()
	var commander_velocity := squad_commander_unit.velocity
	var correction := offset_to_target * SQUAD_FOLLOW_CORRECTION_RATE
	var movement_speed := _get_current_movement_speed()
	var catchup_ratio := clampf(distance / 96.0, 0.0, 1.0)
	var speed_limit := maxf(movement_speed, commander_velocity.length()) * lerpf(1.0, SQUAD_FOLLOW_SPEED_MULTIPLIER, catchup_ratio)
	var desired_velocity := (commander_velocity + correction).limit_length(speed_limit)
	if distance <= SQUAD_FOLLOW_STOP_DISTANCE and commander_velocity.length() < 1.0:
		desired_velocity = Vector2.ZERO
	var response := 1.0 - exp(-SQUAD_FOLLOW_VELOCITY_RESPONSE * delta)
	velocity = velocity.lerp(desired_velocity, clampf(response, 0.0, 1.0))
	if velocity.length() < 0.5 and desired_velocity.is_zero_approx():
		velocity = Vector2.ZERO
		task = Task.IDLE
		# Остановившиеся бойцы автоматически контролируют разные направления.
		# Случайное смещение построения задаёт каждому устойчивый сектор обзора.
		if not squad_formation_offset.is_zero_approx():
			_set_facing_direction(squad_formation_offset)
		return
	task = Task.MOVE
	_set_facing_direction(velocity)
	move_and_slide()


func _stop_following_squad_commander():
	squad_follow_active = false
	squad_command_timeout = 0.0
	platoon_rear_direction = Vector2.ZERO
	squad_commander_unit = null
	velocity = Vector2.ZERO
	if task == Task.MOVE:
		task = Task.IDLE


func _make_default_squad_offset() -> Vector2:
	var offset_rng := RandomNumberGenerator.new()
	offset_rng.seed = int(network_id) * 1103515245 + int(squad_id) * 12345
	var offset := Vector2(
		offset_rng.randf_range(-SQUAD_DEFAULT_OFFSET_RADIUS, SQUAD_DEFAULT_OFFSET_RADIUS),
		offset_rng.randf_range(-SQUAD_DEFAULT_OFFSET_RADIUS, SQUAD_DEFAULT_OFFSET_RADIUS)
	).limit_length(SQUAD_DEFAULT_OFFSET_RADIUS)
	if offset.length() < SQUAD_SPREAD_MIN_DISTANCE:
		offset = offset.normalized() * SQUAD_SPREAD_MIN_DISTANCE if not offset.is_zero_approx() else Vector2(SQUAD_SPREAD_MIN_DISTANCE, 0.0)
	return offset


func issue_squad_order(order: StringName) -> bool:
	if not is_squad_commander():
		return false
	var members := _get_squad_members()
	if members.is_empty():
		return false
	members.sort_custom(func(a: Unit, b: Unit):
		if a == self:
			return true
		if b == self:
			return false
		return a.network_id < b.network_id
	)
	var anchor := global_position
	military_order = order
	match order:
		&"spread_out":
			_assign_random_spread_offsets(members, anchor)
			for member in members:
				member._command_military_hold(order, member.facing_direction)
		&"watch_directions":
			for index in range(members.size()):
				var direction := Vector2.from_angle(-PI * 0.5 + TAU * float(index) / float(members.size()))
				if members[index] != self and members[index].squad_formation_offset.is_zero_approx():
					members[index].squad_formation_offset = members[index]._make_default_squad_offset()
				members[index]._command_military_hold(order, direction)
		&"regroup":
			var columns := 3
			for index in range(members.size()):
				var offset := Vector2.ZERO
				if index > 0:
					var slot := index - 1
					var row: int = slot / columns
					var column := slot % columns
					offset = Vector2((column - 1) * 18.0, (row + 1) * 18.0)
				members[index].squad_formation_offset = offset
				members[index]._command_military_hold(order, members[index].facing_direction)
		&"return_to_base":
			for member in members:
				member.command_return_to_base()
		_:
			for member in members:
				member.squad_formation_offset = (member.global_position - anchor).limit_length(SQUAD_SPREAD_RADIUS)
				member._command_military_hold(&"hold", member.facing_direction)
	squad_command_timer = SQUAD_COMMAND_INTERVAL
	_broadcast_squad_follow_targets()
	return true


func _spread_squad_after_arrival():
	if not is_squad_commander():
		return
	var members := _get_squad_members()
	if members.size() <= 1:
		return
	members.sort_custom(func(a: Unit, b: Unit):
		if a == self:
			return true
		if b == self:
			return false
		return a.network_id < b.network_id
	)
	# Новое построение назначается один раз по прибытии командира. Бойцы затем
	# расходятся к своим точкам обычным следованием, в том числе в фоновом LOD.
	for member in members:
		member.squad_independent_order = false
	if military_order in [&"front_line", &"offensive_line"] and not squad_line_direction.is_zero_approx():
		_assign_line_spread_offsets(members, squad_line_direction, target_position)
	else:
		_assign_random_spread_offsets(members, target_position)
	squad_command_timer = SQUAD_COMMAND_INTERVAL
	_broadcast_squad_follow_targets()


func _assign_random_spread_offsets(members: Array[Unit], anchor: Vector2):
	var offset_rng := RandomNumberGenerator.new()
	# Одинаковый приказ даёт одинаковое построение на всех участниках сети.
	# При перемещении в другую точку схема меняется вместе с координатами цели.
	offset_rng.seed = (
		int(network_id) * 1103515245
		+ int(squad_id) * 12345
		+ roundi(anchor.x) * 73856093
		+ roundi(anchor.y) * 19349663
	)
	var occupied_offsets: Array[Vector2] = [Vector2.ZERO]
	for member in members:
		if member == self:
			member.squad_formation_offset = Vector2.ZERO
			continue
		var chosen_offset := member._make_default_squad_offset()
		for _attempt in range(32):
			var candidate := Vector2(
				offset_rng.randf_range(-SQUAD_SPREAD_RADIUS, SQUAD_SPREAD_RADIUS),
				offset_rng.randf_range(-SQUAD_SPREAD_RADIUS, SQUAD_SPREAD_RADIUS)
			)
			if candidate.length() < SQUAD_SPREAD_MIN_DISTANCE or candidate.length() > SQUAD_SPREAD_RADIUS:
				continue
			var overlaps := false
			for occupied in occupied_offsets:
				if candidate.distance_to(occupied) < SQUAD_SPREAD_MIN_DISTANCE:
					overlaps = true
					break
			if not overlaps:
				chosen_offset = candidate
				break
		member.squad_formation_offset = chosen_offset
		occupied_offsets.append(chosen_offset)


func _assign_line_spread_offsets(members: Array[Unit], line_direction: Vector2, anchor: Vector2):
	var along := line_direction.normalized()
	if along.is_zero_approx():
		_assign_random_spread_offsets(members, anchor)
		return
	var depth := along.orthogonal()
	var offset_rng := RandomNumberGenerator.new()
	offset_rng.seed = (
		int(network_id) * 1103515245
		+ int(squad_id) * 12345
		+ roundi(anchor.x) * 73856093
		+ roundi(anchor.y) * 19349663
	)
	var slot := 0
	for member in members:
		if member == self:
			member.squad_formation_offset = Vector2.ZERO
			continue
		var rank: int = slot / 2 + 1
		var side := -1.0 if slot % 2 == 0 else 1.0
		var along_distance := minf(float(rank) * SQUAD_SPREAD_MIN_DISTANCE, SQUAD_SPREAD_RADIUS)
		var depth_offset := offset_rng.randf_range(-SQUAD_LINE_DEPTH_JITTER, SQUAD_LINE_DEPTH_JITTER)
		member.squad_formation_offset = along * along_distance * side + depth * depth_offset
		slot += 1


func _get_squad_members() -> Array[Unit]:
	var members: Array[Unit] = []
	for unit in _get_indexed_units():
		if is_instance_valid(unit) and unit is Unit and unit.faction_id == faction_id and unit.is_mobilized and unit.squad_id == squad_id:
			members.append(unit)
	return members


func _get_platoon_squad_commanders() -> Array[Unit]:
	var commanders: Array[Unit] = []
	for unit in _get_indexed_units():
		if is_instance_valid(unit) and unit is Unit and unit.faction_id == faction_id and unit.is_mobilized and unit.platoon_id == platoon_id and unit.is_squad_commander():
			commanders.append(unit)
	commanders.sort_custom(func(a: Unit, b: Unit):
		return a.squad_id < b.squad_id if a.squad_id != b.squad_id else a.network_id < b.network_id
	)
	return commanders


func issue_platoon_line(line_type: StringName, line_start: Vector2, line_end: Vector2) -> bool:
	# Общая армейская линия может быть поделена на очень короткие участки,
	# поэтому минимальная длина здесь меньше, чем у нарисованной игроком линии.
	if not is_platoon_commander() or line_start.distance_to(line_end) < 0.01:
		return false
	if line_type == &"offensive_line" and not has_platoon_front_line:
		return false
	if line_type not in [&"front_line", &"offensive_line"]:
		return false
	if line_type == &"front_line":
		has_platoon_front_line = true
		platoon_front_start = line_start
		platoon_front_end = line_end
		# Старая цель наступления относится к предыдущему фронту.
		has_platoon_offensive_line = false
		platoon_offensive_start = Vector2.ZERO
		platoon_offensive_end = Vector2.ZERO
	else:
		has_platoon_offensive_line = true
		platoon_offensive_start = line_start
		platoon_offensive_end = line_end
	var commanders := _get_platoon_squad_commanders()
	if commanders.is_empty():
		return false
	var line_direction := (line_end - line_start).normalized()
	for index in range(commanders.size()):
		var ratio := 0.5 if commanders.size() == 1 else float(index) / float(commanders.size() - 1)
		var destination := line_start.lerp(line_end, ratio)
		commanders[index]._command_military_move(destination, line_type, line_direction)
	return true


func request_platoon_line(line_type: StringName, line_start: Vector2, line_end: Vector2):
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		network_manager.request_unit_command([self], &"platoon_line", {
			"line_type": line_type,
			"line_start": line_start,
			"line_end": line_end,
		})
	else:
		issue_platoon_line(line_type, line_start, line_end)


func _command_military_move(destination: Vector2, order: StringName, formation_direction: Vector2 = Vector2.ZERO):
	if not is_mobilized:
		return
	command_move(destination, false, formation_direction)
	military_order = order
	if is_squad_commander():
		for member in _get_squad_members():
			member.squad_independent_order = false
		squad_command_timer = SQUAD_COMMAND_INTERVAL
		_broadcast_squad_follow_targets()


func _command_military_hold(order: StringName, direction: Vector2):
	if not is_mobilized:
		return
	squad_independent_order = false
	squad_line_direction = Vector2.ZERO
	platoon_rear_direction = Vector2.ZERO
	_cancel_task()
	velocity = Vector2.ZERO
	target_position = global_position
	path_points = PackedVector2Array()
	path_index = 0
	path_destination = Vector2(INF, INF)
	military_order = order
	idle_check_timer = AUTO_WORK_DELAY_AFTER_MANUAL_ORDER
	task = Task.IDLE
	_set_facing_direction(direction)


func command_return_to_base():
	if not is_mobilized:
		return
	squad_independent_order = false
	squad_line_direction = Vector2.ZERO
	military_order = &"return_to_base"
	_stop_following_squad_commander()
	if is_instance_valid(inside_building) and inside_building.is_barracks():
		return
	var barracks := _find_available_barracks()
	if is_instance_valid(barracks):
		command_enter_building(barracks)
		military_order = &"return_to_base"
	else:
		_cancel_task()
		velocity = Vector2.ZERO
		idle_check_timer = 1.0
		task = Task.IDLE


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
	if is_mobilized and building.is_barracks():
		military_order = &"hold"
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
	if continuous_harvest:
		_resume_priority_harvest_order()
		return
	var nearest_resource: Node2D = _find_nearest_resource(mining_job_resource_type)
	if is_instance_valid(nearest_resource):
		_start_harvesting(nearest_resource)
	else:
		task = Task.IDLE


func _resume_priority_harvest_order() -> bool:
	if not continuous_harvest or is_mobilized:
		return false
	harvest_resource_type = mining_job_resource_type
	if get_carried_resource_amount() > 0:
		if not is_instance_valid(target_warehouse) or not target_warehouse.has_resource_space(harvest_resource_type):
			_release_warehouse()
			target_warehouse = _find_warehouse_with_space(harvest_resource_type)
		if is_instance_valid(target_warehouse):
			task = Task.DELIVER_TO_WAREHOUSE
		else:
			velocity = Vector2.ZERO
			task = Task.IDLE
		return true
	if get_carried_total() >= carry_capacity:
		velocity = Vector2.ZERO
		task = Task.IDLE
		return true
	var nearest_resource := _find_nearest_resource(mining_job_resource_type)
	if is_instance_valid(nearest_resource):
		_start_harvesting(nearest_resource)
	else:
		velocity = Vector2.ZERO
		task = Task.IDLE
	return true


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
	for tree in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(tree) or tree.is_depleted() or tree.get_resource_type() != resource_type:
			continue
		var distance := global_position.distance_squared_to(tree.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_tree = tree
	return nearest_tree


func _find_resource_near_position(resource_type: StringName, saved_position: Vector2) -> Node2D:
	if is_instance_valid(lod_manager) and lod_manager.has_method("find_resource_near_position"):
		var indexed_resource = lod_manager.find_resource_near_position(resource_type, saved_position)
		if is_instance_valid(indexed_resource):
			return indexed_resource
	var nearest_resource: Node2D
	var nearest_distance := 32.0 * 32.0
	for resource in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(resource) or resource.is_depleted() or resource.get_resource_type() != resource_type:
			continue
		var distance := saved_position.distance_squared_to(resource.global_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest_resource = resource
	return nearest_resource


func _find_free_warehouse(resource_type: StringName) -> Building:
	var nearest: Building
	var nearest_distance := INF
	for building in _get_indexed_buildings("warehouse"):
		if building is not Building or building.faction_id != faction_id or not building.can_accept_worker(resource_type):
			continue
		var distance := global_position.distance_squared_to(building.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = building
	return nearest


func _find_warehouse_with_space(resource_type: StringName) -> Building:
	var nearest: Building
	var nearest_distance := INF
	for building in _get_indexed_buildings("warehouse"):
		if building is not Building or building.faction_id != faction_id or not building.is_warehouse() or not building.is_completed() or not building.has_resource_space(resource_type):
			continue
		var distance := global_position.distance_squared_to(building.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = building
	return nearest


func _find_warehouse_with_resource(resource_type: StringName) -> Building:
	var nearest: Building
	var nearest_distance := INF
	for building in _get_indexed_buildings("warehouse"):
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
	if is_instance_valid(world_index):
		carried_by_others = world_index.get_carried_to_building(target_building, resource_type, self)
	else:
		for unit in _get_indexed_units():
			if not is_instance_valid(unit) or unit == self or unit.target_building != target_building:
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


func request_move(destination: Vector2):
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		network_manager.request_unit_command([self], &"move", {"destinations": [destination]})
	else:
		command_move(destination)


func request_harvest(resource: Node2D):
	if not is_instance_valid(resource):
		return
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		network_manager.request_unit_command([self], &"harvest", {
			"resource_id": int(resource.get("lod_record_id")),
			"resource_type": resource.get_resource_type(),
			"position": resource.global_position,
		})
	else:
		command_harvest(resource)


func request_build(building: Building):
	if not is_instance_valid(building):
		return
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		network_manager.request_unit_command([self], &"build", {"building_id": building.network_id})
	else:
		command_build(building)


func request_build_line(segments: Array[Building]):
	var building_ids: Array[int] = []
	for segment in segments:
		if is_instance_valid(segment) and segment.network_id > 0:
			building_ids.append(segment.network_id)
	if building_ids.is_empty():
		return
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		network_manager.request_unit_command([self], &"build_line", {"building_ids": building_ids})
	else:
		command_build_line(segments)


func request_enter_building(building: Building):
	if not is_instance_valid(building):
		return
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		network_manager.request_unit_command([self], &"enter_building", {"building_id": building.network_id})
	else:
		command_enter_building(building)


func request_squad_order(order: StringName):
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		network_manager.request_unit_command([self], &"squad_order", {"order": order})
	else:
		issue_squad_order(order)


func command_move(destination: Vector2, independent_order: bool = true, formation_direction: Vector2 = Vector2.ZERO):
	_cancel_task()
	if is_mobilized and squad_id > 0 and not is_squad_commander():
		squad_independent_order = independent_order
		if squad_independent_order:
			_stop_following_squad_commander()
	if is_mobilized:
		squad_line_direction = formation_direction.normalized()
	target_position = _get_reachable_destination(destination)
	_calculate_path(target_position)
	if is_mobilized:
		military_order = &"move"
	task = Task.MOVE


func _get_reachable_destination(destination: Vector2) -> Vector2:
	for building in _get_indexed_buildings():
		if building is Building and building.building_kind != "road" and building.contains_world_point(destination, 4.0):
			return building.get_approach_position(global_position)
	return destination


func command_harvest(tree: Node2D):
	if is_mobilized:
		return
	_cancel_task()
	harvest_resource_type = tree.get_resource_type()
	mining_job_resource_type = harvest_resource_type
	profession = "Каменотёс" if harvest_resource_type == &"stone" else "Лесоруб"
	# Сам приказ постоянный и не зависит от доступного лимита работников склада.
	# Если зарезервировать место не удалось, юнит всё равно добывает и разгружает
	# ресурс в ближайший подходящий склад как обычный доставщик.
	continuous_harvest = true
	var warehouse := _find_free_warehouse(harvest_resource_type)
	if is_instance_valid(warehouse) and warehouse.assign_worker(self):
		target_warehouse = warehouse
	else:
		target_warehouse = _find_warehouse_with_space(harvest_resource_type)
	if get_carried_total() >= carry_capacity:
		_resume_priority_harvest_order()
	else:
		_start_harvesting(tree)


func restore_harvest_order(resource_type: StringName, should_repeat: bool, saved_resource_position: Vector2, saved_warehouse: Building, saved_task: int, saved_work_timer: float) -> bool:
	if is_mobilized or resource_type not in [&"wood", &"stone"]:
		return false
	_cancel_task()
	harvest_resource_type = resource_type
	mining_job_resource_type = resource_type
	profession = "Каменотёс" if resource_type == &"stone" else "Лесоруб"
	if should_repeat:
		continuous_harvest = true
		var warehouse := saved_warehouse
		if not is_instance_valid(warehouse) or not warehouse.can_accept_worker(resource_type):
			warehouse = _find_free_warehouse(resource_type)
		if is_instance_valid(warehouse) and warehouse.assign_worker(self):
			target_warehouse = warehouse
		else:
			target_warehouse = _find_warehouse_with_space(resource_type)
	if continuous_harvest and saved_task != Task.HARVEST and get_carried_resource_amount() > 0:
		_resume_priority_harvest_order()
		return true
	var resource := _find_resource_near_position(resource_type, saved_resource_position)
	if not is_instance_valid(resource):
		resource = _find_nearest_resource(resource_type)
	if is_instance_valid(resource):
		_start_harvesting(resource)
		if saved_work_timer > 0.0:
			work_timer = clampf(saved_work_timer, 0.01, harvest_interval)
		return true
	if continuous_harvest:
		_resume_priority_harvest_order()
		return true
	_release_warehouse()
	task = Task.IDLE
	return false


func command_build(building: Building):
	if is_mobilized or not is_instance_valid(building) or building.faction_id != faction_id:
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
	if is_mobilized:
		return
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
		for building in _get_indexed_buildings(build_job_kind):
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
			request_build(collider)
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
			request_harvest(selected_resource)
		else:
			request_move(selected_resource.global_position)
		return

	request_move(mouse_position)


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
		Task.FACTORY_WORK:
			return "Работает в хижине дровосеков" if is_instance_valid(inside_building) and inside_building.is_lumberjack_cabin() else "Работает на заводе"
		Task.REST: return "В казарме" if is_mobilized else "Находится дома"
		_:
			if continuous_harvest:
				return "Ждёт место на складе" if get_carried_resource_amount() > 0 else "Ждёт ресурс для добычи"
			return "Свободен"


func get_profession_text() -> String:
	return "%s • %s" % [military_rank, get_military_role_name()] if is_mobilized else profession


func get_military_role_name() -> String:
	var template: Dictionary = MILITARY_ROLE_TEMPLATES.get(military_role, MILITARY_ROLE_TEMPLATES[&"rifleman"])
	return str(template["name"])


func get_military_assignment_text() -> String:
	if not is_mobilized:
		return "Не мобилизован"
	var squad_text := "штаб взвода" if is_dedicated_platoon_commander() else ("без отряда" if squad_id <= 0 else "отряд %d" % squad_id)
	var platoon_text := "без взвода" if platoon_id <= 0 else "взвод %d" % platoon_id
	return "%s, %s • %s • %s" % [squad_text, platoon_text, military_rank, get_military_order_name()]


func get_military_order_name() -> String:
	match military_order:
		&"move": return "движение"
		&"platoon_command": return "командует взводом из тыла"
		&"attack": return "наступление"
		&"front_line": return "занимает линию фронта"
		&"offensive_line": return "движется к линии наступления"
		&"spread_out": return "рассредоточение"
		&"watch_directions": return "круговой обзор"
		&"regroup": return "сбор у командира"
		&"return_to_base": return "возврат на базу"
		_: return "удерживать позицию"


func get_military_equipment_text() -> String:
	if not has_armor and not has_rifle:
		return "Нет"
	var items := PackedStringArray()
	if has_armor:
		items.append("броня")
	if has_rifle:
		items.append("автомат")
	return ", ".join(items)


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
