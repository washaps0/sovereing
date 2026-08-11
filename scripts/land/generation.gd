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


func _serialize_building(building: Building) -> Dictionary:
	var limits := {}
	for resource_type in Building.RESOURCE_TYPES:
		limits[str(resource_type)] = building.get_storage_limit(resource_type)
	var result := {
		"kind": building.building_kind,
		"faction_id": building.faction_id,
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


func _restore_building(data: Dictionary):
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


func _restore_unit(data: Dictionary):
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
		return

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
	var north_street := "Квартал %d — Север" % district_number
	var south_street := "Квартал %d — Юг" % district_number
	var west_street := "Квартал %d — Запад" % district_number
	var east_street := "Квартал %d — Восток" % district_number
	var next_entity_id := faction_id * 1000 + 101

	# Прямоугольник 384×192: шесть горизонтальных и три вертикальных сегмента
	# на каждой стороне. Торцы соприкасаются без наложения параллельных дорог.
	for x_index in range(6):
		var x_offset := -160.0 + x_index * RoadSegment.SEGMENT_LENGTH
		_spawn_ai_road_segment(block_center + Vector2(x_offset, -96.0), 0.0, faction_id, faction_name, next_entity_id, north_street)
		next_entity_id += 1
		_spawn_ai_road_segment(block_center + Vector2(x_offset, 96.0), 0.0, faction_id, faction_name, next_entity_id, south_street)
		next_entity_id += 1
	for y_index in range(-1, 2):
		_spawn_ai_road_segment(block_center + Vector2(-192.0, y_index * RoadSegment.SEGMENT_LENGTH), PI * 0.5, faction_id, faction_name, next_entity_id, west_street)
		next_entity_id += 1
		_spawn_ai_road_segment(block_center + Vector2(192.0, y_index * RoadSegment.SEGMENT_LENGTH), PI * 0.5, faction_id, faction_name, next_entity_id, east_street)
		next_entity_id += 1

	# Здания стоят двумя рядами вдоль северной и южной дорог. Интервалы
	# рассчитаны по реальным коллизиям самых широких зданий.
	var building_id := faction_id * 1000 + 201
	_spawn_ai_building(WAREHOUSE_SCENE, block_center + Vector2(-112.0, -45.0), PI, faction_id, faction_name, building_id, north_street, 1)
	building_id += 1
	_spawn_ai_building(RESIDENCE_SCENE, block_center + Vector2(0.0, -45.0), PI, faction_id, faction_name, building_id, north_street, 2)
	building_id += 1
	_spawn_ai_building(FACTORY_SCENE, block_center + Vector2(112.0, -45.0), PI, faction_id, faction_name, building_id, north_street, 3)
	building_id += 1
	_spawn_ai_building(FOOD_FACTORY_SCENE, block_center + Vector2(-112.0, 45.0), 0.0, faction_id, faction_name, building_id, south_street, 1)
	building_id += 1
	_spawn_ai_building(MINE_SCENE, block_center + Vector2(0.0, 45.0), 0.0, faction_id, faction_name, building_id, south_street, 2)
	building_id += 1
	_spawn_ai_building(POWER_PLANT_SCENE, block_center + Vector2(112.0, 45.0), 0.0, faction_id, faction_name, building_id, south_street, 3)


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
