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
		if is_instance_valid(network_manager):
			network_manager.prepare_loaded_game(saved_state.get("session_slots", []))
		apply_save_data(saved_state)
	elif generate_world_on_ready:
		Unit.next_name_index = 0
		var slots: Array = network_manager.get_session_slots() if is_instance_valid(network_manager) and network_manager.has_session() else _get_default_session_slots()
		spawn_session_units(slots)


func get_save_data() -> Dictionary:
	var data := {
		"buildings": [],
		"resources": [],
		"units": [],
		"session_slots": [],
		"auto_work": Unit.auto_work_enabled,
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
		var saved_position: Vector2 = unit.global_position
		if is_instance_valid(unit.inside_building):
			saved_position = unit.inside_building.get_exit_position(unit)
		data.units.append({
			"position": _vector_to_data(saved_position),
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
		})
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		data["camera"] = {"position": _vector_to_data(camera.position), "zoom": _vector_to_data(camera.zoom)}
	return data


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
			"planks": building.get_stored_resource(&"planks"),
			"tools": building.get_stored_resource(&"tools"),
			"food": building.get_stored_resource(&"food"),
		},
		"limits": limits,
		"recipe": str(building.selected_recipe),
	}
	if building is RoadSegment:
		result["street_name"] = building.street_name
	elif building is GovernmentBuilding:
		result["migration_target"] = building.migration_target
		result["migration_timer"] = building.migration_timer
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
	Unit.auto_work_enabled = bool(data.get("auto_work", true))
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
	building.stored_products[&"planks"] = int(stored.get("planks", 0))
	building.stored_products[&"tools"] = int(stored.get("tools", 0))
	building.stored_products[&"food"] = int(stored.get("food", 0))
	var limits: Dictionary = data.get("limits", {})
	_restore_storage_limits(building, limits)
	building.set_recipe(StringName(data.get("recipe", "planks")))
	if building is GovernmentBuilding:
		building.migration_target = int(data.get("migration_target", 0))
		building.migration_timer = float(data.get("migration_timer", building.migration_interval))
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
	unit.position = _data_to_vector(data.get("position", [300, 300]))
	add_child(unit)


func _restore_storage_limits(building: Building, limits: Dictionary):
	if not building.is_warehouse() or limits.is_empty():
		return
	for resource_type in Building.RESOURCE_TYPES:
		building.storage_limits[resource_type] = int(limits.get(str(resource_type), 0))
	# В сохранениях до появления еды сумма четырёх квот уже занимала весь склад.
	# Выделяем еде место за счёт свободной части старых квот, не удаляя ресурсы.
	if not limits.has("food"):
		building.storage_limits[&"food"] = 40
	var overflow := maxi(building.get_total_storage_limits() - building.storage_capacity, 0)
	for resource_type in [&"stone", &"wood", &"planks", &"tools", &"food"]:
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
	var street_name := "Стартовая %d" % (faction_id + 1)
	var rotation_angle := 0.0 if inward_y > 0.0 else PI

	var road := ROAD_SCENE.instantiate() as RoadSegment
	road.faction_id = faction_id
	road.faction_name = faction_name
	road.network_id = faction_id * 1000 + 101
	road.name = "Building_%d" % road.network_id
	road.position = base + Vector2(105.0 * inward_x, 65.0 * inward_y)
	$roads.add_child(road)
	road.setup(street_name, 0.0)
	road.begin_construction()

	_spawn_ai_building(WAREHOUSE_SCENE, base + Vector2(75.0 * inward_x, 125.0 * inward_y), rotation_angle, faction_id, faction_name, faction_id * 1000 + 102, street_name, 1)
	_spawn_ai_building(RESIDENCE_SCENE, base + Vector2(150.0 * inward_x, 125.0 * inward_y), rotation_angle, faction_id, faction_name, faction_id * 1000 + 103, street_name, 2)
	_spawn_ai_building(FACTORY_SCENE, base + Vector2(110.0 * inward_x, 185.0 * inward_y), rotation_angle, faction_id, faction_name, faction_id * 1000 + 104, street_name, 3)
	_spawn_ai_building(FOOD_FACTORY_SCENE, base + Vector2(195.0 * inward_x, 185.0 * inward_y), rotation_angle, faction_id, faction_name, faction_id * 1000 + 105, street_name, 4)


func _spawn_ai_building(scene: PackedScene, position: Vector2, rotation_angle: float, faction_id: int, faction_name: String, entity_id: int, street_name: String, house_number: int):
	var building := scene.instantiate() as Building
	building.faction_id = faction_id
	building.faction_name = faction_name
	building.network_id = entity_id
	building.name = "Building_%d" % entity_id
	building.position = position
	building.rotation = rotation_angle
	$buildings.add_child(building)
	building.set_address(street_name, house_number)
	building.begin_construction()


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
