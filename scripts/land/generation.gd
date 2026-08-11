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
const ROAD_SCENE := preload("res://scenes/objects/buildings/road.tscn")
const SPAWN_MARGIN := 320.0
const SPAWN_CLEAR_RADIUS := 230.0
const AI_STRATEGY_INTERVAL := 6.0
const AI_MAX_CONSTRUCTION_BACKLOG := 2
const AI_MIN_CIVILIAN_WORKERS := 6
const AI_ATTACK_MIN_SOLDIERS := 8
const AI_DISTRICT_COLUMNS := 3
const AI_DISTRICT_COLUMN_STEP := 448.0
const AI_DISTRICT_ROW_STEP := 256.0
const AI_DISTRICT_BUILDING_ROW_OFFSET := 62.0
const AI_DISTRICT_BUILDING_X_SLOTS: Array[float] = [-176.0, -80.0, 80.0, 176.0]
const AI_DISTRICT_SEARCH_ATTEMPTS := 12

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


func _process(delta: float):
	ai_strategy_timer -= delta
	if ai_strategy_timer > 0.0:
		return
	ai_strategy_timer = AI_STRATEGY_INTERVAL
	ai_strategy_cycle += 1
	_run_ai_strategy()


func get_save_data() -> Dictionary:
	_ensure_persistent_building_ids()
	var data := {
		"buildings": [],
		"resources": [],
		"units": [],
		"session_slots": [],
		"continuous_harvest": Unit.continuous_harvest_mode,
	}
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		data.session_slots = network_manager.get_session_slots()
	for building in get_tree().get_nodes_in_group("buildings"):
		if building is Building and is_ancestor_of(building):
			data.buildings.append(_serialize_building(building))
	var lod_manager := get_node_or_null("SimulationLODManager")
	if is_instance_valid(lod_manager) and lod_manager.has_method("get_resource_save_data"):
		data.resources = lod_manager.get_resource_save_data()
	else:
		for resource in get_tree().get_nodes_in_group("resources"):
			if not is_instance_valid(resource) or not is_ancestor_of(resource) or resource.is_depleted():
				continue
			if resource.is_in_group("trees"):
				data.resources.append({"type": "tree", "position": _vector_to_data(resource.position), "variant": resource.tree_variant, "amount": resource.wood_amount})
			elif resource.is_in_group("rocks"):
				data.resources.append({"type": "rock", "position": _vector_to_data(resource.position), "variant": resource.rock_variant, "amount": resource.stone_amount})
	for unit in get_tree().get_nodes_in_group("units"):
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
	for candidate in get_tree().get_nodes_in_group("buildings"):
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
	for candidate in get_tree().get_nodes_in_group("units"):
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
	return result


func get_network_unit_states(faction_ids: Array = []) -> Array:
	var result: Array = []
	var faction_filter := _make_network_faction_filter(faction_ids)
	for candidate in get_tree().get_nodes_in_group("units"):
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
			"facing_direction": _vector_to_data(unit.facing_direction),
			"has_armor": unit.has_armor,
			"has_rifle": unit.has_rifle,
		})
	return result


func get_network_building_states(faction_ids: Array = []) -> Array:
	var result: Array = []
	var faction_filter := _make_network_faction_filter(faction_ids)
	for candidate in get_tree().get_nodes_in_group("buildings"):
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
	for building in get_tree().get_nodes_in_group("buildings"):
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
	for candidate in get_tree().get_nodes_in_group("units"):
		if candidate is not Unit or not is_ancestor_of(candidate) or not authoritative_factions.has(candidate.faction_id):
			continue
		var key := "%d:%d" % [candidate.faction_id, candidate.network_id]
		if not authoritative_keys.has(key):
			candidate.queue_free()


func _apply_network_unit_state(unit: Unit, state: Dictionary):
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
	unit.military_rank = str(state.get("military_rank", unit.military_rank))
	unit.squad_id = int(state.get("squad_id", unit.squad_id))
	unit.platoon_id = int(state.get("platoon_id", unit.platoon_id))
	unit.squad_commander_network_id = int(state.get("squad_commander_network_id", unit.squad_commander_network_id))
	unit.platoon_commander_network_id = int(state.get("platoon_commander_network_id", unit.platoon_commander_network_id))
	unit.military_order = StringName(state.get("military_order", unit.military_order))
	unit.squad_formation_offset = _data_to_vector(state.get("squad_formation_offset", [0, 0]))
	unit.has_armor = bool(state.get("has_armor", unit.has_armor))
	unit.has_rifle = bool(state.get("has_rifle", unit.has_rifle))
	unit.facing_direction = _data_to_vector(state.get("facing_direction", [0, 1]))
	unit.target_building = _find_building_by_network_id(int(state.get("target_building_network_id", 0)), unit.faction_id)
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
	unit.inside_building = _find_building_by_network_id(int(state.get("inside_building_network_id", 0)), unit.faction_id)
	if is_instance_valid(unit.inside_building) and unit not in unit.inside_building.occupants:
		unit.inside_building.occupants.append(unit)
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
	for candidate in get_tree().get_nodes_in_group("buildings"):
		if candidate is not Building or not is_ancestor_of(candidate) or candidate.placement_preview or not authoritative_factions.has(candidate.faction_id):
			continue
		var key := "%d:%d" % [candidate.faction_id, candidate.network_id]
		if not authoritative_keys.has(key):
			candidate.queue_free()


func _apply_network_building_state(building: Building, state: Dictionary):
	building.global_position = _data_to_vector(state.get("position", [building.global_position.x, building.global_position.y]))
	building.rotation = float(state.get("rotation", building.rotation))
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
	building.under_construction = bool(state.get("under_construction", building.under_construction))
	building.progress_bar.visible = building.under_construction
	building._update_visuals()


func _find_unit_by_network_id(network_id: int, faction_id: int) -> Unit:
	for candidate in get_tree().get_nodes_in_group("units"):
		if candidate is Unit and is_ancestor_of(candidate) and candidate.network_id == network_id and candidate.faction_id == faction_id:
			return candidate
	return null


func can_spawn_network_building(specification: Dictionary) -> bool:
	var kind := str(specification.get("kind", ""))
	var position: Variant = specification.get("position", Vector2.ZERO)
	var faction_id := int(specification.get("faction_id", -1))
	if position is not Vector2 or faction_id < 0:
		return false
	var build_manager := get_node_or_null("BuildManager")
	if kind == "road":
		return is_instance_valid(build_manager) and not build_manager._road_segment_overlaps_existing(position, float(specification.get("rotation", 0.0)))
	var attached_to_road := false
	for candidate in get_tree().get_nodes_in_group("roads"):
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
		"road": return ROAD_SCENE
		"residence": return RESIDENCE_SCENE
		_: return null


func apply_save_data(data: Dictionary):
	Unit.clear_selection()
	Building.selected_building = null
	var lod_manager := get_node_or_null("SimulationLODManager")
	if is_instance_valid(lod_manager) and lod_manager.has_method("clear_resource_data"):
		lod_manager.clear_resource_data()
	for unit in get_tree().get_nodes_in_group("units"):
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
	unit.simulation_importance = 2 if unit.military_role == &"commander" else (1 if unit.is_mobilized else 0)
	unit.squad_id = int(data.get("squad_id", 0))
	unit.platoon_id = int(data.get("platoon_id", 0))
	unit.squad_commander_network_id = int(data.get("squad_commander_network_id", 0))
	unit.platoon_commander_network_id = int(data.get("platoon_commander_network_id", 0))
	unit.military_order = StringName(data.get("military_order", "hold"))
	unit.squad_formation_offset = _data_to_vector(data.get("squad_formation_offset", [0, 0]))
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
		unit.command_move(_data_to_vector(data.get("target_position", data.get("position", [300, 300]))))
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
	for building in get_tree().get_nodes_in_group("buildings"):
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
		for unit in get_tree().get_nodes_in_group("units"):
			if unit is Unit and is_ancestor_of(unit) and unit.faction_id == faction_id:
				has_state = true
				break
		if not has_state:
			for building in get_tree().get_nodes_in_group("buildings"):
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
	for unit in get_tree().get_nodes_in_group("units"):
		if unit is Unit and unit.faction_id == faction_id:
			unit.configure_faction(faction_id, controller_peer_id, ai_controlled, faction_name)
	for building in get_tree().get_nodes_in_group("buildings"):
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
	for candidate in get_tree().get_nodes_in_group("units"):
		if candidate is Unit and is_ancestor_of(candidate) and candidate.ai_controlled:
			ai_factions[candidate.faction_id] = candidate.faction_name
	for raw_faction_id in ai_factions:
		var faction_id := int(raw_faction_id)
		var faction_name := str(ai_factions[raw_faction_id])
		_ensure_ai_starting_plan(faction_id, faction_name)
		_configure_ai_economy(faction_id)
		_configure_ai_population_and_army(faction_id)
		if _get_ai_construction_count(faction_id) <= AI_MAX_CONSTRUCTION_BACKLOG:
			_plan_ai_expansion(faction_id, faction_name)
		_issue_ai_attack_orders(faction_id)


func _configure_ai_economy(faction_id: int):
	var mine_index := 0
	var factory_index := 0
	for candidate in get_tree().get_nodes_in_group("buildings"):
		if candidate is not Building or not is_ancestor_of(candidate) or candidate.faction_id != faction_id or not candidate.is_factory():
			continue
		var building := candidate as Building
		building.set_worker_target(building.max_workers)
		if building.is_food_factory():
			building.set_recipe(&"food")
		elif building.is_power_plant():
			building.set_recipe(&"electricity")
		elif building.is_mine():
			var mine_recipes: Array[StringName] = [&"mine_iron", &"mine_coal", &"mine_stone"]
			building.set_recipe(mine_recipes[(ai_strategy_cycle + mine_index) % mine_recipes.size()])
			mine_index += 1
		elif building.is_military_factory():
			building.set_recipe(_get_ai_needed_equipment_recipe(faction_id))
		else:
			building.set_recipe(&"tools" if (ai_strategy_cycle + factory_index) % 2 == 0 else &"planks")
			factory_index += 1


func _get_ai_needed_equipment_recipe(faction_id: int) -> StringName:
	var armor := 0
	var rifles := 0
	for candidate in get_tree().get_nodes_in_group("buildings"):
		if candidate is Building and is_ancestor_of(candidate) and candidate.faction_id == faction_id and candidate.is_warehouse() and candidate.is_completed():
			armor += candidate.get_stored_resource(&"armor")
			rifles += candidate.get_stored_resource(&"rifles")
	for candidate in get_tree().get_nodes_in_group("units"):
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
	government.set_migration_target(maxi(housing_capacity, population))
	var army_capacity := government.get_army_capacity()
	var desired_army := mini(int(round(population * 0.55)), maxi(population - AI_MIN_CIVILIAN_WORKERS, 0))
	government.set_mobilization_target(mini(desired_army, army_capacity))


func _find_ai_government(faction_id: int) -> GovernmentBuilding:
	for candidate in get_tree().get_nodes_in_group("buildings"):
		if candidate is GovernmentBuilding and is_ancestor_of(candidate) and candidate.faction_id == faction_id:
			return candidate
	return null


func _get_ai_construction_count(faction_id: int) -> int:
	var result := 0
	for candidate in get_tree().get_nodes_in_group("buildings"):
		if candidate is Building and is_ancestor_of(candidate) and candidate.faction_id == faction_id and candidate.under_construction:
			result += 1
	return result


func _get_ai_building_count(faction_id: int, building_kind: String) -> int:
	var result := 0
	for candidate in get_tree().get_nodes_in_group("buildings"):
		if candidate is Building and is_ancestor_of(candidate) and candidate.faction_id == faction_id and candidate.building_kind == building_kind:
			result += 1
	return result


func _issue_ai_attack_orders(faction_id: int):
	var soldiers: Array[Unit] = []
	var commanders: Array[Unit] = []
	var riflemen := 0
	for candidate in get_tree().get_nodes_in_group("units"):
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
	for candidate in get_tree().get_nodes_in_group("buildings"):
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
	for candidate in get_tree().get_nodes_in_group("units"):
		if candidate is Unit and is_ancestor_of(candidate) and candidate.faction_id != faction_id and candidate.health > 0:
			var distance := from_position.distance_squared_to(candidate.global_position)
			if distance < nearest_distance:
				nearest = candidate
				nearest_distance = distance
	return nearest


func _ensure_ai_starting_plan(faction_id: int, faction_name: String):
	# Если у покинутой фракции уже есть поселение, ИИ продолжит имеющиеся
	# стройки и производство. Для пустого угла создаётся базовый план развития.
	for building in get_tree().get_nodes_in_group("buildings"):
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
		_spawn_ai_road_segment(block_center + Vector2(224.0 * inward_x, y_index * RoadSegment.SEGMENT_LENGTH), PI * 0.5, faction_id, faction_name, next_entity_id, cross_street)
		next_entity_id += 1

	# Здания стоят двумя рядами вдоль главной улицы. Интервалы рассчитаны по
	# реальным коллизиям самых широких зданий.
	var building_id := faction_id * 1000 + 201
	_spawn_ai_building(WAREHOUSE_SCENE, block_center + Vector2(-120.0, -62.0), PI, faction_id, faction_name, building_id, main_street, 1)
	building_id += 1
	_spawn_ai_building(RESIDENCE_SCENE, block_center + Vector2(0.0, -62.0), PI, faction_id, faction_name, building_id, main_street, 2)
	building_id += 1
	_spawn_ai_building(FACTORY_SCENE, block_center + Vector2(120.0, -62.0), PI, faction_id, faction_name, building_id, main_street, 3)
	building_id += 1
	_spawn_ai_building(FOOD_FACTORY_SCENE, block_center + Vector2(-120.0, 62.0), 0.0, faction_id, faction_name, building_id, main_street, 4)
	building_id += 1
	_spawn_ai_building(MINE_SCENE, block_center + Vector2(0.0, 62.0), 0.0, faction_id, faction_name, building_id, main_street, 5)
	building_id += 1
	_spawn_ai_building(POWER_PLANT_SCENE, block_center + Vector2(120.0, 62.0), 0.0, faction_id, faction_name, building_id, main_street, 6)


func _plan_ai_expansion(faction_id: int, faction_name: String):
	var residence_count := _get_ai_building_count(faction_id, "residence")
	var requested_stage := maxi(int(floor(float(maxi(residence_count - 1, 0)) / 3.0)) + 1, 1)
	var base := get_faction_spawn_position(faction_id)
	var inward_x := 1.0 if faction_id in [0, 2] else -1.0
	var inward_y := 1.0 if faction_id in [0, 1] else -1.0
	var starting_center := base + Vector2(220.0 * inward_x, 190.0 * inward_y)
	var last_developed_center := starting_center + _get_ai_district_offset(requested_stage - 1, inward_x, inward_y)
	for expansion_stage in range(requested_stage, requested_stage + AI_DISTRICT_SEARCH_ATTEMPTS):
		var plan := _make_ai_district_plan(expansion_stage, last_developed_center, starting_center, inward_x, inward_y, faction_id)
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
	var district_center := starting_center + _get_ai_district_offset(expansion_stage, inward_x, inward_y)
	var world_limit := Vector2(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE) - Vector2.ONE * SPAWN_MARGIN
	district_center = district_center.clamp(Vector2.ONE * SPAWN_MARGIN, world_limit)
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
		building_specs.append({
			"scene": planned_scenes[scene_index],
			"position": district_center + Vector2(AI_DISTRICT_BUILDING_X_SLOTS[slot_index], -AI_DISTRICT_BUILDING_ROW_OFFSET if upper_row else AI_DISTRICT_BUILDING_ROW_OFFSET),
			"rotation": PI if upper_row else 0.0,
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
	for candidate in get_tree().get_nodes_in_group("roads"):
		if candidate is not RoadSegment or not is_instance_valid(candidate) or candidate.faction_id != faction_id:
			continue
		var road := candidate as RoadSegment
		var existing_direction := Vector2.RIGHT.rotated(road.rotation)
		if position.distance_squared_to(road.position) <= 1.0 and absf(direction.dot(existing_direction)) >= 0.985:
			return true
	return false


func _next_ai_entity_id() -> int:
	var result := 1
	for candidate in get_tree().get_nodes_in_group("buildings"):
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
	for existing in get_tree().get_nodes_in_group("buildings"):
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
	for existing in get_tree().get_nodes_in_group("buildings"):
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
