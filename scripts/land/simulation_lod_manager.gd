class_name SimulationLODManager
extends Node

const RESOURCE_CHUNK_SIZE := 512.0
const UNIT_CHUNK_SIZE := 64.0
const ROCK_MIN_SPACING := 32.0
const ROCK_POSITION_SEARCH_STEP := 8.0
const ROCK_POSITION_SEARCH_RINGS := 16
const LOD_CATCH_UP_SLICE := 0.5
const MAX_LOD_CATCH_UP_STEPS := 8
const TREE_SCENE := preload("res://scenes/objects/tree.tscn")
const ROCK_SCENE := preload("res://scenes/objects/rock.tscn")

@export var refresh_interval := 0.2
@export var demotion_delay := 2.0
@export var render_margin := 160.0
@export var reduced_margin := 720.0
@export var strategic_margin := 2400.0
@export_range(0.1, 2.0, 0.05) var full_simulation_min_zoom := 0.65
@export var reduced_tick_interval := 0.12
@export var strategic_tick_interval := 0.4
@export var background_tick_interval := 2.0
@export_range(1, 64, 1) var object_load_budget_per_frame := 24
@export_range(8, 512, 8) var lod_unit_budget_per_level_per_frame := 192
@export_range(0.1, 4.0, 0.1) var lod_time_budget_per_level_msec := 1.0

var camera: Camera2D
var _clock := 0.0
var _refresh_accumulator := 0.0
var _lod_tick_credits: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _lod_tick_cursors: Array[int] = [0, 0, 0, 0]
var _lod_buckets: Array = [[], [], [], []]
var _resource_chunks := {}
var _resource_records_by_id := {}
var _active_resource_chunks := {}
var _unit_chunks := {}
var _next_resource_id := 1
var _current_render_rect := Rect2()
var _pending_object_loads: Array[Dictionary] = []
var _pending_object_load_index := 0
var _progressively_visible_units := {}
var _progressively_active_buildings := {}
var _world_index: Node


func _ready():
	add_to_group("simulation_lod_manager")
	set_physics_process(false)
	call_deferred("_initialize")


func _initialize():
	camera = get_node_or_null("../Camera2D") as Camera2D
	_world_index = get_node_or_null("../WorldIndex")
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
	_process_pending_object_loads()

	_tick_lod_bucket(Unit.SimulationLOD.REDUCED, reduced_tick_interval, delta)
	_tick_lod_bucket(Unit.SimulationLOD.STRATEGIC, strategic_tick_interval, delta)
	_tick_lod_bucket(Unit.SimulationLOD.BACKGROUND, background_tick_interval, delta)


func _tick_lod_bucket(level: int, interval: float, delta: float):
	var bucket: Array = _lod_buckets[level]
	if bucket.is_empty():
		_lod_tick_credits[level] = 0.0
		_lod_tick_cursors[level] = 0
		return
	# Кредитная схема сохраняет среднюю частоту каждого LOD, но не обновляет
	# весь бакет одним тяжёлым кадром.
	_lod_tick_credits[level] = minf(
		_lod_tick_credits[level] + float(bucket.size()) * delta / maxf(interval, 0.001),
		float(bucket.size())
	)
	var requested := int(floor(_lod_tick_credits[level]))
	var update_count := mini(requested, mini(lod_unit_budget_per_level_per_frame, bucket.size()))
	var processed := 0
	var started_usec := Time.get_ticks_usec()
	for update_index in range(update_count):
		# Path requests and job selection are much more expensive than an indoor
		# production tick. A small wall-clock budget prevents a group of newly idle
		# citizens from turning one frame into a visible hitch.
		if update_index > 0 and update_index % 8 == 0:
			var elapsed_msec := float(Time.get_ticks_usec() - started_usec) / 1000.0
			if elapsed_msec >= lod_time_budget_per_level_msec:
				break
		var cursor := _lod_tick_cursors[level] % bucket.size()
		_lod_tick_cursors[level] = (cursor + 1) % bucket.size()
		var unit = bucket[cursor]
		processed += 1
		if not is_instance_valid(unit) or unit.simulation_lod != level:
			continue
		_simulate_pending_time(unit)
	_lod_tick_credits[level] = maxf(_lod_tick_credits[level] - processed, 0.0)


func _simulate_pending_time(unit: Unit):
	var elapsed := maxf(_clock - unit.lod_last_simulation_time, 0.0)
	var remaining := elapsed
	var simulated := 0.0
	var catch_up_steps := 0
	# Один большой вызов обрабатывает только текущее состояние юнита. Дробные
	# шаги позволяют за один редкий фоновый тик последовательно завершить путь,
	# добычу, доставку и строительство, не теряя прошедшее игровое время.
	while remaining > 0.0 and catch_up_steps < MAX_LOD_CATCH_UP_STEPS and is_instance_valid(unit):
		var step := minf(remaining, LOD_CATCH_UP_SLICE)
		unit.simulate_lod(step)
		remaining -= step
		simulated += step
		catch_up_steps += 1
	if is_instance_valid(unit):
		# Never collapse a long backlog into one giant state update. Doing so lets
		# hunger consume many meals before work, construction and production can
		# advance through their intermediate states. Keep the unsimulated time as
		# debt; subsequent LOD ticks will catch it up in the same small slices.
		unit.lod_last_simulation_time = minf(unit.lod_last_simulation_time + simulated, _clock)


func _refresh_lods(initial: bool, elapsed: float):
	var visible_rect := _get_camera_rect()
	var render_rect := visible_rect.grow(render_margin)
	var reduced_rect := visible_rect.grow(reduced_margin)
	var strategic_rect := visible_rect.grow(strategic_margin)
	var local_faction_id := _get_local_faction_id()
	var new_buckets: Array = [[], [], [], []]
	var load_candidates: Array[Dictionary] = []
	_current_render_rect = render_rect
	_unit_chunks.clear()

	var units: Array = _world_index.get_all_units_view() if is_instance_valid(_world_index) and _world_index.has_method("get_all_units_view") else get_tree().get_nodes_in_group("units")
	for candidate in units:
		if candidate is not Unit or not get_parent().is_ancestor_of(candidate):
			continue
		var unit := candidate as Unit
		var unit_id := unit.get_instance_id()
		var wants_render := not is_instance_valid(unit.inside_building) and render_rect.has_point(unit.global_position)
		if not wants_render:
			_progressively_visible_units.erase(unit_id)
		elif not _progressively_visible_units.has(unit_id):
			load_candidates.append(_make_load_candidate(&"unit", unit.global_position, unit))
		var render_enabled := wants_render and _progressively_visible_units.has(unit_id)
		var desired_lod := _get_desired_lod(unit, render_rect, reduced_rect, strategic_rect, local_faction_id)
		_update_unit_lod(unit, desired_lod, render_enabled, initial, elapsed)
		new_buckets[unit.simulation_lod].append(unit)
		var unit_chunk := _point_to_chunk(unit.global_position, UNIT_CHUNK_SIZE)
		if not _unit_chunks.has(unit_chunk):
			_unit_chunks[unit_chunk] = []
		_unit_chunks[unit_chunk].append(unit)
	_lod_buckets = new_buckets

	_update_resource_chunks(render_rect, load_candidates)
	_update_buildings(render_rect, load_candidates)
	_replace_pending_object_loads(load_candidates)


func _replace_pending_object_loads(load_candidates: Array[Dictionary]):
	load_candidates.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("distance", INF)) < float(b.get("distance", INF)))
	_pending_object_loads = load_candidates
	_pending_object_load_index = 0


func _make_load_candidate(kind: StringName, position: Vector2, payload: Variant) -> Dictionary:
	return {
		"kind": kind,
		"position": position,
		"distance": camera.global_position.distance_squared_to(position),
		"payload": payload,
	}


func _process_pending_object_loads():
	# Камера может быстро уйти из области между двумя обновлениями LOD. Проверяем
	# актуальный кадр здесь, чтобы очередь не тратила бюджет на уже невидимую зону.
	_current_render_rect = _get_camera_rect().grow(render_margin)
	var loaded := 0
	while _pending_object_load_index < _pending_object_loads.size() and loaded < object_load_budget_per_frame:
		var item := _pending_object_loads[_pending_object_load_index]
		_pending_object_load_index += 1
		var position: Vector2 = item.get("position", Vector2.ZERO)
		if not _current_render_rect.has_point(position):
			continue
		match StringName(item.get("kind", &"")):
			&"unit":
				var unit = item.get("payload") as Unit
				if not is_instance_valid(unit):
					continue
				_progressively_visible_units[unit.get_instance_id()] = true
				unit.set_lod_render_enabled(true)
				loaded += 1
			&"building":
				var building = item.get("payload") as Building
				if not is_instance_valid(building):
					continue
				_progressively_active_buildings[building.get_instance_id()] = true
				building.set_lod_active(true)
				loaded += 1
			&"resource":
				var record: Dictionary = item.get("payload", {})
				if record.is_empty() or int(record.get("amount", 0)) <= 0:
					continue
				var chunk := _point_to_chunk(record.get("position", Vector2.ZERO), RESOURCE_CHUNK_SIZE)
				if not _active_resource_chunks.has(chunk):
					continue
				var resource = record.get("node")
				if not is_instance_valid(resource):
					resource = _materialize_resource(record)
				if resource.has_method("set_lod_active"):
					resource.set_lod_active(true)
				loaded += 1
	if _pending_object_load_index >= _pending_object_loads.size():
		_pending_object_loads.clear()
		_pending_object_load_index = 0


func _get_desired_lod(unit: Unit, render_rect: Rect2, reduced_rect: Rect2, strategic_rect: Rect2, local_faction_id: int) -> int:
	# Indoor work has no movement or collision. Production, hunger, rest and job
	# selection remain exact when advanced with a coarser delta.
	if is_instance_valid(unit.inside_building):
		return Unit.SimulationLOD.STRATEGIC

	# Only visible citizens need CharacterBody2D collision and per-physics-frame
	# presentation. Every lower level keeps the same persistent Unit state and is
	# advanced by the central scheduler in bounded time slices. At strategic zoom
	# rendered units keep a reduced tick because their collision is not perceptible.
	var detailed_view := not is_instance_valid(camera) or minf(absf(camera.zoom.x), absf(camera.zoom.y)) >= full_simulation_min_zoom
	if detailed_view and render_rect.has_point(unit.global_position):
		return Unit.SimulationLOD.FULL

	var desired_lod := Unit.SimulationLOD.BACKGROUND
	if render_rect.has_point(unit.global_position) or reduced_rect.has_point(unit.global_position):
		desired_lod = Unit.SimulationLOD.REDUCED
	elif strategic_rect.has_point(unit.global_position):
		desired_lod = Unit.SimulationLOD.STRATEGIC

	# Activity matters more than distance. Travelling, hauling, building and
	# formation following retain a responsive tick even at the edge of the map.
	if unit.selected or unit.has_lod_focus_in(render_rect) or unit.needs_frequent_offscreen_simulation():
		desired_lod = mini(desired_lod, Unit.SimulationLOD.REDUCED)
	elif unit.needs_reliable_offscreen_simulation():
		desired_lod = mini(desired_lod, Unit.SimulationLOD.STRATEGIC)

	# Local citizens and commanders are scheduled ahead of inactive remote units,
	# without ever enabling off-screen physics solely because they are important.
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
	_pending_object_loads.clear()
	_pending_object_load_index = 0
	_progressively_visible_units.clear()
	_progressively_active_buildings.clear()
	_active_resource_chunks.clear()
	for candidate in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(candidate) or candidate is not Node2D or not get_parent().is_ancestor_of(candidate):
			continue
		# Forestry trees are simulated and saved by their cabin, not as wild resources.
		if candidate.has_meta("managed_forestry_tree"):
			continue
		if int(candidate.get("lod_record_id")) <= 0:
			var resource_kind := "tree" if candidate.is_in_group("trees") else "rock"
			var variant := int(candidate.get("tree_variant")) if resource_kind == "tree" else int(candidate.get("rock_variant"))
			var amount := int(candidate.get("wood_amount")) if resource_kind == "tree" else int(candidate.get("stone_amount"))
			register_resource_data(resource_kind, candidate.global_position, variant, amount, candidate)
		if candidate.has_method("set_lod_active"):
			candidate.set_lod_active(false)
	if is_instance_valid(camera):
		_current_render_rect = _get_camera_rect().grow(render_margin)
		var load_candidates: Array[Dictionary] = []
		_update_resource_chunks(_current_render_rect, load_candidates)
		_replace_pending_object_loads(load_candidates)


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
		existing_node.set("lod_manager", self)
	return record_id


func has_resource_near(position: Vector2, minimum_distance: float) -> bool:
	var search_area := Rect2(position - Vector2.ONE * minimum_distance, Vector2.ONE * minimum_distance * 2.0)
	var minimum_distance_squared := minimum_distance * minimum_distance
	for chunk in _get_chunks_in_rect(search_area, RESOURCE_CHUNK_SIZE):
		for record in _resource_chunks.get(chunk, []):
			if int(record.get("amount", 0)) > 0 and position.distance_squared_to(record.get("position", Vector2.ZERO)) < minimum_distance_squared:
				return true
	return false


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
	_pending_object_loads.clear()
	_pending_object_load_index = 0
	for record in _resource_records_by_id.values():
		var resource = record.get("node")
		if is_instance_valid(resource):
			resource.queue_free()
	_resource_chunks.clear()
	_resource_records_by_id.clear()
	_active_resource_chunks.clear()
	_next_resource_id = 1


func update_resource_amount(record_id: int, amount: int, source_faction_id := -1):
	var record: Dictionary = _resource_records_by_id.get(record_id, {})
	if not record.is_empty():
		record["amount"] = maxi(amount, 0)
		var resource = record.get("node")
		if is_instance_valid(resource):
			if record.get("kind", "tree") == "tree":
				resource.wood_amount = int(record["amount"])
			else:
				resource.stone_amount = int(record["amount"])
			if int(record["amount"]) <= 0:
				resource.queue_free()
				record["node"] = null
		var network_manager := get_node_or_null("/root/NetworkManager")
		if is_instance_valid(network_manager):
			network_manager.replicate_resource_amount(record_id, int(record["amount"]), source_faction_id)


func get_network_resource_states() -> Array:
	var result: Array = []
	for record in _resource_records_by_id.values():
		_sync_resource_record(record)
		result.append({"record_id": int(record.get("id", 0)), "amount": int(record.get("amount", 0))})
	return result


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
			update_resource_amount(int(record.get("id", 0)), 0)


func _update_resource_chunks(active_rect: Rect2, load_candidates: Array[Dictionary]):
	var desired_chunks := _get_chunks_in_rect(active_rect, RESOURCE_CHUNK_SIZE)
	for chunk in _active_resource_chunks.keys():
		if not desired_chunks.has(chunk):
			_set_resource_chunk_active(chunk, false)
	_active_resource_chunks = desired_chunks
	for chunk in desired_chunks:
		for record in _resource_chunks.get(chunk, []):
			if int(record.get("amount", 0)) <= 0:
				continue
			var resource = record.get("node")
			var already_active := is_instance_valid(resource) and bool(resource.get("lod_active"))
			if not already_active:
				load_candidates.append(_make_load_candidate(&"resource", record.get("position", Vector2.ZERO), record))


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
	resource.lod_manager = self
	record["node"] = resource
	return resource


func _sync_resource_record(record: Dictionary):
	var resource = record.get("node")
	if not is_instance_valid(resource):
		return
	record["amount"] = resource.wood_amount if record.get("kind", "tree") == "tree" else resource.stone_amount


func _update_buildings(active_rect: Rect2, load_candidates: Array[Dictionary]):
	var buildings: Array = _world_index.get_all_buildings_view() if is_instance_valid(_world_index) and _world_index.has_method("get_all_buildings_view") else get_tree().get_nodes_in_group("buildings")
	for candidate in buildings:
		if candidate is not Building or not get_parent().is_ancestor_of(candidate):
			continue
		var building := candidate as Building
		var building_id := building.get_instance_id()
		if not active_rect.has_point(building.global_position):
			_progressively_active_buildings.erase(building_id)
			building.set_lod_active(false)
		elif not _progressively_active_buildings.has(building_id):
			building.set_lod_active(false)
			load_candidates.append(_make_load_candidate(&"building", building.global_position, building))


func get_nearby_units(point: Vector2) -> Array:
	var result: Array = []
	var center := _point_to_chunk(point, UNIT_CHUNK_SIZE)
	for x in range(center.x - 1, center.x + 2):
		for y in range(center.y - 1, center.y + 2):
			for unit in _unit_chunks.get(Vector2i(x, y), []):
				if is_instance_valid(unit) and unit is Unit:
					result.append(unit)
	return result


func find_nearest_resource(resource_type: StringName, point: Vector2) -> Node2D:
	var center := _point_to_chunk(point, RESOURCE_CHUNK_SIZE)
	var furthest_radius := 0
	for chunk in _resource_chunks:
		furthest_radius = maxi(furthest_radius, maxi(absi(chunk.x - center.x), absi(chunk.y - center.y)))
	var nearest_record: Dictionary = {}
	var nearest_distance := INF
	for radius in range(furthest_radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			for y in range(center.y - radius, center.y + radius + 1):
				if radius > 0 and absi(x - center.x) != radius and absi(y - center.y) != radius:
					continue
				for record in _resource_chunks.get(Vector2i(x, y), []):
					if int(record.get("amount", 0)) <= 0 or record.get("resource_type") != resource_type:
						continue
					var distance: float = point.distance_squared_to(record.position)
					if distance < nearest_distance:
						nearest_record = record
						nearest_distance = distance
		# Завершаем поиск только когда ближайшая граница ещё не просмотренных
		# чанков дальше уже найденного ресурса. Так сохраняется индексированный
		# поиск, но занятость дерева или камня больше не уводит юнита вдаль.
		if not nearest_record.is_empty():
			var scanned_minimum := Vector2(center - Vector2i.ONE * radius) * RESOURCE_CHUNK_SIZE
			var scanned_maximum := Vector2(center + Vector2i.ONE * (radius + 1)) * RESOURCE_CHUNK_SIZE
			var distance_to_unscanned := minf(
				minf(point.x - scanned_minimum.x, scanned_maximum.x - point.x),
				minf(point.y - scanned_minimum.y, scanned_maximum.y - point.y)
			)
			if nearest_distance <= distance_to_unscanned * distance_to_unscanned:
				break
	return _get_or_materialize_resource(nearest_record)


func find_resource_near_position(resource_type: StringName, point: Vector2, tolerance := 32.0) -> Node2D:
	var search_area := Rect2(point - Vector2.ONE * tolerance, Vector2.ONE * tolerance * 2.0)
	var nearest_record: Dictionary = {}
	var nearest_distance := tolerance * tolerance
	for chunk in _get_chunks_in_rect(search_area, RESOURCE_CHUNK_SIZE):
		for record in _resource_chunks.get(chunk, []):
			if int(record.get("amount", 0)) <= 0 or record.get("resource_type") != resource_type:
				continue
			var distance: float = point.distance_squared_to(record.get("position", Vector2.ZERO))
			if distance <= nearest_distance:
				nearest_distance = distance
				nearest_record = record
	return _get_or_materialize_resource(nearest_record)


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
