class_name SimulationLODManager
extends Node

const RESOURCE_CHUNK_SIZE := 512.0
const UNIT_CHUNK_SIZE := 64.0
const ROCK_MIN_SPACING := 32.0
const ROCK_POSITION_SEARCH_STEP := 8.0
const ROCK_POSITION_SEARCH_RINGS := 16
const TREE_SCENE := preload("res://scenes/objects/tree.tscn")
const ROCK_SCENE := preload("res://scenes/objects/rock.tscn")

@export var refresh_interval := 0.2
@export var demotion_delay := 2.0
@export var render_margin := 160.0
@export var reduced_margin := 720.0
@export var strategic_margin := 2400.0
@export var reduced_tick_interval := 0.12
@export var strategic_tick_interval := 0.75
@export var background_tick_interval := 4.0

var camera: Camera2D
var _clock := 0.0
var _refresh_accumulator := 0.0
var _lod_tick_accumulators: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _lod_buckets: Array = [[], [], [], []]
var _resource_chunks := {}
var _resource_records_by_id := {}
var _active_resource_chunks := {}
var _unit_chunks := {}
var _next_resource_id := 1


func _ready():
	add_to_group("simulation_lod_manager")
	set_physics_process(false)
	call_deferred("_initialize")


func _initialize():
	camera = get_node_or_null("../Camera2D") as Camera2D
	if camera == null:
		return
	rebuild_spatial_index()
	_refresh_lods(true, 0.0)
	set_physics_process(true)


func _physics_process(delta: float):
	if not is_instance_valid(camera):
		return
	_clock += delta
	_refresh_accumulator += delta
	if _refresh_accumulator >= refresh_interval:
		var refresh_delta := _refresh_accumulator
		_refresh_accumulator = fmod(_refresh_accumulator, refresh_interval)
		_refresh_lods(false, refresh_delta)

	_tick_lod_bucket(Unit.SimulationLOD.REDUCED, reduced_tick_interval, delta)
	_tick_lod_bucket(Unit.SimulationLOD.STRATEGIC, strategic_tick_interval, delta)
	_tick_lod_bucket(Unit.SimulationLOD.BACKGROUND, background_tick_interval, delta)


func _tick_lod_bucket(level: int, interval: float, delta: float):
	_lod_tick_accumulators[level] += delta
	if _lod_tick_accumulators[level] < interval:
		return
	_lod_tick_accumulators[level] = fmod(_lod_tick_accumulators[level], interval)
	for unit in _lod_buckets[level]:
		if not is_instance_valid(unit) or unit.simulation_lod != level:
			continue
		_simulate_pending_time(unit)


func _simulate_pending_time(unit: Unit):
	var elapsed := maxf(_clock - unit.lod_last_simulation_time, 0.0)
	if elapsed > 0.0:
		unit.simulate_lod(elapsed)
	unit.lod_last_simulation_time = _clock


func _refresh_lods(initial: bool, elapsed: float):
	var visible_rect := _get_camera_rect()
	var render_rect := visible_rect.grow(render_margin)
	var reduced_rect := visible_rect.grow(reduced_margin)
	var strategic_rect := visible_rect.grow(strategic_margin)
	var local_faction_id := _get_local_faction_id()
	var new_buckets: Array = [[], [], [], []]
	_unit_chunks.clear()

	for candidate in get_tree().get_nodes_in_group("units"):
		if candidate is not Unit or not get_parent().is_ancestor_of(candidate):
			continue
		var unit := candidate as Unit
		var desired_lod := _get_desired_lod(unit, render_rect, reduced_rect, strategic_rect, local_faction_id)
		_update_unit_lod(unit, desired_lod, render_rect.has_point(unit.global_position), initial, elapsed)
		new_buckets[unit.simulation_lod].append(unit)
		var unit_chunk := _point_to_chunk(unit.global_position, UNIT_CHUNK_SIZE)
		if not _unit_chunks.has(unit_chunk):
			_unit_chunks[unit_chunk] = []
		_unit_chunks[unit_chunk].append(unit)
	_lod_buckets = new_buckets

	_update_resource_chunks(render_rect)
	_update_buildings(render_rect)


func _get_desired_lod(unit: Unit, render_rect: Rect2, reduced_rect: Rect2, strategic_rect: Rect2, local_faction_id: int) -> int:
	if unit.selected or render_rect.has_point(unit.global_position):
		return Unit.SimulationLOD.FULL
	var desired_lod := Unit.SimulationLOD.BACKGROUND
	if reduced_rect.has_point(unit.global_position):
		desired_lod = Unit.SimulationLOD.REDUCED
	elif strategic_rect.has_point(unit.global_position):
		desired_lod = Unit.SimulationLOD.STRATEGIC

	# Приказ, цель которого находится в кадре, важнее текущей позиции юнита.
	if unit.has_lod_focus_in(render_rect):
		desired_lod = mini(desired_lod, Unit.SimulationLOD.REDUCED)
	# Свои жители и явно помеченные командиры/ключевые юниты получают более
	# частую симуляцию. Неизвестные далёкие фракции остаются в фоне.
	var importance := unit.simulation_importance
	if unit.faction_id == local_faction_id:
		importance += 1
	if importance > 0:
		desired_lod = maxi(desired_lod - importance, Unit.SimulationLOD.REDUCED)
	return desired_lod


func _update_unit_lod(unit: Unit, desired_lod: int, render_enabled: bool, initial: bool, elapsed: float):
	unit.set_lod_render_enabled(render_enabled)
	var current_lod: int = unit.simulation_lod
	var should_switch := initial or desired_lod < current_lod
	if desired_lod == current_lod:
		unit.lod_pending_level = current_lod
		unit.lod_pending_time = 0.0
	elif desired_lod > current_lod and not initial:
		if unit.lod_pending_level != desired_lod:
			unit.lod_pending_level = desired_lod
			unit.lod_pending_time = 0.0
		else:
			unit.lod_pending_time += elapsed
		should_switch = unit.lod_pending_time >= demotion_delay

	if not should_switch or desired_lod == current_lod:
		return
	if current_lod != Unit.SimulationLOD.FULL:
		_simulate_pending_time(unit)
	unit.set_simulation_lod(desired_lod, render_enabled)
	unit.lod_pending_level = desired_lod
	unit.lod_pending_time = 0.0
	unit.lod_last_simulation_time = _clock


func _get_camera_rect() -> Rect2:
	var viewport_size := camera.get_viewport_rect().size
	var safe_zoom := Vector2(maxf(absf(camera.zoom.x), 0.001), maxf(absf(camera.zoom.y), 0.001))
	var world_size := viewport_size / safe_zoom
	return Rect2(camera.global_position - world_size * 0.5, world_size)


func _get_local_faction_id() -> int:
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager) and network_manager.has_method("get_local_faction_id"):
		return int(network_manager.get_local_faction_id())
	return 0


func rebuild_spatial_index():
	_active_resource_chunks.clear()
	for candidate in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(candidate) or candidate is not Node2D or not get_parent().is_ancestor_of(candidate):
			continue
		if int(candidate.get("lod_record_id")) <= 0:
			var resource_kind := "tree" if candidate.is_in_group("trees") else "rock"
			var variant := int(candidate.get("tree_variant")) if resource_kind == "tree" else int(candidate.get("rock_variant"))
			var amount := int(candidate.get("wood_amount")) if resource_kind == "tree" else int(candidate.get("stone_amount"))
			register_resource_data(resource_kind, candidate.global_position, variant, amount, candidate)
		if candidate.has_method("set_lod_active"):
			candidate.set_lod_active(false)
	if is_instance_valid(camera):
		_update_resource_chunks(_get_camera_rect().grow(render_margin))


func register_resource_data(resource_kind: String, position: Vector2, variant: int, amount: int, existing_node: Node2D = null) -> int:
	if resource_kind == "rock":
		position = _find_available_rock_position(position)
		if is_instance_valid(existing_node):
			existing_node.global_position = position
	var record_id := _next_resource_id
	_next_resource_id += 1
	var record := {
		"id": record_id,
		"kind": resource_kind,
		"resource_type": &"wood" if resource_kind == "tree" else &"stone",
		"position": position,
		"variant": variant,
		"amount": amount,
		"node": existing_node,
	}
	var chunk := _point_to_chunk(position, RESOURCE_CHUNK_SIZE)
	if not _resource_chunks.has(chunk):
		_resource_chunks[chunk] = []
	_resource_chunks[chunk].append(record)
	_resource_records_by_id[record_id] = record
	if is_instance_valid(existing_node):
		existing_node.set("lod_record_id", record_id)
	return record_id


func _find_available_rock_position(requested_position: Vector2) -> Vector2:
	if _is_rock_position_available(requested_position):
		return requested_position
	# Поиск детерминированный: одинаковый seed и одинаковое сохранение всегда
	# дают те же позиции. Кольца позволяют сохранить форму залежи и сдвинуть
	# только тот камень, который действительно пересекается с соседним.
	var phase := TAU * float(_next_resource_id % 32) / 32.0
	for ring_index in range(1, ROCK_POSITION_SEARCH_RINGS + 1):
		var radius := ROCK_POSITION_SEARCH_STEP * ring_index
		var sample_count := maxi(8, ceili(TAU * radius / ROCK_POSITION_SEARCH_STEP))
		for sample_index in range(sample_count):
			var angle := phase + TAU * float(sample_index) / float(sample_count)
			var candidate := requested_position + Vector2.from_angle(angle) * radius
			if _is_rock_position_available(candidate):
				return candidate
	# При штатной плотности залежей этот резерв недостижим. Если область всё же
	# полностью занята, продолжаем поиск дальше, не допуская наложения.
	var fallback_radius := ROCK_MIN_SPACING
	for record in _resource_records_by_id.values():
		if record.get("kind", "") == "rock" and int(record.get("amount", 0)) > 0:
			fallback_radius = maxf(fallback_radius, requested_position.distance_to(record.get("position", Vector2.ZERO)) + ROCK_MIN_SPACING)
	return requested_position + Vector2.from_angle(phase) * fallback_radius


func _is_rock_position_available(position: Vector2) -> bool:
	var search_radius := ROCK_MIN_SPACING
	var search_area := Rect2(position - Vector2.ONE * search_radius, Vector2.ONE * search_radius * 2.0)
	var minimum_distance_squared := ROCK_MIN_SPACING * ROCK_MIN_SPACING
	for chunk in _get_chunks_in_rect(search_area, RESOURCE_CHUNK_SIZE):
		for record in _resource_chunks.get(chunk, []):
			if record.get("kind", "") != "rock" or int(record.get("amount", 0)) <= 0:
				continue
			if position.distance_squared_to(record.get("position", Vector2.ZERO)) < minimum_distance_squared:
				return false
	return true


func clear_resource_data():
	for record in _resource_records_by_id.values():
		var resource = record.get("node")
		if is_instance_valid(resource):
			resource.queue_free()
	_resource_chunks.clear()
	_resource_records_by_id.clear()
	_active_resource_chunks.clear()
	_next_resource_id = 1


func update_resource_amount(record_id: int, amount: int):
	var record: Dictionary = _resource_records_by_id.get(record_id, {})
	if not record.is_empty():
		record["amount"] = maxi(amount, 0)


func get_resource_save_data() -> Array:
	var result: Array = []
	for record in _resource_records_by_id.values():
		_sync_resource_record(record)
		if int(record.get("amount", 0)) <= 0:
			continue
		result.append({
			"type": record.get("kind", "tree"),
			"position": [record.position.x, record.position.y],
			"variant": int(record.get("variant", 0)),
			"amount": int(record.get("amount", 0)),
		})
	return result


func remove_resources_in_radius(center: Vector2, radius: float):
	var area := Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
	for chunk in _get_chunks_in_rect(area, RESOURCE_CHUNK_SIZE):
		for record in _resource_chunks.get(chunk, []):
			if int(record.get("amount", 0)) <= 0 or center.distance_to(record.position) > radius:
				continue
			record["amount"] = 0
			var resource = record.get("node")
			if is_instance_valid(resource):
				resource.queue_free()
			record["node"] = null


func _update_resource_chunks(active_rect: Rect2):
	var desired_chunks := _get_chunks_in_rect(active_rect, RESOURCE_CHUNK_SIZE)
	for chunk in _active_resource_chunks.keys():
		if not desired_chunks.has(chunk):
			_set_resource_chunk_active(chunk, false)
	for chunk in desired_chunks:
		if not _active_resource_chunks.has(chunk):
			_set_resource_chunk_active(chunk, true)
	_active_resource_chunks = desired_chunks


func _set_resource_chunk_active(chunk: Vector2i, active: bool):
	for record in _resource_chunks.get(chunk, []):
		if int(record.get("amount", 0)) <= 0:
			continue
		var resource = record.get("node")
		if active and not is_instance_valid(resource):
			resource = _materialize_resource(record)
		if not is_instance_valid(resource):
			continue
		if resource.has_method("set_lod_active"):
			resource.set_lod_active(active)
		if not active and resource.get_harvester_count() <= 0:
			_sync_resource_record(record)
			resource.queue_free()
			record["node"] = null


func _materialize_resource(record: Dictionary) -> Node2D:
	var resource: Node2D
	if record.get("kind", "tree") == "tree":
		resource = TREE_SCENE.instantiate()
		resource.tree_variant = int(record.get("variant", 0))
		resource.wood_amount = int(record.get("amount", 20))
		get_parent().get_node("trees").add_child(resource)
	else:
		resource = ROCK_SCENE.instantiate()
		resource.rock_variant = int(record.get("variant", 0))
		resource.stone_amount = int(record.get("amount", 30))
		get_parent().get_node("rocks").add_child(resource)
	resource.global_position = record.get("position", Vector2.ZERO)
	resource.lod_record_id = int(record.get("id", 0))
	record["node"] = resource
	return resource


func _sync_resource_record(record: Dictionary):
	var resource = record.get("node")
	if not is_instance_valid(resource):
		return
	record["amount"] = resource.wood_amount if record.get("kind", "tree") == "tree" else resource.stone_amount


func _update_buildings(active_rect: Rect2):
	for candidate in get_tree().get_nodes_in_group("buildings"):
		if candidate is Building and get_parent().is_ancestor_of(candidate):
			candidate.set_lod_active(active_rect.has_point(candidate.global_position))


func get_nearby_units(point: Vector2) -> Array:
	var result: Array = []
	var center := _point_to_chunk(point, UNIT_CHUNK_SIZE)
	for x in range(center.x - 1, center.x + 2):
		for y in range(center.y - 1, center.y + 2):
			result.append_array(_unit_chunks.get(Vector2i(x, y), []))
	return result


func find_nearest_resource(resource_type: StringName, point: Vector2) -> Node2D:
	var center := _point_to_chunk(point, RESOURCE_CHUNK_SIZE)
	var furthest_radius := 0
	for chunk in _resource_chunks:
		furthest_radius = maxi(furthest_radius, maxi(absi(chunk.x - center.x), absi(chunk.y - center.y)))
	var nearest_busy: Dictionary = {}
	var nearest_busy_workers := 2147483647
	var nearest_busy_distance := INF
	for radius in range(furthest_radius + 1):
		var nearest_free: Dictionary = {}
		var nearest_free_distance := INF
		for x in range(center.x - radius, center.x + radius + 1):
			for y in range(center.y - radius, center.y + radius + 1):
				if radius > 0 and absi(x - center.x) != radius and absi(y - center.y) != radius:
					continue
				for record in _resource_chunks.get(Vector2i(x, y), []):
					if int(record.get("amount", 0)) <= 0 or record.get("resource_type") != resource_type:
						continue
					var distance: float = point.distance_squared_to(record.position)
					var resource = record.get("node")
					var workers: int = resource.get_harvester_count() if is_instance_valid(resource) else 0
					if workers == 0 and distance < nearest_free_distance:
						nearest_free = record
						nearest_free_distance = distance
					elif workers < nearest_busy_workers or (workers == nearest_busy_workers and distance < nearest_busy_distance):
						nearest_busy = record
						nearest_busy_workers = workers
						nearest_busy_distance = distance
		if not nearest_free.is_empty():
			return _get_or_materialize_resource(nearest_free)
	return _get_or_materialize_resource(nearest_busy)


func _get_or_materialize_resource(record: Dictionary) -> Node2D:
	if record.is_empty():
		return null
	var resource = record.get("node")
	if not is_instance_valid(resource):
		resource = _materialize_resource(record)
		var chunk := _point_to_chunk(record.position, RESOURCE_CHUNK_SIZE)
		if resource.has_method("set_lod_active"):
			resource.set_lod_active(_active_resource_chunks.has(chunk))
	return resource


func _get_chunks_in_rect(rect: Rect2, chunk_size: float) -> Dictionary:
	var result := {}
	var first := _point_to_chunk(rect.position, chunk_size)
	var last := _point_to_chunk(rect.end, chunk_size)
	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			result[Vector2i(x, y)] = true
	return result


func _point_to_chunk(point: Vector2, chunk_size: float) -> Vector2i:
	return Vector2i(floori(point.x / chunk_size), floori(point.y / chunk_size))
