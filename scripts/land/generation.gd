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
const ROAD_SCENE := preload("res://scenes/objects/buildings/road.tscn")

@export var starting_unit_count := 5
@export var unit_spawn_position := Vector2(300, 300)
@export var unit_spacing := 40.0
@export var generate_world_on_ready := true


func spawn_starting_units():
	for i in range(starting_unit_count):
		var unit = UNIT_SCENE.instantiate()
		unit.position = unit_spawn_position + Vector2(i * unit_spacing, 0)
		add_child(unit)

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
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var grass_texture = grass_textures[rng.randi_range(0, grass_textures.size() - 1)]
			var grass_sprite = Sprite2D.new()
			grass_sprite.texture = grass_texture
			grass_sprite.position = Vector2(x * TILE_SIZE, y * TILE_SIZE)
			$ground.add_child(grass_sprite)


func spawn_tree(pos: Vector2):
	var tree = TREE_SCENE.instantiate()
	tree.tree_variant = rng.randi_range(0, tree_textures.size() - 1)
	tree.position = pos
	$trees.add_child(tree)


func spawn_rock(pos: Vector2):
	var rock = ROCK_SCENE.instantiate()
	rock.rock_variant = rng.randi_range(0, 2)
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
	world_seed = int(save_manager.current_seed) if is_instance_valid(save_manager) else 12345
	rng.seed = world_seed

	forest_noise.seed = world_seed
	forest_noise.frequency = FOREST_NOISE_FREQUENCY

	if generate_world_on_ready:
		generate_ground()
		generate_forest()
		generate_rock_deposits()
		spawn_starting_units()
	var saved_state: Dictionary = save_manager.consume_pending_save() if is_instance_valid(save_manager) else {}
	if not saved_state.is_empty():
		apply_save_data(saved_state)


func get_save_data() -> Dictionary:
	var data := {
		"buildings": [],
		"resources": [],
		"units": [],
		"auto_work": Unit.auto_work_enabled,
		"continuous_harvest": Unit.continuous_harvest_mode,
	}
	for building in get_tree().get_nodes_in_group("buildings"):
		if building is Building and is_ancestor_of(building):
			data.buildings.append(_serialize_building(building))
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
			"health": unit.health,
			"max_health": unit.max_health,
			"profession": unit.profession,
			"wood": unit.carried_wood,
			"stone": unit.carried_stone,
			"produced_items": unit.produced_items,
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
		},
		"limits": limits,
		"recipe": str(building.selected_recipe),
	}
	if building is RoadSegment:
		result["street_name"] = building.street_name
	return result


func apply_save_data(data: Dictionary):
	Unit.clear_selection()
	Building.selected_building = null
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


func _restore_resource(data: Dictionary):
	var resource: Node2D
	if data.get("type", "") == "tree":
		resource = TREE_SCENE.instantiate()
		resource.tree_variant = int(data.get("variant", 0))
		resource.wood_amount = int(data.get("amount", 20))
		resource.position = _data_to_vector(data.get("position", [0, 0]))
		$trees.add_child(resource)
	elif data.get("type", "") == "rock":
		resource = ROCK_SCENE.instantiate()
		resource.rock_variant = int(data.get("variant", 0))
		resource.stone_amount = int(data.get("amount", 30))
		resource.position = _data_to_vector(data.get("position", [0, 0]))
		$rocks.add_child(resource)


func _restore_building(data: Dictionary):
	var kind := str(data.get("kind", "residence"))
	var scene: PackedScene
	match kind:
		"warehouse": scene = WAREHOUSE_SCENE
		"factory": scene = FACTORY_SCENE
		"road": scene = ROAD_SCENE
		_: scene = RESIDENCE_SCENE
	var building := scene.instantiate() as Building
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
	var limits: Dictionary = data.get("limits", {})
	for resource_type in Building.RESOURCE_TYPES:
		if limits.has(str(resource_type)):
			building.storage_limits[resource_type] = int(limits[str(resource_type)])
	building.set_recipe(StringName(data.get("recipe", "planks")))
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
	unit.unit_name = str(data.get("name", ""))
	unit.max_health = int(data.get("max_health", 100))
	unit.health = int(data.get("health", unit.max_health))
	unit.profession = str(data.get("profession", "Безработный"))
	unit.carried_wood = int(data.get("wood", 0))
	unit.carried_stone = int(data.get("stone", 0))
	unit.produced_items = int(data.get("produced_items", 0))
	unit.position = _data_to_vector(data.get("position", [300, 300]))
	add_child(unit)


func _vector_to_data(value: Vector2) -> Array[float]:
	return [value.x, value.y]


func _data_to_vector(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _unhandled_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_tree().call_group("units", "deselect")
