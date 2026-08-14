extends Node2D

const MAP_WIDTH := 200
const MAP_HEIGHT := 200
const TILE_SIZE := 64
const FOREST_NOISE_FREQUENCY := 0.0003
const FOREST_THRESHOLD := 0.2
const TREE_SPACING := 32
const UNIT_SCENE := preload("res://scenes/objects/unit.tscn")
const RESIDENCE_SCENE := preload("res://scenes/objects/buildings/residence.tscn")
const WAREHOUSE_SCENE := preload("res://scenes/objects/buildings/warehouse.tscn")
const FACTORY_SCENE := preload("res://scenes/objects/buildings/fabric.tscn")
const FOOD_FACTORY_SCENE := preload("res://scenes/objects/buildings/food_fabric.tscn")
const MINE_SCENE := preload("res://scenes/objects/buildings/mine.tscn")
const POWER_PLANT_SCENE := preload("res://scenes/objects/buildings/power_plant.tscn")
const BARRACKS_SCENE := preload("res://scenes/objects/buildings/barracks.tscn")
const MILITARY_FACTORY_SCENE := preload("res://scenes/objects/buildings/military_factory.tscn")
const GOVERNMENT_SCENE := preload("res://scenes/objects/buildings/government.tscn")
const LUMBERJACK_CABIN_SCENE := preload("res://scenes/objects/buildings/lumberjack_cabin.tscn")
const ROAD_SCENE := preload("res://scenes/objects/buildings/road.tscn")
const SPAWN_MARGIN := 320.0
const SPAWN_CLEAR_RADIUS := 230.0
const AI_STRATEGY_INTERVAL := 6.0
const AI_MAX_CONSTRUCTION_BACKLOG := 2
const AI_MIN_CIVILIAN_WORKERS := 6
const AI_ATTACK_MIN_SOLDIERS := 8
const AI_STARTING_WOOD := 55
const AI_STARTING_STONE := 30
const AI_STARTING_COAL := 12
const AI_STARTING_FOOD := 90
const AI_DISTRICT_COLUMNS := 3
const AI_DISTRICT_COLUMN_STEP := 448.0
const AI_DISTRICT_ROW_STEP := 256.0
const AI_DISTRICT_BUILDING_ROW_OFFSET := 62.0
const AI_DISTRICT_BUILDING_X_SLOTS: Array[float] = [-176.0, -80.0, 80.0, 176.0]
const AI_DISTRICT_SEARCH_ATTEMPTS := 12
const OFFENSIVE_UPDATE_INTERVAL := 0.25
const OFFENSIVE_COMMANDER_ARRIVAL_DISTANCE := 28.0
const FRONT_COMMAND_REISSUE_DISTANCE := 32.0
const MILITARY_LINE_POINT_SPACING := 48.0
const MILITARY_LINE_BLEND_DISTANCE := 96.0
const MILITARY_LINE_SMOOTH_PASSES := 3
const MILITARY_LINE_MAX_SAMPLES := 384
const MILITARY_LINE_GEOMETRY_VERSION := 1

@export var starting_unit_count := 5
@export var unit_spawn_position := Vector2(300, 300)
@export var unit_spacing := 40.0
@export var generate_world_on_ready := true


func spawn_starting_units():
	spawn_session_units(_get_default_session_slots())

var forest_noise := FastNoiseLite.new()

var grass_textures = [
	preload("res://assets/terrain/grass/grass1.png"),
	preload("res://assets/terrain/grass/grass2.png"),
	preload("res://assets/terrain/grass/grass3.png")
]

var tree_textures = [
	preload("res://assets/objects/nature/trees/tree1.png"),
	preload("res://assets/objects/nature/trees/tree2.png"),
	preload("res://assets/objects/nature/trees/tree3.png")
]

const TREE_SCENE := preload("res://scenes/objects/tree.tscn")
const ROCK_SCENE := preload("res://scenes/objects/rock.tscn")

var rng := RandomNumberGenerator.new()
var world_seed := 12345
var ai_strategy_timer := 2.0
var ai_strategy_cycle := 0
var ai_emergency_food_given := {}
var military_front_lines := {}
var military_offensive_timer := 0.0

func generate_ground():
	# Один TileMapLayer хранит и отрисовывает землю чанками. Раньше для карты
	# создавалось 40 000 отдельных Sprite2D, из-за чего даже невидимая часть
	# мира оставалась тяжёлой для SceneTree.
	var ground_layer := TileMapLayer.new()
	ground_layer.name = "GroundTiles"
	ground_layer.position = -Vector2.ONE * TILE_SIZE * 0.5
	ground_layer.rendering_quadrant_size = 16
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i.ONE * TILE_SIZE
	var source_ids: Array[int] = []
	for grass_texture in grass_textures:
		var source := TileSetAtlasSource.new()
		source.texture = grass_texture
		source.texture_region_size = Vector2i.ONE * TILE_SIZE
		source.create_tile(Vector2i.ZERO)
		source_ids.append(tile_set.add_source(source))
	ground_layer.tile_set = tile_set
	$ground.add_child(ground_layer)
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var source_id := source_ids[rng.randi_range(0, source_ids.size() - 1)]
			ground_layer.set_cell(Vector2i(x, y), source_id, Vector2i.ZERO)


func spawn_tree(pos: Vector2):
	var variant := rng.randi_range(0, tree_textures.size() - 1)
	var lod_manager := get_node_or_null("SimulationLODManager")
	if is_instance_valid(lod_manager) and lod_manager.has_method("register_resource_data"):
		lod_manager.register_resource_data("tree", pos, variant, 20)
		return
	var tree = TREE_SCENE.instantiate()
	tree.tree_variant = variant
	tree.position = pos
	$trees.add_child(tree)


func spawn_rock(pos: Vector2):
	var variant := rng.randi_range(0, 2)
	var lod_manager := get_node_or_null("SimulationLODManager")
	if is_instance_valid(lod_manager) and lod_manager.has_method("register_resource_data"):
		lod_manager.register_resource_data("rock", pos, variant, 30)
		return
	var rock = ROCK_SCENE.instantiate()
	rock.rock_variant = variant
	rock.position = pos
	$rocks.add_child(rock)


func generate_rock_deposits():
	# Редкие небольшие залежи по 2–5 камней.
	for x in range(96, MAP_WIDTH * TILE_SIZE, 192):
		for y in range(96, MAP_HEIGHT * TILE_SIZE, 192):
			if rng.randf() > 0.06:
				continue
			var center := Vector2(x, y) + Vector2(rng.randf_range(-64, 64), rng.randf_range(-64, 64))
			for i in range(rng.randi_range(2, 5)):
				var angle := rng.randf_range(0.0, TAU)
				var offset := Vector2.from_angle(angle) * rng.randf_range(10.0, 35.0)
				spawn_rock(center + offset)

func generate_forest():
	for x in range(0, MAP_WIDTH * TILE_SIZE, TREE_SPACING):
		for y in range(0, MAP_HEIGHT * TILE_SIZE, TREE_SPACING):
			
			var value = forest_noise.get_noise_2d(x, y)
			
			if value > FOREST_THRESHOLD:
				spawn_tree(Vector2(x + rng.randf_range(0, 16), y + rng.randf_range(0, 16)))

				
func _ready():
	var save_manager := get_node_or_null("/root/SaveManager")
	var network_manager := get_node_or_null("/root/NetworkManager")
	world_seed = int(save_manager.current_seed) if is_instance_valid(save_manager) else 12345
	rng.seed = world_seed

	forest_noise.seed = world_seed
	forest_noise.frequency = FOREST_NOISE_FREQUENCY

	if generate_world_on_ready:
		generate_ground()
		generate_forest()
		generate_rock_deposits()
	var saved_state: Dictionary = save_manager.consume_pending_save() if is_instance_valid(save_manager) else {}
	if not saved_state.is_empty():
		if is_instance_valid(network_manager) and not network_manager.is_lan_session():
			network_manager.prepare_loaded_game(saved_state.get("session_slots", []))
		apply_save_data(saved_state)
		if is_instance_valid(network_manager) and network_manager.has_session():
			_spawn_missing_loaded_factions(network_manager.get_session_slots())
	elif generate_world_on_ready:
		Unit.next_name_index = 0
		var slots: Array = network_manager.get_session_slots() if is_instance_valid(network_manager) and network_manager.has_session() else _get_default_session_slots()
		spawn_session_units(slots)
	_ensure_persistent_entity_ids()
	if is_instance_valid(network_manager):
		network_manager.notify_world_ready()


func _get_indexed_units(faction_id := -1) -> Array:
	var index := get_node_or_null("WorldIndex")
	if is_instance_valid(index):
		return index.get_units(faction_id)
	var result: Array[Unit] = []
	for candidate in get_tree().get_nodes_in_group("units"):
		if candidate is Unit and is_ancestor_of(candidate) and (faction_id < 0 or candidate.faction_id == faction_id):
			result.append(candidate)
	return result


func _get_indexed_buildings(building_kind := "", faction_id := -1) -> Array:
	var index := get_node_or_null("WorldIndex")
	if is_instance_valid(index):
		return index.get_buildings(faction_id, building_kind)
	var result: Array[Building] = []
	for candidate in get_tree().get_nodes_in_group("buildings"):
		if candidate is Building and is_ancestor_of(candidate) and (faction_id < 0 or candidate.faction_id == faction_id) and (building_kind.is_empty() or candidate.building_kind == building_kind):
			result.append(candidate)
	return result


func _process(delta: float):
	military_offensive_timer -= delta
	if military_offensive_timer <= 0.0:
		military_offensive_timer = OFFENSIVE_UPDATE_INTERVAL
		_update_active_military_offensives()
	ai_strategy_timer -= delta
	if ai_strategy_timer > 0.0:
		return
	ai_strategy_timer = AI_STRATEGY_INTERVAL
	ai_strategy_cycle += 1
	_run_ai_strategy()


func get_military_front_lines(faction_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_plan in military_front_lines.values():
		if raw_plan is Dictionary and int(raw_plan.get("faction_id", -1)) == faction_id:
			result.append(raw_plan.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		return str(a.get("line_id", "")) < str(b.get("line_id", ""))
	)
	return result


func find_military_front_at(faction_id: int, point: Vector2, maximum_distance := 24.0) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance := maximum_distance
	for plan in get_military_front_lines(faction_id):
		var front_points := _coerce_military_line_points(plan.get("front_points", []))
		if front_points.size() < 2:
			continue
		var projection := _project_onto_military_polyline(point, front_points)
		var position: Vector2 = projection.get("position", point)
		var distance := point.distance_to(position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = {
				"line_id": str(plan.get("line_id", "")),
				"position": position,
				"squad_ids": plan.get("squad_ids", []).duplicate(),
			}
	return nearest


func has_military_front_line(faction_id: int, line_id: String) -> bool:
	if not military_front_lines.has(line_id):
		return false
	return int(military_front_lines[line_id].get("faction_id", -1)) == faction_id


func apply_military_plan_command(faction_id: int, commanders: Array[Unit], action: StringName, payload: Dictionary) -> bool:
	var line_id := str(payload.get("line_id", "")).strip_edges().left(96)
	if line_id.is_empty():
		return false
	var squad_ids: Array[int] = []
	for commander in commanders:
		if is_instance_valid(commander) and commander.faction_id == faction_id and commander.is_squad_commander() and commander.squad_id not in squad_ids:
			squad_ids.append(commander.squad_id)
	match action:
		&"create_front":
			var front_points := _prepare_military_line(payload.get("points", []), MILITARY_LINE_SMOOTH_PASSES)
			if front_points.size() < 2 or squad_ids.is_empty():
				return false
			_detach_squads_from_other_fronts(faction_id, squad_ids, line_id)
			military_front_lines[line_id] = {
				"line_id": line_id,
				"faction_id": faction_id,
				"name": _make_military_front_name(faction_id),
				"front_points": front_points,
				"offensive_points": [],
				"has_offensive": false,
				"offensive_active": false,
				"attacking_squad_ids": [],
				"squad_ids": squad_ids,
				"attach_all": _squad_ids_cover_whole_army(faction_id, squad_ids),
			}
			_redistribute_military_front(line_id, false)
			return true
		&"set_offensive":
			if not has_military_front_line(faction_id, line_id):
				return false
			var offensive_points := _prepare_military_line(payload.get("points", []), MILITARY_LINE_SMOOTH_PASSES)
			if offensive_points.size() < 2:
				return false
			var offensive_plan: Dictionary = military_front_lines[line_id]
			offensive_plan["offensive_points"] = offensive_points
			offensive_plan["has_offensive"] = true
			offensive_plan["offensive_active"] = false
			offensive_plan["attacking_squad_ids"] = []
			# Drawing is planning only. It must not reissue orders even to the troops
			# already holding the front; movement starts after an explicit command.
			return true
		&"start_offensive":
			if not has_military_front_line(faction_id, line_id):
				return false
			var start_plan: Dictionary = military_front_lines[line_id]
			if not bool(start_plan.get("has_offensive", false)) or bool(start_plan.get("offensive_active", false)):
				return false
			var attackers := _select_local_offensive_commanders(start_plan)
			if attackers.is_empty():
				return false
			var attacking_ids: Array[int] = []
			for commander in attackers:
				attacking_ids.append(commander.squad_id)
			start_plan["attacking_squad_ids"] = attacking_ids
			start_plan["offensive_active"] = true
			_send_commanders_to_military_line(attackers, _coerce_military_line_points(start_plan.get("offensive_points", [])), &"offensive_line")
			return true
		&"stop_offensive":
			if not has_military_front_line(faction_id, line_id):
				return false
			var stop_plan: Dictionary = military_front_lines[line_id]
			if not bool(stop_plan.get("offensive_active", false)):
				return false
			var stopped_squad_ids: Array = stop_plan.get("attacking_squad_ids", []).duplicate()
			stop_plan["offensive_active"] = false
			stop_plan["attacking_squad_ids"] = []
			_return_squads_to_military_front(stop_plan, stopped_squad_ids)
			return true
		&"delete_offensive":
			if not has_military_front_line(faction_id, line_id):
				return false
			var clear_plan: Dictionary = military_front_lines[line_id]
			if not bool(clear_plan.get("has_offensive", false)):
				return false
			var returning_squad_ids: Array = clear_plan.get("attacking_squad_ids", []).duplicate()
			clear_plan["offensive_active"] = false
			clear_plan["attacking_squad_ids"] = []
			clear_plan["has_offensive"] = false
			clear_plan["offensive_points"] = []
			_return_squads_to_military_front(clear_plan, returning_squad_ids)
			return true
		&"return_to_front":
			if not has_military_front_line(faction_id, line_id) or squad_ids.is_empty():
				return false
			var return_plan: Dictionary = military_front_lines[line_id]
			var attached_squad_ids: Array = return_plan.get("squad_ids", [])
			for squad_id in squad_ids:
				if squad_id not in attached_squad_ids:
					return false
			var raw_preferred_point: Variant = payload.get("point", Vector2.ZERO)
			if raw_preferred_point is not Vector2:
				return false
			var preferred_point: Vector2 = raw_preferred_point
			_return_commanders_to_front(return_plan, commanders, preferred_point)
			var active_attackers: Array = return_plan.get("attacking_squad_ids", []).duplicate()
			for squad_id in squad_ids:
				active_attackers.erase(squad_id)
			return_plan["attacking_squad_ids"] = active_attackers
			if active_attackers.is_empty():
				return_plan["offensive_active"] = false
			return true
		&"attach":
			if not has_military_front_line(faction_id, line_id) or squad_ids.is_empty():
				return false
			if bool(military_front_lines[line_id].get("offensive_active", false)):
				return false
			_detach_squads_from_other_fronts(faction_id, squad_ids, line_id)
			var attach_plan: Dictionary = military_front_lines[line_id]
			var attached: Array = attach_plan.get("squad_ids", [])
			for squad_id in squad_ids:
				if squad_id not in attached:
					attached.append(squad_id)
			attach_plan["squad_ids"] = attached
			attach_plan["attach_all"] = _squad_ids_cover_whole_army(faction_id, attached)
			_redistribute_military_front(line_id, false)
			return true
		&"detach":
			if not has_military_front_line(faction_id, line_id) or squad_ids.is_empty():
				return false
			if bool(military_front_lines[line_id].get("offensive_active", false)):
				return false
			var detach_plan: Dictionary = military_front_lines[line_id]
			var remaining: Array = detach_plan.get("squad_ids", []).duplicate()
			var previously_attached := remaining.duplicate()
			for squad_id in squad_ids:
				remaining.erase(squad_id)
			detach_plan["squad_ids"] = remaining
			detach_plan["attach_all"] = false
			for commander in commanders:
				if is_instance_valid(commander) and commander.is_squad_commander() and commander.squad_id in previously_attached:
					commander.issue_squad_order(&"hold")
			_redistribute_military_front(line_id, false)
			return true
		&"delete":
			if not has_military_front_line(faction_id, line_id):
				return false
			var delete_plan: Dictionary = military_front_lines[line_id]
			for commander in _get_front_squad_commanders(faction_id, delete_plan.get("squad_ids", [])):
				commander.issue_squad_order(&"hold")
			military_front_lines.erase(line_id)
			return true
	return false


func _make_military_front_name(faction_id: int) -> String:
	var used_names := {}
	for plan in get_military_front_lines(faction_id):
		used_names[str(plan.get("name", ""))] = true
	var index := 1
	while used_names.has("Линия фронта %d" % index):
		index += 1
	return "Линия фронта %d" % index


func _squad_ids_cover_whole_army(faction_id: int, raw_squad_ids: Array) -> bool:
	var expected := {}
	for unit in _get_indexed_units(faction_id):
		if unit is Unit and unit.is_squad_commander():
			expected[unit.squad_id] = true
	if expected.is_empty():
		return false
	for squad_id in expected.keys():
		if squad_id not in raw_squad_ids:
			return false
	return true


func refresh_military_front_assignments(faction_id: int):
	var all_squad_ids: Array[int] = []
	for unit in _get_indexed_units(faction_id):
		if unit is Unit and unit.is_squad_commander() and unit.squad_id not in all_squad_ids:
			all_squad_ids.append(unit.squad_id)
	for line_id in military_front_lines.keys():
		var plan: Dictionary = military_front_lines[line_id]
		if int(plan.get("faction_id", -1)) != faction_id:
			continue
		var attached: Array = plan.get("squad_ids", []).duplicate()
		for index in range(attached.size() - 1, -1, -1):
			if int(attached[index]) not in all_squad_ids:
				attached.remove_at(index)
		if bool(plan.get("attach_all", false)):
			for squad_id in all_squad_ids:
				if squad_id not in attached:
					attached.append(squad_id)
		plan["squad_ids"] = attached
		if not bool(plan.get("offensive_active", false)):
			_redistribute_military_front(str(line_id), false)


func _detach_squads_from_other_fronts(faction_id: int, squad_ids: Array[int], except_line_id: String):
	var changed_lines: Array[String] = []
	for raw_line_id in military_front_lines.keys():
		var other_line_id := str(raw_line_id)
		if other_line_id == except_line_id:
			continue
		var plan: Dictionary = military_front_lines[raw_line_id]
		if int(plan.get("faction_id", -1)) != faction_id:
			continue
		var attached: Array = plan.get("squad_ids", []).duplicate()
		var changed := false
		for squad_id in squad_ids:
			if squad_id in attached:
				attached.erase(squad_id)
				changed = true
		if changed:
			plan["squad_ids"] = attached
			plan["attach_all"] = false
			changed_lines.append(other_line_id)
	for changed_line_id in changed_lines:
		var changed_plan: Dictionary = military_front_lines[changed_line_id]
		_redistribute_military_front(changed_line_id, false)


func _redistribute_military_front(line_id: String, use_offensive: bool):
	if not military_front_lines.has(line_id):
		return
	var plan: Dictionary = military_front_lines[line_id]
	var points := _coerce_military_line_points(plan.get("offensive_points" if use_offensive else "front_points", []))
	if points.size() < 2:
		return
	var commanders := _get_front_squad_commanders(int(plan.get("faction_id", -1)), plan.get("squad_ids", []))
	_send_commanders_to_military_line(commanders, points, &"offensive_line" if use_offensive else &"front_line")


func _send_commanders_to_military_line(commanders: Array[Unit], points: Array[Vector2], order: StringName):
	if commanders.is_empty() or points.size() < 2:
		return
	for assignment in _make_military_line_assignments(commanders, points):
		var commander := assignment.get("commander") as Unit
		if is_instance_valid(commander):
			commander._command_military_move(
				assignment.get("destination", commander.global_position),
				order,
				assignment.get("direction", Vector2.RIGHT)
			)


func _make_military_line_assignments(commanders: Array[Unit], points: Array[Vector2]) -> Array[Dictionary]:
	var assignments: Array[Dictionary] = []
	if commanders.is_empty() or points.size() < 2:
		return assignments
	var ordered_commanders: Array[Unit] = commanders.duplicate()
	# Keep neighbouring squads neighbouring on the line. Assigning solely by
	# squad id made distant squads cross through one another and deadlock.
	ordered_commanders.sort_custom(func(a: Unit, b: Unit):
		var a_ratio := float(_project_onto_military_polyline(a.global_position, points).get("ratio", 0.0))
		var b_ratio := float(_project_onto_military_polyline(b.global_position, points).get("ratio", 0.0))
		return a_ratio < b_ratio if not is_equal_approx(a_ratio, b_ratio) else a.squad_id < b.squad_id
	)
	for index in range(ordered_commanders.size()):
		var ratio := 0.5 if ordered_commanders.size() == 1 else float(index) / float(ordered_commanders.size() - 1)
		var sample := _sample_military_polyline(points, ratio)
		assignments.append({
			"commander": ordered_commanders[index],
			"destination": sample.get("position", ordered_commanders[index].global_position),
			"direction": sample.get("direction", Vector2.RIGHT),
		})
	return assignments


func _select_local_offensive_commanders(plan: Dictionary) -> Array[Unit]:
	var offensive_points := _coerce_military_line_points(plan.get("offensive_points", []))
	var commanders := _get_front_squad_commanders(int(plan.get("faction_id", -1)), plan.get("squad_ids", []))
	if commanders.is_empty() or offensive_points.size() < 2:
		var empty_result: Array[Unit] = []
		return empty_result
	var ranked: Array[Dictionary] = []
	for commander in commanders:
		var sector_position: Vector2 = commander.target_position if commander.military_order == &"front_line" else commander.global_position
		ranked.append({"commander": commander, "distance": _distance_to_military_polyline(sector_position, offensive_points)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.distance) < float(b.distance))
	var offensive_length := _get_military_polyline_length(offensive_points)
	var desired_count := clampi(ceili(offensive_length / 220.0), 1, commanders.size())
	var local_radius := float(ranked[0].distance) + maxf(160.0, offensive_length * 0.35)
	var result: Array[Unit] = []
	for entry in ranked:
		if result.size() >= desired_count:
			break
		if result.is_empty() or float(entry.distance) <= local_radius:
			result.append(entry.commander)
	return result


func _update_active_military_offensives():
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager) and network_manager.has_method("is_remote_client") and network_manager.is_remote_client():
		return
	for raw_line_id in military_front_lines.keys():
		var plan: Dictionary = military_front_lines[raw_line_id]
		_maintain_military_front_orders(plan)
		if not bool(plan.get("offensive_active", false)):
			continue
		var attackers := _get_front_squad_commanders(int(plan.get("faction_id", -1)), plan.get("attacking_squad_ids", []))
		if attackers.is_empty():
			_cancel_military_offensive(str(raw_line_id))
			continue
		var all_arrived := true
		for commander in attackers:
			if not _has_offensive_squad_arrived(commander):
				all_arrived = false
				break
		if all_arrived:
			_complete_military_offensive(str(raw_line_id))


func _has_offensive_squad_arrived(commander: Unit) -> bool:
	if not is_instance_valid(commander) or commander.military_order != &"offensive_line":
		return false
	# The commander is the squad's assigned point on the operational line.
	# Soldiers keep following and spreading around that point, but an outer
	# formation member must not prevent the front from advancing forever.
	return commander.global_position.distance_to(commander.target_position) <= OFFENSIVE_COMMANDER_ARRIVAL_DISTANCE


func _maintain_military_front_orders(plan: Dictionary):
	var faction_id := int(plan.get("faction_id", -1))
	var offensive_active := bool(plan.get("offensive_active", false))
	var squad_ids: Array = plan.get("attacking_squad_ids", []) if offensive_active else plan.get("squad_ids", [])
	var points := _coerce_military_line_points(plan.get("offensive_points", [])) if offensive_active else _coerce_military_line_points(plan.get("front_points", []))
	if points.size() < 2:
		return
	var order: StringName = &"offensive_line" if offensive_active else &"front_line"
	var commanders := _get_front_squad_commanders(faction_id, squad_ids)
	for commander in commanders:
		if not is_instance_valid(commander):
			continue
		# A direct player move temporarily overrides the automatic front order.
		# The commander returns only after an explicit click on the front line.
		if commander.military_order == &"move":
			continue
		# Preserve every squad's assigned sector. Re-sampling all destinations on
		# every update would move quiet parts of a long front after a local attack.
		var projection_source := commander.target_position if commander.military_order == order else commander.global_position
		var projection := _project_onto_military_polyline(projection_source, points)
		var destination: Vector2 = projection.get("position", commander.global_position)
		var sample := _sample_military_polyline(points, float(projection.get("ratio", 0.0)))
		var lost_order := commander.military_order != order
		var wrong_target := commander.target_position.distance_to(destination) > FRONT_COMMAND_REISSUE_DISTANCE
		var stopped_early := commander.task != Unit.Task.MOVE and commander.global_position.distance_to(destination) > FRONT_COMMAND_REISSUE_DISTANCE
		if lost_order or wrong_target or stopped_early:
			commander._command_military_move(destination, order, sample.get("direction", Vector2.RIGHT))


func _return_squads_to_military_front(plan: Dictionary, squad_ids: Array):
	var front_points := _coerce_military_line_points(plan.get("front_points", []))
	if front_points.size() < 2 or squad_ids.is_empty():
		return
	var faction_id := int(plan.get("faction_id", -1))
	for commander in _get_front_squad_commanders(faction_id, squad_ids):
		# Return each attacking squad to the closest part of the old front. This
		# keeps a cancelled local offensive local and does not shift quiet sectors.
		var projection := _project_onto_military_polyline(commander.global_position, front_points)
		var destination: Vector2 = projection.get("position", commander.global_position)
		var sample := _sample_military_polyline(front_points, float(projection.get("ratio", 0.0)))
		commander._command_military_move(destination, &"front_line", sample.get("direction", Vector2.RIGHT))


func _return_commanders_to_front(plan: Dictionary, commanders: Array[Unit], preferred_point: Vector2):
	var front_points := _coerce_military_line_points(plan.get("front_points", []))
	if front_points.size() < 2 or commanders.is_empty():
		return
	var center_projection := _project_onto_military_polyline(preferred_point, front_points)
	var center_ratio := float(center_projection.get("ratio", 0.5))
	var front_length := maxf(_get_military_polyline_length(front_points), 1.0)
	var ratio_spacing := 72.0 / front_length
	var ordered_commanders: Array[Unit] = commanders.duplicate()
	ordered_commanders.sort_custom(func(a: Unit, b: Unit): return a.squad_id < b.squad_id)
	for index in range(ordered_commanders.size()):
		var centered_index := float(index) - float(ordered_commanders.size() - 1) * 0.5
		var target_ratio := clampf(center_ratio + centered_index * ratio_spacing, 0.0, 1.0)
		var sample := _sample_military_polyline(front_points, target_ratio)
		ordered_commanders[index]._command_military_move(
			sample.get("position", preferred_point),
			&"front_line",
			sample.get("direction", Vector2.RIGHT)
		)


func _cancel_military_offensive(line_id: String):
	if not military_front_lines.has(line_id):
		return
	var plan: Dictionary = military_front_lines[line_id]
	plan["offensive_active"] = false
	plan["attacking_squad_ids"] = []
	plan["has_offensive"] = false
	plan["offensive_points"] = []
	_redistribute_military_front(line_id, false)


func _complete_military_offensive(line_id: String):
	if not military_front_lines.has(line_id):
		return
	var plan: Dictionary = military_front_lines[line_id]
	var attacking_ids: Array = plan.get("attacking_squad_ids", []).duplicate()
	plan["front_points"] = _merge_offensive_into_front(
		_coerce_military_line_points(plan.get("front_points", [])),
		_coerce_military_line_points(plan.get("offensive_points", []))
	)
	plan["offensive_active"] = false
	plan["attacking_squad_ids"] = []
	plan["has_offensive"] = false
	plan["offensive_points"] = []
	# Troops outside the attacked sector keep their exact positions. Only the
	# squads that reached the objective switch from attack back to holding the
	# newly advanced local front.
	for commander in _get_front_squad_commanders(int(plan.get("faction_id", -1)), attacking_ids):
		commander.military_order = &"front_line"
		commander.squad_command_timer = 0.0
		commander._broadcast_squad_follow_targets()


func _get_front_squad_commanders(faction_id: int, raw_squad_ids) -> Array[Unit]:
	var squad_ids := {}
	var commanders: Array[Unit] = []
	if raw_squad_ids is not Array:
		return commanders
	for raw_id in raw_squad_ids:
		squad_ids[int(raw_id)] = true
	for unit in _get_indexed_units(faction_id):
		if unit is Unit and unit.is_squad_commander() and squad_ids.has(unit.squad_id):
			commanders.append(unit)
	# Взводы получают соседние участки, а их отряды — соседние точки участка.
	commanders.sort_custom(func(a: Unit, b: Unit):
		return a.platoon_id < b.platoon_id if a.platoon_id != b.platoon_id else a.squad_id < b.squad_id
	)
	return commanders


func _sample_military_polyline(points: Array[Vector2], ratio: float) -> Dictionary:
	var total_length := 0.0
	var lengths: Array[float] = []
	for index in range(points.size() - 1):
		var segment_length := points[index].distance_to(points[index + 1])
		lengths.append(segment_length)
		total_length += segment_length
	if total_length <= 0.001:
		return {"position": points[0], "direction": Vector2.RIGHT}
	var target_distance := clampf(ratio, 0.0, 1.0) * total_length
	var walked := 0.0
	for index in range(lengths.size()):
		var segment_length := lengths[index]
		if target_distance <= walked + segment_length or index == lengths.size() - 1:
			var local_ratio := clampf((target_distance - walked) / maxf(segment_length, 0.001), 0.0, 1.0)
			return {
				"position": points[index].lerp(points[index + 1], local_ratio),
				"direction": points[index].direction_to(points[index + 1]),
			}
		walked += segment_length
	return {"position": points.back(), "direction": Vector2.RIGHT}


func _get_military_polyline_length(points: Array[Vector2]) -> float:
	var result := 0.0
	for index in range(points.size() - 1):
		result += points[index].distance_to(points[index + 1])
	return result


func _distance_to_military_polyline(point: Vector2, points: Array[Vector2]) -> float:
	var projection := _project_onto_military_polyline(point, points)
	return point.distance_to(projection.get("position", point))


func _project_onto_military_polyline(point: Vector2, points: Array[Vector2]) -> Dictionary:
	if points.is_empty():
		return {"position": point, "ratio": 0.0}
	var total_length := _get_military_polyline_length(points)
	if total_length <= 0.001:
		return {"position": points[0], "ratio": 0.0}
	var nearest_position := points[0]
	var nearest_distance := INF
	var nearest_walked := 0.0
	var walked := 0.0
	for index in range(points.size() - 1):
		var start := points[index]
		var finish := points[index + 1]
		var segment := finish - start
		var segment_length := segment.length()
		if segment_length <= 0.001:
			continue
		var local_ratio := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
		var candidate := start + segment * local_ratio
		var distance := point.distance_squared_to(candidate)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_position = candidate
			nearest_walked = walked + segment_length * local_ratio
		walked += segment_length
	return {"position": nearest_position, "ratio": nearest_walked / total_length}


func _project_onto_military_polyline_range(point: Vector2, points: Array[Vector2], minimum_ratio: float, maximum_ratio: float) -> Dictionary:
	if points.is_empty():
		return {"position": point, "ratio": 0.0}
	var total_length := _get_military_polyline_length(points)
	if total_length <= 0.001:
		return {"position": points[0], "ratio": 0.0}
	var range_start := clampf(minimum_ratio, 0.0, 1.0)
	var range_end := clampf(maximum_ratio, range_start, 1.0)
	var nearest_position: Vector2 = _sample_military_polyline(points, range_start).get("position", points[0])
	var nearest_distance := INF
	var nearest_walked := range_start * total_length
	var walked := 0.0
	for index in range(points.size() - 1):
		var start := points[index]
		var finish := points[index + 1]
		var segment := finish - start
		var segment_length := segment.length()
		if segment_length <= 0.001:
			continue
		var segment_start_ratio := walked / total_length
		var segment_end_ratio := (walked + segment_length) / total_length
		var overlap_start := maxf(segment_start_ratio, range_start)
		var overlap_end := minf(segment_end_ratio, range_end)
		if overlap_start <= overlap_end:
			var local_minimum := clampf((overlap_start * total_length - walked) / segment_length, 0.0, 1.0)
			var local_maximum := clampf((overlap_end * total_length - walked) / segment_length, local_minimum, 1.0)
			var local_ratio := clampf((point - start).dot(segment) / segment.length_squared(), local_minimum, local_maximum)
			var candidate := start + segment * local_ratio
			var distance := point.distance_squared_to(candidate)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_position = candidate
				nearest_walked = walked + segment_length * local_ratio
		walked += segment_length
	return {"position": nearest_position, "ratio": nearest_walked / total_length}


func _get_local_offensive_projections(front_points: Array[Vector2], offensive_points: Array[Vector2]) -> Array[Dictionary]:
	var first_projection := _project_onto_military_polyline(offensive_points[0], front_points)
	var last_projection := _project_onto_military_polyline(offensive_points.back(), front_points)
	var front_length := maxf(_get_military_polyline_length(front_points), 1.0)
	var offensive_ratio := _get_military_polyline_length(offensive_points) / front_length
	# On a folded front the globally closest points can belong to remote sectors.
	# Keep both flanks of one offensive within a local arc of the front, so a
	# short advance cannot accidentally consume a huge U-shaped section.
	var maximum_span := clampf(offensive_ratio * 1.35 + 0.06, 0.12, 0.45)
	if absf(float(first_projection.get("ratio", 0.0)) - float(last_projection.get("ratio", 0.0))) <= maximum_span:
		return [first_projection, last_projection]
	var first_ratio := float(first_projection.get("ratio", 0.0))
	var last_near_first := _project_onto_military_polyline_range(
		offensive_points.back(),
		front_points,
		first_ratio - maximum_span,
		first_ratio + maximum_span
	)
	var last_ratio := float(last_projection.get("ratio", 0.0))
	var first_near_last := _project_onto_military_polyline_range(
		offensive_points[0],
		front_points,
		last_ratio - maximum_span,
		last_ratio + maximum_span
	)
	var first_anchor: Vector2 = first_projection.get("position", offensive_points[0])
	var last_near_first_anchor: Vector2 = last_near_first.get("position", offensive_points.back())
	var first_near_last_anchor: Vector2 = first_near_last.get("position", offensive_points[0])
	var last_anchor: Vector2 = last_projection.get("position", offensive_points.back())
	var anchor_first_score: float = offensive_points[0].distance_squared_to(first_anchor) \
		+ offensive_points.back().distance_squared_to(last_near_first_anchor)
	var anchor_last_score: float = offensive_points[0].distance_squared_to(first_near_last_anchor) \
		+ offensive_points.back().distance_squared_to(last_anchor)
	if anchor_last_score < anchor_first_score:
		return [first_near_last, last_projection]
	return [first_projection, last_near_first]


func _merge_offensive_into_front(front_points: Array[Vector2], offensive_points: Array[Vector2]) -> Array[Vector2]:
	if front_points.size() < 2 or offensive_points.size() < 2:
		return front_points
	var stable_front := _resample_military_polyline(_erase_military_polyline_loops(front_points), MILITARY_LINE_POINT_SPACING)
	var smooth_offensive := _prepare_military_line(offensive_points, MILITARY_LINE_SMOOTH_PASSES)
	if stable_front.size() < 2 or smooth_offensive.size() < 2:
		return front_points
	var projections := _get_local_offensive_projections(stable_front, smooth_offensive)
	var first_projection: Dictionary = projections[0]
	var last_projection: Dictionary = projections[1]
	var start_ratio := float(first_projection.get("ratio", 0.0))
	var end_ratio := float(last_projection.get("ratio", 1.0))
	var oriented_offensive: Array[Vector2] = smooth_offensive.duplicate()
	if start_ratio > end_ratio:
		var swap := start_ratio
		start_ratio = end_ratio
		end_ratio = swap
		oriented_offensive.reverse()
	# If both ends project onto nearly the same point, use the offensive width
	# to define a local sector around that point instead of replacing the whole
	# front or producing a zero-width advance.
	if end_ratio - start_ratio < 0.02:
		var center := (start_ratio + end_ratio) * 0.5
		var half_span := clampf(_get_military_polyline_length(oriented_offensive) / maxf(_get_military_polyline_length(stable_front), 1.0) * 0.5, 0.03, 0.25)
		start_ratio = maxf(center - half_span, 0.0)
		end_ratio = minf(center + half_span, 1.0)
	# Blend across a short piece of the old front on both sides. Smoothing only
	# the inserted local section preserves quiet sectors while removing the long
	# diagonal connectors and sharp V-shaped corners created by direct insertion.
	var front_length := maxf(_get_military_polyline_length(stable_front), 1.0)
	var blend_ratio := minf(MILITARY_LINE_BLEND_DISTANCE / front_length, 0.12)
	var blend_start_ratio := maxf(start_ratio - blend_ratio, 0.0)
	var blend_end_ratio := minf(end_ratio + blend_ratio, 1.0)
	var sample_count := clampi(ceili(front_length / MILITARY_LINE_POINT_SPACING), 1, MILITARY_LINE_MAX_SAMPLES)
	var merged: Array[Vector2] = []
	for index in range(sample_count + 1):
		var ratio := float(index) / float(sample_count)
		if ratio < blend_start_ratio:
			_append_unique_military_point(merged, _sample_military_polyline(stable_front, ratio).get("position", Vector2.ZERO))
	var transition: Array[Vector2] = []
	_append_unique_military_point(transition, _sample_military_polyline(stable_front, blend_start_ratio).get("position", Vector2.ZERO))
	_append_unique_military_point(transition, _sample_military_polyline(stable_front, start_ratio).get("position", Vector2.ZERO))
	for point in oriented_offensive:
		_append_unique_military_point(transition, point)
	_append_unique_military_point(transition, _sample_military_polyline(stable_front, end_ratio).get("position", Vector2.ZERO))
	_append_unique_military_point(transition, _sample_military_polyline(stable_front, blend_end_ratio).get("position", Vector2.ZERO))
	transition = _prepare_military_line(transition, MILITARY_LINE_SMOOTH_PASSES)
	for point in transition:
		_append_unique_military_point(merged, point)
	for index in range(sample_count + 1):
		var ratio := float(index) / float(sample_count)
		if ratio > blend_end_ratio:
			_append_unique_military_point(merged, _sample_military_polyline(stable_front, ratio).get("position", Vector2.ZERO))
	return _resample_military_polyline(_erase_military_polyline_loops(merged), MILITARY_LINE_POINT_SPACING)


func _prepare_military_line(raw_points, smooth_passes: int) -> Array[Vector2]:
	var points := _coerce_military_line_points(raw_points)
	if points.size() < 2:
		return points
	points = _erase_military_polyline_loops(points)
	points = _resample_military_polyline(points, MILITARY_LINE_POINT_SPACING)
	points = _smooth_military_polyline(points, smooth_passes)
	points = _erase_military_polyline_loops(points)
	return _resample_military_polyline(points, MILITARY_LINE_POINT_SPACING)


func _resample_military_polyline(points: Array[Vector2], spacing: float) -> Array[Vector2]:
	if points.size() < 2:
		return points.duplicate()
	var total_length := _get_military_polyline_length(points)
	if total_length <= 0.001:
		return [points[0]]
	var sample_count := clampi(ceili(total_length / maxf(spacing, 1.0)), 1, MILITARY_LINE_MAX_SAMPLES)
	var result: Array[Vector2] = []
	for index in range(sample_count + 1):
		var ratio := float(index) / float(sample_count)
		_append_unique_military_point(result, _sample_military_polyline(points, ratio).get("position", points[0]))
	return result


func _smooth_military_polyline(points: Array[Vector2], passes: int) -> Array[Vector2]:
	var result: Array[Vector2] = points.duplicate()
	if result.size() < 3:
		return result
	for pass_index in range(maxi(passes, 0)):
		var smoothed: Array[Vector2] = [result[0]]
		for index in range(1, result.size() - 1):
			var neighbour_center := (result[index - 1] + result[index + 1]) * 0.5
			smoothed.append(result[index].lerp(neighbour_center, 0.45))
		smoothed.append(result.back())
		result = smoothed
	return result


func _erase_military_polyline_loops(points: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = points.duplicate()
	var iteration := 0
	var changed := true
	while changed and result.size() >= 4 and iteration < 16:
		changed = false
		iteration += 1
		for first_index in range(result.size() - 1):
			for second_index in range(first_index + 2, result.size() - 1):
				var intersection = Geometry2D.segment_intersects_segment(
					result[first_index],
					result[first_index + 1],
					result[second_index],
					result[second_index + 1]
				)
				if intersection is not Vector2:
					continue
				var clean: Array[Vector2] = []
				for prefix_index in range(first_index + 1):
					_append_unique_military_point(clean, result[prefix_index])
				_append_unique_military_point(clean, intersection)
				for suffix_index in range(second_index + 1, result.size()):
					_append_unique_military_point(clean, result[suffix_index])
				result = clean
				changed = true
				break
			if changed:
				break
	return result


func _military_polyline_has_self_intersection(points: Array[Vector2]) -> bool:
	for first_index in range(points.size() - 1):
		for second_index in range(first_index + 2, points.size() - 1):
			if Geometry2D.segment_intersects_segment(
				points[first_index],
				points[first_index + 1],
				points[second_index],
				points[second_index + 1]
			) is Vector2:
				return true
	return false


func _append_unique_military_point(points: Array[Vector2], point: Vector2):
	if points.is_empty() or points.back().distance_to(point) >= 1.0:
		points.append(point)


func _coerce_military_line_points(raw_points) -> Array[Vector2]:
	var points: Array[Vector2] = []
	if raw_points is not Array:
		return points
	for raw_point in raw_points:
		if raw_point is Vector2:
			var vector_point: Vector2 = raw_point
			if points.is_empty() or points.back().distance_to(vector_point) >= 1.0:
				points.append(vector_point)
		elif raw_point is Array and raw_point.size() >= 2:
			var point := Vector2(float(raw_point[0]), float(raw_point[1]))
			if points.is_empty() or points.back().distance_to(point) >= 1.0:
				points.append(point)
	return points


func _serialize_military_front_lines() -> Array:
	var result: Array = []
	for raw_plan in military_front_lines.values():
		if raw_plan is not Dictionary:
			continue
		var plan: Dictionary = raw_plan
		var front_data: Array = []
		for point in _coerce_military_line_points(plan.get("front_points", [])):
			front_data.append(_vector_to_data(point))
		var offensive_data: Array = []
		for point in _coerce_military_line_points(plan.get("offensive_points", [])):
			offensive_data.append(_vector_to_data(point))
		result.append({
			"line_id": str(plan.get("line_id", "")),
			"faction_id": int(plan.get("faction_id", -1)),
			"name": str(plan.get("name", "Линия фронта")),
			"front_points": front_data,
			"offensive_points": offensive_data,
			"has_offensive": bool(plan.get("has_offensive", false)),
			"offensive_active": bool(plan.get("offensive_active", false)),
			"attacking_squad_ids": plan.get("attacking_squad_ids", []).duplicate(),
			"squad_ids": plan.get("squad_ids", []).duplicate(),
			"attach_all": bool(plan.get("attach_all", false)),
		})
	return result


func _restore_military_front_lines(raw_plans: Array, smooth_legacy_geometry := false):
	military_front_lines.clear()
	for raw_plan in raw_plans:
		if raw_plan is not Dictionary:
			continue
		var line_id := str(raw_plan.get("line_id", "")).strip_edges().left(96)
		var front_points := _prepare_military_line(raw_plan.get("front_points", []), MILITARY_LINE_SMOOTH_PASSES) \
			if smooth_legacy_geometry else _coerce_military_line_points(raw_plan.get("front_points", []))
		var offensive_points := _prepare_military_line(raw_plan.get("offensive_points", []), MILITARY_LINE_SMOOTH_PASSES) \
			if smooth_legacy_geometry else _coerce_military_line_points(raw_plan.get("offensive_points", []))
		if line_id.is_empty() or front_points.size() < 2:
			continue
		military_front_lines[line_id] = {
			"line_id": line_id,
			"faction_id": int(raw_plan.get("faction_id", -1)),
			"name": str(raw_plan.get("name", "Линия фронта")),
			"front_points": front_points,
			"offensive_points": offensive_points,
			"has_offensive": bool(raw_plan.get("has_offensive", false)),
			"offensive_active": bool(raw_plan.get("offensive_active", false)),
			"attacking_squad_ids": raw_plan.get("attacking_squad_ids", []).duplicate(),
			"squad_ids": raw_plan.get("squad_ids", []).duplicate(),
			"attach_all": bool(raw_plan.get("attach_all", false)),
		}


func get_network_military_front_lines(faction_ids: Array = []) -> Array:
	var faction_filter := _make_network_faction_filter(faction_ids)
	var result: Array = []
	for plan in _serialize_military_front_lines():
		if faction_filter.is_empty() or faction_filter.has(int(plan.get("faction_id", -1))):
			result.append(plan)
	return result


func apply_network_military_front_lines(raw_plans: Array, faction_ids: Array):
	var faction_filter := _make_network_faction_filter(faction_ids)
	var combined_plans := _serialize_military_front_lines()
	for index in range(combined_plans.size() - 1, -1, -1):
		if faction_filter.has(int(combined_plans[index].get("faction_id", -1))):
			combined_plans.remove_at(index)
	for raw_plan in raw_plans:
		if raw_plan is not Dictionary or not faction_filter.has(int(raw_plan.get("faction_id", -1))):
			continue
		combined_plans.append(raw_plan)
	_restore_military_front_lines(combined_plans)


func get_save_data() -> Dictionary:
	_ensure_persistent_building_ids()
	var data := {
		"buildings": [],
		"resources": [],
		"units": [],
		"session_slots": [],
		"military_front_lines": _serialize_military_front_lines(),
		"military_line_geometry_version": MILITARY_LINE_GEOMETRY_VERSION,
		"continuous_harvest": Unit.continuous_harvest_mode,
	}
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		data.session_slots = network_manager.get_session_slots()
	for building in _get_indexed_buildings():
		if building is Building and is_ancestor_of(building):
			data.buildings.append(_serialize_building(building))
	var lod_manager := get_node_or_null("SimulationLODManager")
	if is_instance_valid(lod_manager) and lod_manager.has_method("get_resource_save_data"):
		data.resources = lod_manager.get_resource_save_data()
	else:
		for resource in get_tree().get_nodes_in_group("resources"):
			if not is_instance_valid(resource) or not is_ancestor_of(resource) or resource.is_depleted():
				continue
			if resource.has_meta("managed_forestry_tree"):
				continue
			if resource.is_in_group("trees"):
				data.resources.append({"type": "tree", "position": _vector_to_data(resource.position), "variant": resource.tree_variant, "amount": resource.wood_amount})
			elif resource.is_in_group("rocks"):
				data.resources.append({"type": "rock", "position": _vector_to_data(resource.position), "variant": resource.rock_variant, "amount": resource.stone_amount})
	for unit in _get_indexed_units():
		if unit is not Unit or not is_ancestor_of(unit):
			continue
		var target_resource_position: Vector2 = unit.global_position
		if is_instance_valid(unit.target_tree):
			target_resource_position = unit.target_tree.global_position
		data.units.append({
			"position": _vector_to_data(unit.global_position),
			"name": unit.unit_name,
			"faction_id": unit.faction_id,
			"faction_name": unit.faction_name,
			"network_id": unit.network_id,
			"health": unit.health,
			"max_health": unit.max_health,
			"profession": unit.profession,
			"wood": unit.carried_wood,
			"stone": unit.carried_stone,
			"produced_items": unit.produced_items,
			"food_timer": unit.food_timer,
			"missed_meals": unit.missed_meals,
			"is_mobilized": unit.is_mobilized,
			"military_role": str(unit.military_role),
			"military_rank": unit.military_rank,
			"squad_id": unit.squad_id,
			"platoon_id": unit.platoon_id,
			"squad_commander_network_id": unit.squad_commander_network_id,
			"platoon_commander_network_id": unit.platoon_commander_network_id,
			"military_order": str(unit.military_order),
			"squad_formation_offset": _vector_to_data(unit.squad_formation_offset),
			"squad_independent_order": unit.squad_independent_order,
			"squad_line_direction": _vector_to_data(unit.squad_line_direction),
			"has_platoon_front_line": unit.has_platoon_front_line,
			"platoon_front_start": _vector_to_data(unit.platoon_front_start),
			"platoon_front_end": _vector_to_data(unit.platoon_front_end),
			"has_platoon_offensive_line": unit.has_platoon_offensive_line,
			"platoon_offensive_start": _vector_to_data(unit.platoon_offensive_start),
			"platoon_offensive_end": _vector_to_data(unit.platoon_offensive_end),
			"has_armor": unit.has_armor,
			"has_rifle": unit.has_rifle,
			"facing_direction": _vector_to_data(unit.facing_direction),
			"task": int(unit.task),
			"target_position": _vector_to_data(unit.target_position),
			"harvest_resource_type": str(unit.harvest_resource_type),
			"mining_job_resource_type": str(unit.mining_job_resource_type),
			"continuous_harvest_order": unit.continuous_harvest,
			"harvest_target_position": _vector_to_data(target_resource_position),
			"work_timer": unit.work_timer,
			"idle_check_timer": unit.idle_check_timer,
			"production_timer": unit.production_timer,
			"inside_building_network_id": unit.inside_building.network_id if is_instance_valid(unit.inside_building) else 0,
			"target_building_network_id": unit.target_building.network_id if is_instance_valid(unit.target_building) else 0,
			"target_warehouse_network_id": unit.target_warehouse.network_id if is_instance_valid(unit.target_warehouse) else 0,
			"build_job_kind": unit.build_job_kind,
		})
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		data["camera"] = {"position": _vector_to_data(camera.position), "zoom": _vector_to_data(camera.zoom)}
	return data


func _ensure_persistent_building_ids():
	var used_ids := {}
	var buildings_to_assign: Array[Building] = []
	for candidate in _get_indexed_buildings():
		if candidate is not Building or not is_ancestor_of(candidate):
			continue
		var building := candidate as Building
		if building.network_id > 0 and not used_ids.has(building.network_id):
			used_ids[building.network_id] = true
		else:
			buildings_to_assign.append(building)
	var next_id := 1
	for building in buildings_to_assign:
		while used_ids.has(next_id):
			next_id += 1
		building.network_id = next_id
		used_ids[next_id] = true
		next_id += 1


func _ensure_persistent_entity_ids():
	_ensure_persistent_building_ids()
	var used_unit_ids := {}
	for candidate in _get_indexed_units():
		if candidate is not Unit or not is_ancestor_of(candidate):
			continue
		var unit := candidate as Unit
		if unit.network_id > 0 and not used_unit_ids.has(unit.network_id):
			used_unit_ids[unit.network_id] = true
			continue
		var next_id := unit.faction_id * 100000 + 1
		while used_unit_ids.has(next_id):
			next_id += 1
		unit.network_id = next_id
		unit.name = "Unit_%d" % next_id
		used_unit_ids[next_id] = true


func _serialize_building(building: Building) -> Dictionary:
	var limits := {}
	for resource_type in Building.RESOURCE_TYPES:
		limits[str(resource_type)] = building.get_storage_limit(resource_type)
	var result := {
		"kind": building.building_kind,
		"faction_id": building.faction_id,
		"faction_name": building.faction_name,
		"network_id": building.network_id,
		"position": _vector_to_data(building.position),
		"rotation": building.rotation,
		"address": building.address,
		"under_construction": building.under_construction,
		"delivered_wood": building.delivered_wood,
		"delivered_stone": building.delivered_stone,
		"build_progress": building.build_progress,
		"stored": {
			"wood": building.stored_wood,
			"stone": building.stored_stone,
			"iron": building.get_stored_resource(&"iron"),
			"coal": building.get_stored_resource(&"coal"),
			"planks": building.get_stored_resource(&"planks"),
			"tools": building.get_stored_resource(&"tools"),
			"food": building.get_stored_resource(&"food"),
			"armor": building.get_stored_resource(&"armor"),
			"rifles": building.get_stored_resource(&"rifles"),
		},
		"limits": limits,
		"recipe": str(building.selected_recipe),
		"desired_workers": building.get_worker_target() if building.is_factory() else 0,
		"stored_electricity": building.stored_electricity,
	}
	if building is RoadSegment:
		result["street_name"] = building.street_name
	elif building is GovernmentBuilding:
		result["migration_target"] = building.migration_target
		result["migration_timer"] = building.migration_timer
		result["mobilization_target"] = building.mobilization_target
		result["mobilization_timer"] = building.mobilization_timer
	if building.has_method("get_forestry_save_data"):
		result["forestry_plots"] = building.get_forestry_save_data()
	return result


func get_network_unit_states(faction_ids: Array = []) -> Array:
	var result: Array = []
	var faction_filter := _make_network_faction_filter(faction_ids)
	for candidate in _get_indexed_units():
		if candidate is not Unit or not is_ancestor_of(candidate):
			continue
		var unit := candidate as Unit
		if not faction_filter.is_empty() and not faction_filter.has(unit.faction_id):
			continue
		var target_resource_position := unit.global_position
		var target_resource_record_id := 0
		if is_instance_valid(unit.target_tree):
			target_resource_position = unit.target_tree.global_position
			target_resource_record_id = int(unit.target_tree.get("lod_record_id"))
		result.append({
			"network_id": unit.network_id,
			"faction_id": unit.faction_id,
			"faction_name": unit.faction_name,
			"controller_peer_id": unit.controller_peer_id,
			"ai_controlled": unit.ai_controlled,
			"position": _vector_to_data(unit.global_position),
			"velocity": _vector_to_data(unit.velocity),
			"name": unit.unit_name,
			"health": unit.health,
			"max_health": unit.max_health,
			"profession": unit.profession,
			"wood": unit.carried_wood,
			"stone": unit.carried_stone,
			"produced_items": unit.produced_items,
			"food_timer": unit.food_timer,
			"missed_meals": unit.missed_meals,
			"task": int(unit.task),
			"target_position": _vector_to_data(unit.target_position),
			"harvest_resource_type": str(unit.harvest_resource_type),
			"mining_job_resource_type": str(unit.mining_job_resource_type),
			"continuous_harvest_order": unit.continuous_harvest,
			"harvest_target_record_id": target_resource_record_id,
			"harvest_target_position": _vector_to_data(target_resource_position),
			"work_timer": unit.work_timer,
			"idle_check_timer": unit.idle_check_timer,
			"production_timer": unit.production_timer,
			"inside_building_network_id": unit.inside_building.network_id if is_instance_valid(unit.inside_building) else 0,
			"target_building_network_id": unit.target_building.network_id if is_instance_valid(unit.target_building) else 0,
			"target_warehouse_network_id": unit.target_warehouse.network_id if is_instance_valid(unit.target_warehouse) else 0,
			"build_job_kind": unit.build_job_kind,
			"is_mobilized": unit.is_mobilized,
			"military_role": str(unit.military_role),
			"military_rank": unit.military_rank,
			"squad_id": unit.squad_id,
			"platoon_id": unit.platoon_id,
			"squad_commander_network_id": unit.squad_commander_network_id,
			"platoon_commander_network_id": unit.platoon_commander_network_id,
			"military_order": str(unit.military_order),
			"squad_formation_offset": _vector_to_data(unit.squad_formation_offset),
			"squad_independent_order": unit.squad_independent_order,
			"squad_line_direction": _vector_to_data(unit.squad_line_direction),
			"has_platoon_front_line": unit.has_platoon_front_line,
			"platoon_front_start": _vector_to_data(unit.platoon_front_start),
			"platoon_front_end": _vector_to_data(unit.platoon_front_end),
			"has_platoon_offensive_line": unit.has_platoon_offensive_line,
			"platoon_offensive_start": _vector_to_data(unit.platoon_offensive_start),
			"platoon_offensive_end": _vector_to_data(unit.platoon_offensive_end),
			"facing_direction": _vector_to_data(unit.facing_direction),
			"has_armor": unit.has_armor,
			"has_rifle": unit.has_rifle,
		})
	return result


func get_network_building_states(faction_ids: Array = []) -> Array:
	var result: Array = []
	var faction_filter := _make_network_faction_filter(faction_ids)
	for candidate in _get_indexed_buildings():
		if candidate is Building and is_ancestor_of(candidate) and not candidate.placement_preview and (faction_filter.is_empty() or faction_filter.has(candidate.faction_id)):
			result.append(_serialize_building(candidate))
	return result


func _make_network_faction_filter(faction_ids: Array) -> Dictionary:
	var result := {}
	for raw_faction_id in faction_ids:
		var faction_id := int(raw_faction_id)
		if faction_id >= 0:
			result[faction_id] = true
	return result


func is_network_position_valid(position: Vector2) -> bool:
	return position.x >= 0.0 and position.y >= 0.0 and position.x <= MAP_WIDTH * TILE_SIZE and position.y <= MAP_HEIGHT * TILE_SIZE


func apply_network_unit_states(states: Array, authoritative_faction_ids: Array = []):
	var authoritative_factions := _make_network_faction_filter(authoritative_faction_ids)
	if authoritative_factions.is_empty():
		for raw_state in states:
			if raw_state is Dictionary:
				authoritative_factions[int(raw_state.get("faction_id", -1))] = true
	if authoritative_factions.is_empty():
		return
	var authoritative_keys := {}
	for building in _get_indexed_buildings():
		if building is Building and is_ancestor_of(building):
			for occupant in building.occupants.duplicate():
				if not is_instance_valid(occupant) or authoritative_factions.has(occupant.faction_id):
					building.occupants.erase(occupant)
	for raw_state in states:
		if raw_state is not Dictionary:
			continue
		var state: Dictionary = raw_state
		var network_id := int(state.get("network_id", 0))
		var faction_id := int(state.get("faction_id", 0))
		if network_id <= 0 or not authoritative_factions.has(faction_id):
			continue
		var key := "%d:%d" % [faction_id, network_id]
		authoritative_keys[key] = true
		var unit := _find_unit_by_network_id(network_id, faction_id)
		if not is_instance_valid(unit):
			unit = _restore_unit(state)
		if not is_instance_valid(unit):
			continue
		_apply_network_unit_state(unit, state)
	for candidate in _get_indexed_units():
		if candidate is not Unit or not is_ancestor_of(candidate) or not authoritative_factions.has(candidate.faction_id):
			continue
		var key := "%d:%d" % [candidate.faction_id, candidate.network_id]
		if not authoritative_keys.has(key):
			candidate.queue_free()


func apply_network_unit_state_deltas(states: Array, authoritative_faction_ids: Array = []):
	var authoritative_factions := _make_network_faction_filter(authoritative_faction_ids)
	for raw_state in states:
		if raw_state is not Dictionary:
			continue
		var state: Dictionary = raw_state
		var network_id := int(state.get("network_id", 0))
		var faction_id := int(state.get("faction_id", -1))
		if network_id <= 0 or not authoritative_factions.has(faction_id):
			continue
		var unit := _find_unit_by_network_id(network_id, faction_id)
		if bool(state.get("_deleted", false)):
			if is_instance_valid(unit):
				unit.queue_free()
			continue
		if not is_instance_valid(unit):
			unit = _restore_unit(state)
		if is_instance_valid(unit):
			_apply_network_unit_state(unit, state)


func _apply_network_unit_state(unit: Unit, state: Dictionary):
	var previous_target_building := unit.target_building
	unit.configure_faction(
		int(state.get("faction_id", unit.faction_id)),
		int(state.get("controller_peer_id", unit.controller_peer_id)),
		bool(state.get("ai_controlled", unit.ai_controlled)),
		str(state.get("faction_name", unit.faction_name))
	)
	unit.unit_name = str(state.get("name", unit.unit_name))
	unit.max_health = int(state.get("max_health", unit.max_health))
	unit.health = clampi(int(state.get("health", unit.health)), 0, unit.max_health)
	unit.profession = str(state.get("profession", unit.profession))
	unit.carried_wood = int(state.get("wood", unit.carried_wood))
	unit.carried_stone = int(state.get("stone", unit.carried_stone))
	unit.produced_items = int(state.get("produced_items", unit.produced_items))
	unit.food_timer = float(state.get("food_timer", unit.food_timer))
	unit.missed_meals = int(state.get("missed_meals", unit.missed_meals))
	unit.task = clampi(int(state.get("task", Unit.Task.IDLE)), Unit.Task.IDLE, Unit.Task.REST)
	unit.target_position = _data_to_vector(state.get("target_position", [unit.global_position.x, unit.global_position.y]))
	unit.harvest_resource_type = StringName(state.get("harvest_resource_type", "wood"))
	unit.mining_job_resource_type = StringName(state.get("mining_job_resource_type", "wood"))
	unit.continuous_harvest = bool(state.get("continuous_harvest_order", false))
	unit.work_timer = float(state.get("work_timer", unit.work_timer))
	unit.idle_check_timer = float(state.get("idle_check_timer", unit.idle_check_timer))
	unit.production_timer = float(state.get("production_timer", unit.production_timer))
	unit.build_job_kind = str(state.get("build_job_kind", unit.build_job_kind))
	unit.is_mobilized = bool(state.get("is_mobilized", unit.is_mobilized))
	unit.military_role = StringName(state.get("military_role", unit.military_role))
	unit.simulation_importance = 2 if unit.military_role in [&"commander", &"platoon_commander"] else (1 if unit.is_mobilized else 0)
	unit.military_rank = str(state.get("military_rank", unit.military_rank))
	unit.squad_id = int(state.get("squad_id", unit.squad_id))
	unit.platoon_id = int(state.get("platoon_id", unit.platoon_id))
	unit.squad_commander_network_id = int(state.get("squad_commander_network_id", unit.squad_commander_network_id))
	unit.platoon_commander_network_id = int(state.get("platoon_commander_network_id", unit.platoon_commander_network_id))
	unit.military_order = StringName(state.get("military_order", unit.military_order))
	unit.squad_formation_offset = _data_to_vector(state.get("squad_formation_offset", [0, 0]))
	unit.squad_independent_order = bool(state.get("squad_independent_order", false))
	unit.squad_line_direction = _data_to_vector(state.get("squad_line_direction", [0, 0])).normalized()
	unit.has_platoon_front_line = bool(state.get("has_platoon_front_line", false))
	unit.platoon_front_start = _data_to_vector(state.get("platoon_front_start", [0, 0]))
	unit.platoon_front_end = _data_to_vector(state.get("platoon_front_end", [0, 0]))
	unit.has_platoon_offensive_line = bool(state.get("has_platoon_offensive_line", false))
	unit.platoon_offensive_start = _data_to_vector(state.get("platoon_offensive_start", [0, 0]))
	unit.platoon_offensive_end = _data_to_vector(state.get("platoon_offensive_end", [0, 0]))
	unit.has_armor = bool(state.get("has_armor", unit.has_armor))
	unit.has_rifle = bool(state.get("has_rifle", unit.has_rifle))
	unit.facing_direction = _data_to_vector(state.get("facing_direction", [0, 1]))
	unit.target_building = _find_building_by_network_id(int(state.get("target_building_network_id", 0)), unit.faction_id)
	if is_instance_valid(previous_target_building) and previous_target_building != unit.target_building:
		previous_target_building.release_entry_reservation(unit)
	unit.target_warehouse = _find_building_by_network_id(int(state.get("target_warehouse_network_id", 0)), unit.faction_id)
	if unit.task == Unit.Task.HARVEST:
		var resource_target := _resolve_network_resource_target(state, unit)
		if is_instance_valid(resource_target):
			if is_instance_valid(unit.target_tree) and unit.target_tree != resource_target:
				unit.target_tree.stop_harvest(unit)
			unit.target_tree = resource_target
		else:
			if is_instance_valid(unit.target_tree):
				unit.target_tree.stop_harvest(unit)
			unit.target_tree = null
	else:
		if is_instance_valid(unit.target_tree):
			unit.target_tree.stop_harvest(unit)
		unit.target_tree = null
	var previous_inside_building := unit.inside_building
	unit.inside_building = _find_building_by_network_id(int(state.get("inside_building_network_id", 0)), unit.faction_id)
	if is_instance_valid(previous_inside_building) and previous_inside_building != unit.inside_building:
		previous_inside_building.leave(unit)
	if is_instance_valid(unit.inside_building) and unit not in unit.inside_building.occupants:
		unit.inside_building.occupants.append(unit)
	unit.sync_entry_reservation()
	unit.apply_network_motion(
		_data_to_vector(state.get("position", [0, 0])),
		_data_to_vector(state.get("velocity", [0, 0]))
	)
	unit.refresh_military_visuals()
	unit._refresh_lod_presentation()


func _resolve_network_resource_target(state: Dictionary, unit: Unit) -> Node2D:
	var lod_manager := get_node_or_null("SimulationLODManager")
	if not is_instance_valid(lod_manager):
		return null
	var record_id := int(state.get("harvest_target_record_id", 0))
	if record_id > 0:
		var record: Dictionary = lod_manager._resource_records_by_id.get(record_id, {})
		if not record.is_empty() and int(record.get("amount", 0)) > 0:
			return lod_manager._get_or_materialize_resource(record)
	var resource_position := _data_to_vector(state.get("harvest_target_position", [unit.global_position.x, unit.global_position.y]))
	return lod_manager.find_resource_near_position(unit.harvest_resource_type, resource_position, 48.0)


func apply_network_building_states(states: Array, authoritative_faction_ids: Array = []):
	var authoritative_factions := _make_network_faction_filter(authoritative_faction_ids)
	if authoritative_factions.is_empty():
		for raw_state in states:
			if raw_state is Dictionary:
				authoritative_factions[int(raw_state.get("faction_id", -1))] = true
	if authoritative_factions.is_empty():
		return
	var authoritative_keys := {}
	for raw_state in states:
		if raw_state is not Dictionary:
			continue
		var state: Dictionary = raw_state
		var network_id := int(state.get("network_id", 0))
		var faction_id := int(state.get("faction_id", 0))
		if network_id <= 0 or not authoritative_factions.has(faction_id):
			continue
		var key := "%d:%d" % [faction_id, network_id]
		authoritative_keys[key] = true
		var building := _find_building_by_network_id(network_id, faction_id)
		if not is_instance_valid(building):
			building = _restore_building(state)
		if is_instance_valid(building):
			_apply_network_building_state(building, state)
	for candidate in _get_indexed_buildings():
		if candidate is not Building or not is_ancestor_of(candidate) or candidate.placement_preview or not authoritative_factions.has(candidate.faction_id):
			continue
		var key := "%d:%d" % [candidate.faction_id, candidate.network_id]
		if not authoritative_keys.has(key):
			candidate.queue_free()


func apply_network_building_state_deltas(states: Array, authoritative_faction_ids: Array = []):
	var authoritative_factions := _make_network_faction_filter(authoritative_faction_ids)
	for raw_state in states:
		if raw_state is not Dictionary:
			continue
		var state: Dictionary = raw_state
		var network_id := int(state.get("network_id", 0))
		var faction_id := int(state.get("faction_id", -1))
		if network_id <= 0 or not authoritative_factions.has(faction_id):
			continue
		var building := _find_building_by_network_id(network_id, faction_id)
		if bool(state.get("_deleted", false)):
			if is_instance_valid(building):
				building.queue_free()
			continue
		if not is_instance_valid(building):
			building = _restore_building(state)
		if is_instance_valid(building):
			_apply_network_building_state(building, state)


func _apply_network_building_state(building: Building, state: Dictionary):
	var new_position := _data_to_vector(state.get("position", [building.global_position.x, building.global_position.y]))
	var new_rotation := float(state.get("rotation", building.rotation))
	var new_under_construction := bool(state.get("under_construction", building.under_construction))
	var navigation_changed := building.global_position != new_position or not is_equal_approx(building.rotation, new_rotation) or building.under_construction != new_under_construction
	building.global_position = new_position
	building.rotation = new_rotation
	building.faction_name = str(state.get("faction_name", building.faction_name))
	building.address = str(state.get("address", building.address))
	if is_instance_valid(building.address_label):
		building.address_label.text = building.address
	if building is RoadSegment:
		building.set_street_name(str(state.get("street_name", building.street_name)))
	building.delivered_wood = int(state.get("delivered_wood", building.delivered_wood))
	building.delivered_stone = int(state.get("delivered_stone", building.delivered_stone))
	building.build_progress = float(state.get("build_progress", building.build_progress))
	var stored: Dictionary = state.get("stored", {})
	building.stored_wood = int(stored.get("wood", building.stored_wood))
	building.stored_stone = int(stored.get("stone", building.stored_stone))
	for resource_type in [&"iron", &"coal", &"planks", &"tools", &"food", &"armor", &"rifles"]:
		building.stored_products[resource_type] = int(stored.get(str(resource_type), building.stored_products.get(resource_type, 0)))
	building.stored_electricity = clampi(int(state.get("stored_electricity", building.stored_electricity)), 0, building.electricity_capacity)
	var limits: Dictionary = state.get("limits", {})
	if not limits.is_empty():
		for resource_type in Building.RESOURCE_TYPES:
			building.storage_limits[resource_type] = int(limits.get(str(resource_type), building.storage_limits.get(resource_type, 0)))
	building.set_recipe(StringName(state.get("recipe", building.selected_recipe)))
	if building.is_factory():
		building.set_worker_target(int(state.get("desired_workers", building.desired_workers)))
	if building is GovernmentBuilding:
		building.migration_target = int(state.get("migration_target", building.migration_target))
		building.migration_timer = float(state.get("migration_timer", building.migration_timer))
		building.mobilization_target = int(state.get("mobilization_target", building.mobilization_target))
		building.mobilization_timer = float(state.get("mobilization_timer", building.mobilization_timer))
	if building.has_method("apply_forestry_network_state"):
		building.apply_forestry_network_state(state.get("forestry_plots", []))
	building.under_construction = new_under_construction
	building.progress_bar.visible = building.under_construction
	building._update_visuals()
	if navigation_changed:
		building.notify_navigation_changed()


func _find_unit_by_network_id(network_id: int, faction_id: int) -> Unit:
	var index := get_node_or_null("WorldIndex")
	if is_instance_valid(index):
		return index.find_unit(network_id, faction_id) as Unit
	for candidate in _get_indexed_units(faction_id):
		if candidate is Unit and is_ancestor_of(candidate) and candidate.network_id == network_id and candidate.faction_id == faction_id:
			return candidate
	return null


func can_spawn_network_building(specification: Dictionary) -> bool:
	var kind := str(specification.get("kind", ""))
	var position: Variant = specification.get("position", Vector2.ZERO)
	var faction_id := int(specification.get("faction_id", -1))
	if position is not Vector2 or faction_id < 0:
		return false
	if kind == "government" and _faction_has_government(faction_id):
		return false
	var build_manager := get_node_or_null("BuildManager")
	if kind == "road":
		return is_instance_valid(build_manager) and not build_manager._road_segment_overlaps_existing(position, float(specification.get("rotation", 0.0)))
	var attached_to_road := false
	for candidate in _get_indexed_buildings("road", faction_id):
		if candidate is not RoadSegment or candidate.faction_id != faction_id or candidate.under_construction:
			continue
		var direction := Vector2.RIGHT.rotated(candidate.global_rotation)
		var along: float = clampf((position - candidate.global_position).dot(direction), -RoadSegment.SEGMENT_LENGTH * 0.5, RoadSegment.SEGMENT_LENGTH * 0.5)
		if position.distance_to(candidate.global_position + direction * along) <= 100.0:
			attached_to_road = true
			break
	if not attached_to_road:
		return false
	var scene := _get_building_scene(kind)
	if scene == null:
		return false
	var preview := scene.instantiate() as Building
	var collision := preview.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape == null:
		preview.free()
		return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision.shape
	query.transform = Transform2D(float(specification.get("rotation", 0.0)), position) * collision.transform
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.collision_mask = 1
	var blocked := false
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 32):
		if hit.collider is Building:
			blocked = true
			break
	preview.free()
	return not blocked


func spawn_network_buildings(specifications: Array, builder_ids: Array):
	var spawned: Array[Building] = []
	var faction_id := -1
	for raw_spec in specifications:
		if raw_spec is not Dictionary:
			continue
		var spec: Dictionary = raw_spec
		var network_id := int(spec.get("network_id", 0))
		faction_id = int(spec.get("faction_id", faction_id))
		if network_id <= 0 or is_instance_valid(_find_building_by_network_id(network_id, faction_id)):
			continue
		if str(spec.get("kind", "")) == "government" and _faction_has_government(faction_id):
			continue
		var data := spec.duplicate(true)
		var position: Vector2 = spec.get("position", Vector2.ZERO)
		data["position"] = _vector_to_data(position)
		data["under_construction"] = true
		data["delivered_wood"] = 0
		data["delivered_stone"] = 0
		data["build_progress"] = 0.0
		var building := _restore_building(data)
		if not is_instance_valid(building):
			continue
		building.begin_construction()
		_clear_resources_around(building.global_position, _get_building_footprint(building).size.length() * 0.55)
		spawned.append(building)
	if spawned.is_empty() or faction_id < 0:
		return
	var builders: Array[Unit] = []
	for raw_id in builder_ids:
		var builder := _find_unit_by_network_id(int(raw_id), faction_id)
		if is_instance_valid(builder):
			builders.append(builder)
	if spawned.size() == 1 and spawned[0] is not RoadSegment:
		for builder in builders:
			builder.command_build(spawned[0])
	else:
		for builder in builders:
			builder.command_build_line(spawned)


func _get_building_scene(kind: String) -> PackedScene:
	match kind:
		"warehouse": return WAREHOUSE_SCENE
		"factory": return FACTORY_SCENE
		"food_factory": return FOOD_FACTORY_SCENE
		"mine": return MINE_SCENE
		"power_plant": return POWER_PLANT_SCENE
		"barracks": return BARRACKS_SCENE
		"military_factory": return MILITARY_FACTORY_SCENE
		"government": return GOVERNMENT_SCENE
		"lumberjack_cabin": return LUMBERJACK_CABIN_SCENE
		"road": return ROAD_SCENE
		"residence": return RESIDENCE_SCENE
		_: return null


func apply_save_data(data: Dictionary):
	Unit.clear_selection()
	Building.selected_building = null
	var lod_manager := get_node_or_null("SimulationLODManager")
	if is_instance_valid(lod_manager) and lod_manager.has_method("clear_resource_data"):
		lod_manager.clear_resource_data()
	for unit in _get_indexed_units():
		if is_instance_valid(unit) and is_ancestor_of(unit):
			unit.free()
	for container_name in ["trees", "rocks", "roads", "buildings"]:
		var container := get_node(container_name)
		for child in container.get_children():
			child.free()

	for resource_data in data.get("resources", []):
		_restore_resource(resource_data)
	for building_data in data.get("buildings", []):
		_restore_building(building_data)
	for unit_data in data.get("units", []):
		_restore_unit(unit_data)
	var smooth_legacy_fronts := int(data.get("military_line_geometry_version", 0)) < MILITARY_LINE_GEOMETRY_VERSION
	_restore_military_front_lines(data.get("military_front_lines", []), smooth_legacy_fronts)
	# Migrate older armies where the first squad commander also acted as the
	# platoon commander. New platoons always receive a separate rear commander.
	for building in _get_indexed_buildings("government"):
		if building is GovernmentBuilding and building.is_completed():
			building.organize_army()
	Unit.continuous_harvest_mode = bool(data.get("continuous_harvest", false))
	var camera_data: Dictionary = data.get("camera", {})
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera != null and not camera_data.is_empty():
		camera.position = _data_to_vector(camera_data.get("position", [576, 321]))
		camera.zoom = _data_to_vector(camera_data.get("zoom", [1, 1]))
	if is_instance_valid(lod_manager) and lod_manager.has_method("rebuild_spatial_index"):
		lod_manager.call_deferred("rebuild_spatial_index")


func _restore_resource(data: Dictionary):
	var resource_kind := str(data.get("type", ""))
	var amount := int(data.get("amount", 20 if resource_kind == "tree" else 30))
	var position := _data_to_vector(data.get("position", [0, 0]))
	var variant := int(data.get("variant", 0))
	var lod_manager := get_node_or_null("SimulationLODManager")
	if is_instance_valid(lod_manager) and lod_manager.has_method("register_resource_data"):
		lod_manager.register_resource_data(resource_kind, position, variant, amount)
		return
	var resource: Node2D
	if resource_kind == "tree":
		resource = TREE_SCENE.instantiate()
		resource.tree_variant = variant
		resource.wood_amount = amount
		resource.position = position
		$trees.add_child(resource)
	elif resource_kind == "rock":
		resource = ROCK_SCENE.instantiate()
		resource.rock_variant = variant
		resource.stone_amount = amount
		resource.position = position
		$rocks.add_child(resource)


func _restore_building(data: Dictionary) -> Building:
	var kind := str(data.get("kind", "residence"))
	var scene: PackedScene
	match kind:
		"warehouse": scene = WAREHOUSE_SCENE
		"factory": scene = FACTORY_SCENE
		"food_factory": scene = FOOD_FACTORY_SCENE
		"mine": scene = MINE_SCENE
		"power_plant": scene = POWER_PLANT_SCENE
		"barracks": scene = BARRACKS_SCENE
		"military_factory": scene = MILITARY_FACTORY_SCENE
		"government": scene = GOVERNMENT_SCENE
		"lumberjack_cabin": scene = LUMBERJACK_CABIN_SCENE
		"road": scene = ROAD_SCENE
		_: scene = RESIDENCE_SCENE
	var building := scene.instantiate() as Building
	building.faction_id = int(data.get("faction_id", 0))
	building.network_id = int(data.get("network_id", 0))
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		var slot: Dictionary = network_manager.get_faction_slot(building.faction_id)
		if not slot.is_empty():
			building.faction_name = str(slot.get("nickname", building.faction_name))
	building.position = _data_to_vector(data.get("position", [0, 0]))
	var target_container: Node = $roads if kind == "road" else $buildings
	target_container.add_child(building)
	if building is RoadSegment:
		building.setup(str(data.get("street_name", "Улица")), float(data.get("rotation", 0.0)))
	else:
		building.rotation = float(data.get("rotation", 0.0))
	building.address = str(data.get("address", ""))
	building.address_label.text = building.address
	building.delivered_wood = int(data.get("delivered_wood", 0))
	building.delivered_stone = int(data.get("delivered_stone", 0))
	building.build_progress = float(data.get("build_progress", 0.0))
	var stored: Dictionary = data.get("stored", {})
	building.stored_wood = int(stored.get("wood", 0))
	building.stored_stone = int(stored.get("stone", 0))
	building.stored_products[&"iron"] = int(stored.get("iron", 0))
	building.stored_products[&"coal"] = int(stored.get("coal", 0))
	building.stored_products[&"planks"] = int(stored.get("planks", 0))
	building.stored_products[&"tools"] = int(stored.get("tools", 0))
	building.stored_products[&"food"] = int(stored.get("food", 0))
	building.stored_products[&"armor"] = int(stored.get("armor", 0))
	building.stored_products[&"rifles"] = int(stored.get("rifles", 0))
	building.stored_electricity = clampi(int(data.get("stored_electricity", 0)), 0, building.electricity_capacity)
	var limits: Dictionary = data.get("limits", {})
	_restore_storage_limits(building, limits)
	building.set_recipe(StringName(data.get("recipe", "planks")))
	if building.is_factory():
		building.set_worker_target(int(data.get("desired_workers", building.max_workers)))
	if building is GovernmentBuilding:
		building.migration_target = int(data.get("migration_target", 0))
		building.migration_timer = float(data.get("migration_timer", building.migration_interval))
		building.mobilization_target = int(data.get("mobilization_target", 0))
		building.mobilization_timer = float(data.get("mobilization_timer", building.mobilization_interval))
	if bool(data.get("under_construction", false)):
		building.under_construction = true
		building.progress_bar.visible = true
		building._update_visuals()
	else:
		building.under_construction = false
		building.progress_bar.visible = false
		building.building_sprite.modulate.a = 1.0
	if building.has_method("restore_forestry_save_data"):
		building.restore_forestry_save_data(data.get("forestry_plots", []))
	return building


func _restore_unit(data: Dictionary) -> Unit:
	var unit := UNIT_SCENE.instantiate() as Unit
	var faction_id := int(data.get("faction_id", 0))
	var faction_name := str(data.get("faction_name", "Игрок" if faction_id == 0 else "ИИ %d" % faction_id))
	var controller_peer_id := 1 if faction_id == 0 else 0
	var ai_controlled := faction_id != 0
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		var slot: Dictionary = network_manager.get_faction_slot(faction_id)
		if not slot.is_empty():
			controller_peer_id = int(slot.get("controller_peer_id", controller_peer_id))
			ai_controlled = bool(slot.get("is_ai", ai_controlled))
			faction_name = str(slot.get("nickname", faction_name))
	unit.configure_faction(faction_id, controller_peer_id, ai_controlled, faction_name)
	unit.network_id = int(data.get("network_id", 0))
	unit.unit_name = str(data.get("name", ""))
	unit.max_health = int(data.get("max_health", 100))
	unit.health = int(data.get("health", unit.max_health))
	unit.profession = str(data.get("profession", "Безработный"))
	unit.carried_wood = int(data.get("wood", 0))
	unit.carried_stone = int(data.get("stone", 0))
	unit.produced_items = int(data.get("produced_items", 0))
	unit.food_timer = float(data.get("food_timer", Unit.FOOD_CONSUMPTION_INTERVAL))
	unit.missed_meals = int(data.get("missed_meals", 0))
	unit.is_mobilized = bool(data.get("is_mobilized", false))
	unit.military_role = StringName(data.get("military_role", "rifleman"))
	unit.military_rank = str(data.get("military_rank", "Солдат" if unit.is_mobilized else "Гражданский"))
	unit.simulation_importance = 2 if unit.military_role in [&"commander", &"platoon_commander"] else (1 if unit.is_mobilized else 0)
	unit.squad_id = int(data.get("squad_id", 0))
	unit.platoon_id = int(data.get("platoon_id", 0))
	unit.squad_commander_network_id = int(data.get("squad_commander_network_id", 0))
	unit.platoon_commander_network_id = int(data.get("platoon_commander_network_id", 0))
	unit.military_order = StringName(data.get("military_order", "hold"))
	unit.squad_formation_offset = _data_to_vector(data.get("squad_formation_offset", [0, 0]))
	unit.squad_independent_order = bool(data.get("squad_independent_order", false))
	unit.squad_line_direction = _data_to_vector(data.get("squad_line_direction", [0, 0])).normalized()
	unit.has_platoon_front_line = bool(data.get("has_platoon_front_line", false))
	unit.platoon_front_start = _data_to_vector(data.get("platoon_front_start", [0, 0]))
	unit.platoon_front_end = _data_to_vector(data.get("platoon_front_end", [0, 0]))
	unit.has_platoon_offensive_line = bool(data.get("has_platoon_offensive_line", false))
	unit.platoon_offensive_start = _data_to_vector(data.get("platoon_offensive_start", [0, 0]))
	unit.platoon_offensive_end = _data_to_vector(data.get("platoon_offensive_end", [0, 0]))
	unit.has_armor = bool(data.get("has_armor", false))
	unit.has_rifle = bool(data.get("has_rifle", false))
	unit.facing_direction = _data_to_vector(data.get("facing_direction", [0, 1])).normalized()
	if unit.facing_direction.is_zero_approx():
		unit.facing_direction = Vector2.DOWN
	unit.position = _data_to_vector(data.get("position", [300, 300]))
	add_child(unit)
	unit.idle_check_timer = maxf(float(data.get("idle_check_timer", 1.0)), 0.0)
	var inside_building := _find_building_by_network_id(int(data.get("inside_building_network_id", 0)), faction_id)
	if is_instance_valid(inside_building) and unit.restore_inside_building(inside_building, float(data.get("production_timer", 0.0))):
		return unit

	var saved_task := clampi(int(data.get("task", Unit.Task.IDLE)), Unit.Task.IDLE, Unit.Task.REST)
	var target_building := _find_building_by_network_id(int(data.get("target_building_network_id", 0)), faction_id)
	var target_warehouse := _find_building_by_network_id(int(data.get("target_warehouse_network_id", 0)), faction_id)
	if saved_task in [Unit.Task.HARVEST, Unit.Task.DELIVER_TO_WAREHOUSE] or bool(data.get("continuous_harvest_order", false)):
		unit.restore_harvest_order(
			StringName(data.get("mining_job_resource_type", data.get("harvest_resource_type", "wood"))),
			bool(data.get("continuous_harvest_order", false)),
			_data_to_vector(data.get("harvest_target_position", data.get("position", [300, 300]))),
			target_warehouse,
			saved_task,
			float(data.get("work_timer", unit.harvest_interval))
		)
	elif saved_task == Unit.Task.MOVE:
		unit.command_move(
			_data_to_vector(data.get("target_position", data.get("position", [300, 300]))),
			unit.squad_independent_order,
			unit.squad_line_direction
		)
		if unit.is_mobilized:
			unit.military_order = StringName(data.get("military_order", "move"))
	elif saved_task == Unit.Task.ENTER_BUILDING and is_instance_valid(target_building):
		unit.command_enter_building(target_building)
	elif saved_task == Unit.Task.BUILD and is_instance_valid(target_building):
		unit.command_build(target_building)
	else:
		unit.task = Unit.Task.IDLE
	return unit


func _find_building_by_network_id(network_id: int, faction_id: int) -> Building:
	if network_id <= 0:
		return null
	var index := get_node_or_null("WorldIndex")
	if is_instance_valid(index):
		return index.find_building(network_id, faction_id) as Building
	for building in _get_indexed_buildings("", faction_id):
		if building is Building and is_ancestor_of(building) and building.network_id == network_id and building.faction_id == faction_id:
			return building
	return null


func _restore_storage_limits(building: Building, limits: Dictionary):
	if not building.is_warehouse() or limits.is_empty():
		return
	for resource_type in Building.RESOURCE_TYPES:
		building.storage_limits[resource_type] = int(limits.get(str(resource_type), 0))
	# Новые ресурсы получают квоты и в старых сохранениях. Место выделяется за
	# счёт незанятой части прежних квот, уже сохранённые ресурсы не удаляются.
	if not limits.has("food"):
		building.storage_limits[&"food"] = 40
	if not limits.has("coal"):
		building.storage_limits[&"coal"] = 40
	if not limits.has("iron"):
		building.storage_limits[&"iron"] = 40
	if not limits.has("armor"):
		building.storage_limits[&"armor"] = 20
	if not limits.has("rifles"):
		building.storage_limits[&"rifles"] = 20
	var overflow := maxi(building.get_total_storage_limits() - building.storage_capacity, 0)
	for resource_type in [&"stone", &"wood", &"planks", &"tools", &"food", &"coal", &"iron", &"armor", &"rifles"]:
		if overflow <= 0:
			break
		var current_limit := building.get_storage_limit(resource_type)
		var stored_amount := building.get_stored_resource(resource_type)
		var reduction := mini(maxi(current_limit - stored_amount, 0), overflow)
		building.storage_limits[resource_type] = current_limit - reduction
		overflow -= reduction


func spawn_session_units(raw_slots: Array):
	var slot_count := mini(raw_slots.size(), 4)
	var ai_slots: Array[Dictionary] = []
	for slot_index in range(slot_count):
		var raw_slot = raw_slots[slot_index]
		if raw_slot is not Dictionary:
			continue
		var faction_id := clampi(int(raw_slot.get("faction_id", slot_index)), 0, 3)
		if bool(raw_slot.get("is_ai", true)):
			ai_slots.append(raw_slot)
		var spawn_position := get_faction_spawn_position(faction_id)
		_clear_spawn_area(spawn_position)
		var inward_x := 1.0 if faction_id in [0, 2] else -1.0
		var inward_y := 1.0 if faction_id in [0, 1] else -1.0
		for unit_index in range(starting_unit_count):
			var unit := UNIT_SCENE.instantiate() as Unit
			var column := unit_index % 3
			var row := unit_index / 3
			unit.position = spawn_position + Vector2(column * unit_spacing * inward_x, row * unit_spacing * inward_y)
			unit.network_id = faction_id * 1000 + unit_index + 1
			unit.name = "Unit_%d" % unit.network_id
			unit.configure_faction(
				faction_id,
				int(raw_slot.get("controller_peer_id", 0)),
				bool(raw_slot.get("is_ai", true)),
				str(raw_slot.get("nickname", "ИИ %d" % (faction_id + 1)))
			)
			if unit.ai_controlled:
				# Фоновая фракция должна успеть развернуть пищевую цепочку до
				# первого приёма пищи даже при редких стратегических тиках.
				unit.food_timer = Unit.FOOD_CONSUMPTION_INTERVAL * 3.0
			add_child(unit)
	for ai_slot in ai_slots:
		_ensure_ai_starting_plan(int(ai_slot.get("faction_id", 0)), str(ai_slot.get("nickname", "ИИ")))
	_position_camera_for_local_faction()


func _spawn_missing_loaded_factions(raw_slots: Array):
	var missing_slots: Array = []
	for raw_slot in raw_slots:
		if raw_slot is not Dictionary:
			continue
		var faction_id := int(raw_slot.get("faction_id", -1))
		var has_state := false
		for unit in _get_indexed_units(faction_id):
			if unit is Unit and is_ancestor_of(unit) and unit.faction_id == faction_id:
				has_state = true
				break
		if not has_state:
			for building in _get_indexed_buildings("", faction_id):
				if building is Building and is_ancestor_of(building) and building.faction_id == faction_id:
					has_state = true
					break
		if not has_state:
			missing_slots.append(raw_slot)
	if not missing_slots.is_empty():
		spawn_session_units(missing_slots)
	else:
		_position_camera_for_local_faction()


func get_faction_spawn_position(faction_id: int) -> Vector2:
	var maximum := Vector2(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE) - Vector2.ONE * SPAWN_MARGIN
	match faction_id:
		1: return Vector2(maximum.x, SPAWN_MARGIN)
		2: return Vector2(SPAWN_MARGIN, maximum.y)
		3: return maximum
		_: return Vector2.ONE * SPAWN_MARGIN


func set_faction_controller(faction_id: int, controller_peer_id: int, ai_controlled: bool, faction_name: String):
	for unit in _get_indexed_units(faction_id):
		if unit is Unit and unit.faction_id == faction_id:
			unit.configure_faction(faction_id, controller_peer_id, ai_controlled, faction_name)
	for building in _get_indexed_buildings("", faction_id):
		if building is Building and building.faction_id == faction_id:
			building.faction_name = faction_name
	var selected_units := Unit.get_selected_units()
	for unit in selected_units:
		if unit.faction_id == faction_id and not unit.can_be_controlled_locally():
			unit.deselect()
	if ai_controlled:
		_ensure_ai_starting_plan(faction_id, faction_name)


func _run_ai_strategy():
	var ai_factions := {}
	for candidate in _get_indexed_units():
		if candidate is Unit and is_ancestor_of(candidate) and candidate.ai_controlled:
			ai_factions[candidate.faction_id] = candidate.faction_name
	for raw_faction_id in ai_factions:
		var faction_id := int(raw_faction_id)
		var faction_name := str(ai_factions[raw_faction_id])
		_ensure_ai_starting_plan(faction_id, faction_name)
		_configure_ai_economy(faction_id)
		_provide_ai_emergency_food_if_needed(faction_id)
		_configure_ai_population_and_army(faction_id)
		if _ai_can_expand(faction_id):
			_plan_ai_expansion(faction_id, faction_name)
		_issue_ai_attack_orders(faction_id)


func _configure_ai_economy(faction_id: int):
	var mine_index := 0
	var factory_index := 0
	var population := _get_indexed_units(faction_id).size()
	var construction_active := _get_ai_construction_count(faction_id) > 0
	var coal_amount := _get_ai_stored_resource(faction_id, &"coal")
	for candidate in _get_indexed_buildings("", faction_id):
		if candidate is not Building or not is_ancestor_of(candidate) or candidate.faction_id != faction_id or not candidate.is_factory():
			continue
		var building := candidate as Building
		if building.is_food_factory():
			building.set_worker_target(clampi(ceili(float(population) / 3.0), 1, building.max_workers))
			building.set_recipe(&"food")
		elif building.is_lumberjack_cabin():
			building.set_worker_target(clampi(ceili(float(population) / 8.0), 1, building.max_workers))
			building.set_recipe(&"forestry")
		elif building.is_power_plant():
			building.set_worker_target(mini(1, building.max_workers))
			building.set_recipe(&"electricity")
		elif building.is_mine():
			building.set_worker_target(mini(1, building.max_workers))
			var mine_recipes: Array[StringName] = [&"mine_iron", &"mine_coal", &"mine_stone"]
			building.set_recipe(&"mine_coal" if coal_amount < 16 else mine_recipes[(ai_strategy_cycle + mine_index) % mine_recipes.size()])
			mine_index += 1
		elif building.is_military_factory():
			building.set_worker_target(0 if construction_active else mini(1, building.max_workers))
			building.set_recipe(_get_ai_needed_equipment_recipe(faction_id))
		else:
			building.set_worker_target(0 if construction_active else mini(1, building.max_workers))
			building.set_recipe(&"tools" if (ai_strategy_cycle + factory_index) % 2 == 0 else &"planks")
			factory_index += 1


func _get_ai_stored_resource(faction_id: int, resource_type: StringName) -> int:
	var total := 0
	for candidate in _get_indexed_buildings("warehouse", faction_id):
		if candidate is Building and is_ancestor_of(candidate) and candidate.is_completed():
			total += candidate.get_stored_resource(resource_type)
	return total


func _ai_can_expand(faction_id: int) -> bool:
	if _get_ai_construction_count(faction_id) > AI_MAX_CONSTRUCTION_BACKLOG:
		return false
	var units := _get_indexed_units(faction_id)
	var population := units.size()
	if population <= 0 or _get_ai_stored_resource(faction_id, &"food") < population * 3:
		return false
	for unit in units:
		if unit is Unit and unit.missed_meals > 0:
			return false
	for essential_kind in ["power_plant", "food_factory", "mine"]:
		var essential_ready := false
		for building in _get_indexed_buildings(essential_kind, faction_id):
			if building is Building and building.is_completed():
				essential_ready = true
				break
		if not essential_ready:
			return false
	return true


func _provide_ai_emergency_food_if_needed(faction_id: int):
	# Одноразовая помощь спасает уже начатые сохранения, в которых старая LOD-
	# логика успела довести всю фракцию до голода. Дальше ИИ обязан кормить
	# себя самостоятельно через шахту, электростанцию и пищевой завод.
	if ai_emergency_food_given.has(faction_id) or _get_ai_stored_resource(faction_id, &"food") > 0:
		return
	var population := 0
	var worst_missed_meals := 0
	for candidate in _get_indexed_units(faction_id):
		if candidate is Unit and is_ancestor_of(candidate):
			population += 1
			worst_missed_meals = maxi(worst_missed_meals, candidate.missed_meals)
	if population <= 0 or worst_missed_meals < Unit.AI_STARVATION_GRACE_MEALS:
		return
	for candidate in _get_indexed_buildings("warehouse", faction_id):
		if candidate is Building and is_ancestor_of(candidate) and candidate.is_completed():
			var delivered: int = candidate.store_resource(&"food", maxi(population * 2, 10))
			if delivered > 0:
				ai_emergency_food_given[faction_id] = true
				return


func _get_ai_needed_equipment_recipe(faction_id: int) -> StringName:
	var armor := 0
	var rifles := 0
	for candidate in _get_indexed_buildings("warehouse", faction_id):
		if candidate is Building and is_ancestor_of(candidate) and candidate.faction_id == faction_id and candidate.is_warehouse() and candidate.is_completed():
			armor += candidate.get_stored_resource(&"armor")
			rifles += candidate.get_stored_resource(&"rifles")
	for candidate in _get_indexed_units(faction_id):
		if candidate is Unit and is_ancestor_of(candidate) and candidate.faction_id == faction_id:
			armor += 1 if candidate.has_armor else 0
			rifles += 1 if candidate.has_rifle else 0
	return &"armor" if armor <= rifles else &"rifles"


func _configure_ai_population_and_army(faction_id: int):
	var government := _find_ai_government(faction_id)
	if not is_instance_valid(government) or not government.is_completed():
		return
	var population := government.get_population_count()
	var housing_capacity := government.get_housing_capacity()
	# ИИ постоянно заполняет всё построенное жильё. Новый район создаётся
	# планировщиком, когда текущие стройки закончены.
	var food_reserve := _get_ai_stored_resource(faction_id, &"food")
	var economy_is_safe := food_reserve >= maxi(population * 3, 12)
	government.set_migration_target(maxi(housing_capacity, population) if economy_is_safe else population)
	var army_capacity := government.get_army_capacity()
	var desired_army := mini(int(round(population * 0.55)), maxi(population - AI_MIN_CIVILIAN_WORKERS, 0))
	government.set_mobilization_target(mini(desired_army, army_capacity) if economy_is_safe else 0)


func _find_ai_government(faction_id: int) -> GovernmentBuilding:
	for candidate in _get_indexed_buildings("government", faction_id):
		if candidate is GovernmentBuilding and is_ancestor_of(candidate) and candidate.faction_id == faction_id:
			return candidate
	return null


func _faction_has_government(faction_id: int) -> bool:
	for candidate in _get_indexed_buildings("government", faction_id):
		if candidate is Building and is_instance_valid(candidate) and is_ancestor_of(candidate) and candidate.faction_id == faction_id and not candidate.placement_preview:
			return true
	return false


func _get_ai_construction_count(faction_id: int) -> int:
	var result := 0
	for candidate in _get_indexed_buildings("", faction_id):
		if candidate is Building and is_ancestor_of(candidate) and candidate.faction_id == faction_id and candidate.under_construction:
			result += 1
	return result


func _get_ai_building_count(faction_id: int, building_kind: String) -> int:
	var result := 0
	for candidate in _get_indexed_buildings(building_kind, faction_id):
		if candidate is Building and is_ancestor_of(candidate) and candidate.faction_id == faction_id and candidate.building_kind == building_kind:
			result += 1
	return result


func _issue_ai_attack_orders(faction_id: int):
	var soldiers: Array[Unit] = []
	var commanders: Array[Unit] = []
	var riflemen := 0
	for candidate in _get_indexed_units(faction_id):
		if candidate is not Unit or not is_ancestor_of(candidate) or candidate.faction_id != faction_id or not candidate.is_mobilized:
			continue
		soldiers.append(candidate)
		if candidate.has_rifle:
			riflemen += 1
		if candidate.is_squad_commander():
			commanders.append(candidate)
	if soldiers.size() < AI_ATTACK_MIN_SOLDIERS or riflemen * 2 < soldiers.size() or commanders.is_empty():
		return
	var target := _find_nearest_enemy_target(faction_id, commanders[0].global_position)
	if not is_instance_valid(target):
		return
	for commander_index in range(commanders.size()):
		var flank := Vector2.from_angle(TAU * float(commander_index) / float(maxi(commanders.size(), 1))) * 48.0
		var destination := target.global_position + flank
		if commanders[commander_index].military_order == &"attack" and commanders[commander_index].target_position.distance_to(destination) <= 64.0:
			continue
		commanders[commander_index]._command_military_move(destination, &"attack")


func _find_nearest_enemy_target(faction_id: int, from_position: Vector2) -> Node2D:
	var nearest: Node2D
	var nearest_priority := 100
	var nearest_distance := INF
	for candidate in _get_indexed_buildings():
		if candidate is not Building or not is_ancestor_of(candidate) or candidate.faction_id == faction_id or not candidate.is_completed():
			continue
		var priority := 0 if candidate.is_government() else (1 if candidate.is_barracks() else 2)
		var distance := from_position.distance_squared_to(candidate.global_position)
		if priority < nearest_priority or (priority == nearest_priority and distance < nearest_distance):
			nearest = candidate
			nearest_priority = priority
			nearest_distance = distance
	if is_instance_valid(nearest):
		return nearest
	for candidate in _get_indexed_units():
		if candidate is Unit and is_ancestor_of(candidate) and candidate.faction_id != faction_id and candidate.health > 0:
			var distance := from_position.distance_squared_to(candidate.global_position)
			if distance < nearest_distance:
				nearest = candidate
				nearest_distance = distance
	return nearest


func _ensure_ai_starting_plan(faction_id: int, faction_name: String):
	# Если у покинутой фракции уже есть поселение, ИИ продолжит имеющиеся
	# стройки и производство. Для пустого угла создаётся базовый план развития.
	for building in _get_indexed_buildings("", faction_id):
		if building is Building and building.faction_id == faction_id:
			return
	var base := get_faction_spawn_position(faction_id)
	var inward_x := 1.0 if faction_id in [0, 2] else -1.0
	var inward_y := 1.0 if faction_id in [0, 1] else -1.0
	var block_center := base + Vector2(220.0 * inward_x, 190.0 * inward_y)
	var district_number := faction_id + 1
	var main_street := "Квартал %d — Главная" % district_number
	var cross_street := "Квартал %d — Выезд" % district_number
	var next_entity_id := faction_id * 1000 + 101

	# Открытая стартовая сеть: сквозная главная улица и ответвление наружу.
	# В отличие от прежнего прямоугольника она не формирует закрытую коробку.
	for x_index in range(-3, 4):
		_spawn_ai_road_segment(block_center + Vector2(x_index * RoadSegment.SEGMENT_LENGTH, 0.0), 0.0, faction_id, faction_name, next_entity_id, main_street)
		next_entity_id += 1
	for y_index in range(-2, 3):
		_spawn_ai_road_segment(block_center + Vector2(3.0 * RoadSegment.SEGMENT_LENGTH * inward_x, y_index * RoadSegment.SEGMENT_LENGTH), PI * 0.5, faction_id, faction_name, next_entity_id, cross_street)
		next_entity_id += 1

	# Здания стоят двумя рядами вдоль главной улицы. Интервалы рассчитаны по
	# реальным коллизиям самых широких зданий.
	var building_id := faction_id * 1000 + 201
	var starting_warehouse := _spawn_ai_building(WAREHOUSE_SCENE, block_center + Vector2(-120.0, -62.0), 0.0, faction_id, faction_name, building_id, main_street, 1)
	if is_instance_valid(starting_warehouse):
		# Стартовый лагерь не даёт всем жителям застрять в добыче материалов
		# для дорог и обеспечивает запас еды до запуска собственного завода.
		starting_warehouse.delivered_wood = starting_warehouse.wood_required
		starting_warehouse.delivered_stone = starting_warehouse.stone_required
		starting_warehouse.build_progress = starting_warehouse.build_time
		starting_warehouse.under_construction = false
		starting_warehouse.progress_bar.visible = false
		starting_warehouse.stored_wood = AI_STARTING_WOOD
		starting_warehouse.stored_stone = AI_STARTING_STONE
		starting_warehouse.stored_products[&"coal"] = AI_STARTING_COAL
		starting_warehouse.stored_products[&"food"] = AI_STARTING_FOOD
		starting_warehouse._update_visuals()
		starting_warehouse.notify_navigation_changed()
	building_id += 1
	_spawn_ai_building(RESIDENCE_SCENE, block_center + Vector2(0.0, -62.0), 0.0, faction_id, faction_name, building_id, main_street, 2)
	building_id += 1
	_spawn_ai_building(FACTORY_SCENE, block_center + Vector2(120.0, -62.0), 0.0, faction_id, faction_name, building_id, main_street, 3)
	building_id += 1
	_spawn_ai_building(FOOD_FACTORY_SCENE, block_center + Vector2(-120.0, 62.0), PI, faction_id, faction_name, building_id, main_street, 4)
	building_id += 1
	_spawn_ai_building(MINE_SCENE, block_center + Vector2(0.0, 62.0), PI, faction_id, faction_name, building_id, main_street, 5)
	building_id += 1
	_spawn_ai_building(POWER_PLANT_SCENE, block_center + Vector2(120.0, 62.0), PI, faction_id, faction_name, building_id, main_street, 6)
	building_id += 1
	_spawn_ai_building(LUMBERJACK_CABIN_SCENE, block_center + Vector2(-240.0 * inward_x, 62.0), PI, faction_id, faction_name, building_id, main_street, 7)


func _plan_ai_expansion(faction_id: int, faction_name: String):
	var residence_count := _get_ai_building_count(faction_id, "residence")
	var requested_stage := maxi(int(floor(float(maxi(residence_count - 1, 0)) / 3.0)) + 1, 1)
	var base := get_faction_spawn_position(faction_id)
	var inward_x := 1.0 if faction_id in [0, 2] else -1.0
	var inward_y := 1.0 if faction_id in [0, 1] else -1.0
	var starting_center := base + Vector2(220.0 * inward_x, 190.0 * inward_y)
	for expansion_stage in range(requested_stage, requested_stage + AI_DISTRICT_SEARCH_ATTEMPTS):
		var district_center := _get_ai_district_center(expansion_stage, starting_center, inward_x, inward_y)
		var connection_start := _find_ai_road_connection_position(faction_id, district_center, starting_center)
		var plan := _make_ai_district_plan(expansion_stage, connection_start, starting_center, inward_x, inward_y, faction_id)
		var road_specs: Array[Dictionary] = plan.road_specs
		var building_specs: Array[Dictionary] = plan.building_specs
		if not _is_ai_district_plan_free(road_specs, building_specs, faction_id, faction_name):
			continue
		var next_entity_id := _next_ai_entity_id()
		for road_spec in road_specs:
			if _has_compatible_ai_road(road_spec.position, float(road_spec.rotation), faction_id):
				continue
			_spawn_ai_road_segment(road_spec.position, float(road_spec.rotation), faction_id, faction_name, next_entity_id, str(road_spec.street))
			next_entity_id += 1
		for building_spec in building_specs:
			_spawn_ai_building(building_spec.scene, building_spec.position, float(building_spec.rotation), faction_id, faction_name, next_entity_id, str(plan.street_name), int(building_spec.house_number))
			next_entity_id += 1
		return


func _make_ai_district_plan(expansion_stage: int, connection_start: Vector2, starting_center: Vector2, inward_x: float, inward_y: float, faction_id: int) -> Dictionary:
	var district_center := _get_ai_district_center(expansion_stage, starting_center, inward_x, inward_y)
	var street_name := "Квартал ИИ %d-%d" % [faction_id + 1, expansion_stage]
	var connector_name := "Поперечная ИИ %d-%d" % [faction_id + 1, expansion_stage]
	var road_specs: Array[Dictionary] = []
	# Прокладывается короткий путь от последнего готового квартала. Совпадающие
	# с уже существующей сеткой сегменты позднее будут переиспользованы.
	var horizontal_direction := signf(district_center.x - connection_start.x)
	var horizontal_steps := int(round(absf(district_center.x - connection_start.x) / RoadSegment.SEGMENT_LENGTH))
	for step_index in range(1, horizontal_steps + 1):
		_append_ai_road_spec(road_specs, connection_start + Vector2(horizontal_direction * RoadSegment.SEGMENT_LENGTH * step_index, 0.0), 0.0, street_name)
	var corner := Vector2(district_center.x, connection_start.y)
	if not is_equal_approx(corner.y, district_center.y):
		var vertical_direction := signf(district_center.y - corner.y)
		var vertical_steps := int(round(absf(district_center.y - corner.y) / RoadSegment.SEGMENT_LENGTH))
		for step_index in range(1, vertical_steps + 1):
			_append_ai_road_spec(road_specs, corner + Vector2(0.0, vertical_direction * RoadSegment.SEGMENT_LENGTH * step_index), PI * 0.5, connector_name)
	for segment_index in range(-3, 4):
		_append_ai_road_spec(road_specs, district_center + Vector2(segment_index * RoadSegment.SEGMENT_LENGTH, 0.0), 0.0, street_name)

	var planned_scenes: Array[PackedScene] = [RESIDENCE_SCENE, RESIDENCE_SCENE, RESIDENCE_SCENE]
	planned_scenes.append(GOVERNMENT_SCENE if not is_instance_valid(_find_ai_government(faction_id)) else WAREHOUSE_SCENE)
	planned_scenes.append(BARRACKS_SCENE)
	planned_scenes.append(MILITARY_FACTORY_SCENE)
	planned_scenes.append(FOOD_FACTORY_SCENE)
	planned_scenes.append(MINE_SCENE if expansion_stage % 2 == 1 else FACTORY_SCENE)
	var building_specs: Array[Dictionary] = []
	for scene_index in range(planned_scenes.size()):
		var upper_row := scene_index < AI_DISTRICT_BUILDING_X_SLOTS.size()
		var slot_index := scene_index if upper_row else scene_index - AI_DISTRICT_BUILDING_X_SLOTS.size()
		var building_position := district_center + Vector2(AI_DISTRICT_BUILDING_X_SLOTS[slot_index], -AI_DISTRICT_BUILDING_ROW_OFFSET if upper_row else AI_DISTRICT_BUILDING_ROW_OFFSET)
		building_specs.append({
			"scene": planned_scenes[scene_index],
			"position": building_position,
			"rotation": _get_ai_building_rotation(building_position, district_center, 0.0),
			"house_number": scene_index + 1,
		})
	return {
		"street_name": street_name,
		"road_specs": road_specs,
		"building_specs": building_specs,
	}


func _append_ai_road_spec(road_specs: Array[Dictionary], position: Vector2, rotation_angle: float, street_name: String):
	var direction := Vector2.RIGHT.rotated(rotation_angle)
	for existing_spec in road_specs:
		var existing_direction := Vector2.RIGHT.rotated(float(existing_spec.rotation))
		if position.distance_squared_to(existing_spec.position) <= 1.0 and absf(direction.dot(existing_direction)) >= 0.985:
			return
	road_specs.append({"position": position, "rotation": rotation_angle, "street": street_name})


func _get_ai_district_offset(stage: int, inward_x: float, inward_y: float) -> Vector2:
	if stage <= 0:
		return Vector2.ZERO
	var zero_based_stage := stage - 1
	var row := int(zero_based_stage / AI_DISTRICT_COLUMNS)
	var index_in_row := zero_based_stage % AI_DISTRICT_COLUMNS
	var column := index_in_row + 1 if row % 2 == 0 else AI_DISTRICT_COLUMNS - index_in_row
	return Vector2(column * AI_DISTRICT_COLUMN_STEP * inward_x, row * AI_DISTRICT_ROW_STEP * inward_y)


func _get_ai_district_center(stage: int, starting_center: Vector2, inward_x: float, inward_y: float) -> Vector2:
	var desired_center := starting_center + _get_ai_district_offset(stage, inward_x, inward_y)
	var minimum := Vector2.ONE * SPAWN_MARGIN
	var maximum := Vector2(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE) - minimum
	var minimum_grid_step := Vector2i(
		ceili((minimum.x - starting_center.x) / RoadSegment.SEGMENT_LENGTH),
		ceili((minimum.y - starting_center.y) / RoadSegment.SEGMENT_LENGTH)
	)
	var maximum_grid_step := Vector2i(
		floori((maximum.x - starting_center.x) / RoadSegment.SEGMENT_LENGTH),
		floori((maximum.y - starting_center.y) / RoadSegment.SEGMENT_LENGTH)
	)
	var desired_grid_step := Vector2i(
		roundi((desired_center.x - starting_center.x) / RoadSegment.SEGMENT_LENGTH),
		roundi((desired_center.y - starting_center.y) / RoadSegment.SEGMENT_LENGTH)
	)
	desired_grid_step.x = clampi(desired_grid_step.x, minimum_grid_step.x, maximum_grid_step.x)
	desired_grid_step.y = clampi(desired_grid_step.y, minimum_grid_step.y, maximum_grid_step.y)
	return starting_center + Vector2(desired_grid_step.x, desired_grid_step.y) * RoadSegment.SEGMENT_LENGTH


func _find_ai_road_connection_position(faction_id: int, target_position: Vector2, grid_origin: Vector2) -> Vector2:
	var nearest_position: Vector2 = grid_origin
	var nearest_distance: float = INF
	for candidate in _get_indexed_buildings("road", faction_id):
		if not is_instance_valid(candidate) or candidate is not RoadSegment or candidate.faction_id != faction_id:
			continue
		var road := candidate as RoadSegment
		var grid_offset: Vector2 = (road.position - grid_origin) / RoadSegment.SEGMENT_LENGTH
		if absf(grid_offset.x - roundf(grid_offset.x)) > 0.01 or absf(grid_offset.y - roundf(grid_offset.y)) > 0.01:
			continue
		var distance: float = road.position.distance_squared_to(target_position)
		if distance < nearest_distance:
			nearest_position = road.position
			nearest_distance = distance
	return nearest_position


func _find_nearest_ai_road(faction_id: int, target_position: Vector2) -> RoadSegment:
	var nearest: RoadSegment
	var nearest_distance: float = INF
	for candidate in _get_indexed_buildings("road", faction_id):
		if not is_instance_valid(candidate) or candidate is not RoadSegment or candidate.faction_id != faction_id:
			continue
		var road := candidate as RoadSegment
		var distance: float = road.position.distance_squared_to(target_position)
		if distance < nearest_distance:
			nearest = road
			nearest_distance = distance
	return nearest


func _get_ai_building_rotation(building_position: Vector2, road_position: Vector2, road_rotation: float) -> float:
	var road_direction := Vector2.RIGHT.rotated(road_rotation)
	var road_perpendicular := Vector2(-road_direction.y, road_direction.x)
	var side := signf((building_position - road_position).dot(road_perpendicular))
	if side == 0.0:
		side = 1.0
	return wrapf(road_rotation + (PI if side > 0.0 else 0.0), -PI, PI)


func _is_ai_district_plan_free(road_specs: Array[Dictionary], building_specs: Array[Dictionary], faction_id: int, faction_name: String) -> bool:
	for road_spec in road_specs:
		if _has_compatible_ai_road(road_spec.position, float(road_spec.rotation), faction_id):
			continue
		var road := ROAD_SCENE.instantiate() as RoadSegment
		road.faction_id = faction_id
		road.faction_name = faction_name
		road.position = road_spec.position
		road.rotation = float(road_spec.rotation)
		var road_position_is_free := _is_ai_road_position_free(road)
		road.free()
		if not road_position_is_free:
			return false
	for building_spec in building_specs:
		var scene := building_spec.scene as PackedScene
		var building := scene.instantiate() as Building
		building.faction_id = faction_id
		building.faction_name = faction_name
		building.position = building_spec.position
		building.rotation = float(building_spec.rotation)
		var building_position_is_free := _is_ai_building_position_free(building)
		building.free()
		if not building_position_is_free:
			return false
	return true


func _has_compatible_ai_road(position: Vector2, rotation_angle: float, faction_id: int) -> bool:
	var direction := Vector2.RIGHT.rotated(rotation_angle)
	for candidate in _get_indexed_buildings("road", faction_id):
		if candidate is not RoadSegment or not is_instance_valid(candidate) or candidate.faction_id != faction_id:
			continue
		var road := candidate as RoadSegment
		var existing_direction := Vector2.RIGHT.rotated(road.rotation)
		if position.distance_squared_to(road.position) <= 1.0 and absf(direction.dot(existing_direction)) >= 0.985:
			return true
	return false


func _next_ai_entity_id() -> int:
	var result := 1
	for candidate in _get_indexed_buildings():
		if candidate is Building and is_ancestor_of(candidate):
			result = maxi(result, candidate.network_id + 1)
	return result


func _spawn_ai_road_segment(position: Vector2, rotation_angle: float, faction_id: int, faction_name: String, entity_id: int, street_name: String) -> RoadSegment:
	var road := ROAD_SCENE.instantiate() as RoadSegment
	road.faction_id = faction_id
	road.faction_name = faction_name
	road.network_id = entity_id
	road.name = "Building_%d" % entity_id
	road.position = position
	road.rotation = rotation_angle
	if not _is_ai_road_position_free(road):
		road.free()
		return null
	$roads.add_child(road)
	road.setup(street_name, rotation_angle)
	_clear_resources_around(position, 40.0)
	road.begin_construction()
	return road


func _spawn_ai_building(scene: PackedScene, position: Vector2, rotation_angle: float, faction_id: int, faction_name: String, entity_id: int, street_name: String, house_number: int) -> Building:
	var building := scene.instantiate() as Building
	building.faction_id = faction_id
	building.faction_name = faction_name
	building.network_id = entity_id
	building.name = "Building_%d" % entity_id
	building.position = position
	var nearest_road := _find_nearest_ai_road(faction_id, position)
	if is_instance_valid(nearest_road):
		rotation_angle = _get_ai_building_rotation(position, nearest_road.position, nearest_road.rotation)
	building.rotation = rotation_angle
	if not _is_ai_building_position_free(building):
		building.free()
		return null
	$buildings.add_child(building)
	building.set_address(street_name, house_number)
	var footprint := _get_building_footprint(building)
	_clear_resources_around(footprint.get_center(), footprint.size.length() * 0.5)
	building.begin_construction()
	return building


func _is_ai_road_position_free(candidate: RoadSegment) -> bool:
	var candidate_direction := Vector2.RIGHT.rotated(candidate.rotation)
	var candidate_footprint := _get_building_footprint(candidate).grow(3.0)
	for existing in _get_indexed_buildings():
		if existing is not Building or not is_instance_valid(existing):
			continue
		if existing is RoadSegment:
			var existing_direction := Vector2.RIGHT.rotated(existing.rotation)
			if absf(candidate_direction.dot(existing_direction)) < 0.985:
				continue
			var offset: Vector2 = existing.position - candidate.position
			if absf(offset.cross(candidate_direction)) >= RoadSegment.MIN_PARALLEL_SPACING:
				continue
			if absf(offset.dot(candidate_direction)) < RoadSegment.SEGMENT_LENGTH - 2.0:
				return false
		elif candidate_footprint.intersects(_get_building_footprint(existing)):
			return false
	return true


func _is_ai_building_position_free(candidate: Building) -> bool:
	var candidate_footprint := _get_building_footprint(candidate).grow(6.0)
	for existing in _get_indexed_buildings():
		if existing is Building and is_instance_valid(existing) and candidate_footprint.intersects(_get_building_footprint(existing)):
			return false
	return true


func _get_building_footprint(building: Building) -> Rect2:
	var collision := building.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape is not RectangleShape2D:
		return Rect2(building.position - Vector2.ONE * 24.0, Vector2.ONE * 48.0)
	var combined_scale := (building.scale * collision.scale).abs()
	var half_size: Vector2 = collision.shape.size * combined_scale * 0.5
	var angle := building.rotation + collision.rotation
	var cosine := absf(cos(angle))
	var sine := absf(sin(angle))
	var extents := Vector2(cosine * half_size.x + sine * half_size.y, sine * half_size.x + cosine * half_size.y)
	var center := building.position + (collision.position * building.scale).rotated(building.rotation)
	return Rect2(center - extents, extents * 2.0)


func _clear_resources_around(center: Vector2, radius: float):
	var lod_manager := get_node_or_null("SimulationLODManager")
	if is_instance_valid(lod_manager) and lod_manager.has_method("remove_resources_in_radius"):
		lod_manager.remove_resources_in_radius(center, radius)
		return
	for resource in get_tree().get_nodes_in_group("resources"):
		if is_instance_valid(resource) and resource.global_position.distance_to(center) <= radius:
			resource.free()


func _clear_spawn_area(center: Vector2):
	var lod_manager := get_node_or_null("SimulationLODManager")
	if is_instance_valid(lod_manager) and lod_manager.has_method("remove_resources_in_radius"):
		lod_manager.remove_resources_in_radius(center, SPAWN_CLEAR_RADIUS)
		return
	for group_name in ["resources", "trees", "rocks"]:
		for resource in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(resource) and resource.global_position.distance_to(center) <= SPAWN_CLEAR_RADIUS:
				resource.free()


func _position_camera_for_local_faction():
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	var network_manager := get_node_or_null("/root/NetworkManager")
	var faction_id: int = int(network_manager.get_local_faction_id()) if is_instance_valid(network_manager) else 0
	if faction_id >= 0:
		camera.position = get_faction_spawn_position(faction_id)


func _get_default_session_slots() -> Array:
	return [
		{"faction_id": 0, "controller_peer_id": 1, "nickname": "Игрок", "is_ai": false},
		{"faction_id": 1, "controller_peer_id": 0, "nickname": "ИИ 1", "is_ai": true},
		{"faction_id": 2, "controller_peer_id": 0, "nickname": "ИИ 2", "is_ai": true},
		{"faction_id": 3, "controller_peer_id": 0, "nickname": "ИИ 3", "is_ai": true},
	]


func _vector_to_data(value: Vector2) -> Array[float]:
	return [value.x, value.y]


func _data_to_vector(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _unhandled_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_tree().call_group("units", "deselect")
