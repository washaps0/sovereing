class_name Building
extends Area2D

const CONSTRUCTION_SOUND := preload("res://assets/sounds/construction.mp3")
const RESOURCE_TYPES: Array[StringName] = [&"wood", &"stone", &"iron", &"coal", &"planks", &"tools", &"food", &"armor", &"rifles"]
const RESOURCE_NAMES := {
	&"wood": "Дерево",
	&"stone": "Камень",
	&"iron": "Железо",
	&"coal": "Уголь",
	&"planks": "Доски",
	&"tools": "Инструменты",
	&"food": "Еда",
	&"armor": "Броня",
	&"rifles": "Автоматы",
	&"electricity": "Электричество",
}
const FACTORY_RECIPES := {
	&"planks": {
		"name": "Доски",
		"inputs": {&"wood": 2},
		"output": &"planks",
		"amount": 1,
		"time": 2.5,
	},
	&"tools": {
		"name": "Инструменты",
		"inputs": {&"wood": 1, &"stone": 2},
		"output": &"tools",
		"amount": 1,
		"time": 4.0,
	},
	&"food": {
		"name": "Еда",
		"inputs": {},
		"output": &"food",
		"amount": 1,
		"time": 15.0,
	},
	&"mine_stone": {
		"name": "Камень",
		"inputs": {},
		"outputs": {&"stone": 1},
		"time": 3.0,
	},
	&"mine_coal": {
		"name": "Уголь",
		"inputs": {},
		"outputs": {&"coal": 1},
		"time": 3.0,
	},
	&"mine_iron": {
		"name": "Железо",
		"inputs": {},
		"outputs": {&"iron": 1},
		"time": 3.0,
	},
	&"mine_both": {
		"name": "Камень и уголь (медленнее ×2)",
		"inputs": {},
		"outputs": {&"stone": 1, &"coal": 1},
		"time": 6.0,
	},
	&"electricity": {
		"name": "Электричество",
		"inputs": {&"coal": 1},
		"outputs": {&"electricity": 4},
		"time": 4.0,
	},
	&"armor": {
		"name": "Броня",
		"inputs": {&"iron": 3, &"coal": 1},
		"outputs": {&"armor": 1},
		"time": 8.0,
	},
	&"rifles": {
		"name": "Автоматы",
		"inputs": {&"iron": 2, &"tools": 1},
		"outputs": {&"rifles": 1},
		"time": 6.0,
	},
	&"forestry": {
		"name": "Лесничество",
		"inputs": {},
		"outputs": {&"wood": 1},
		"time": 1.0,
	},
}
const INDUSTRIAL_RECIPES: Array[StringName] = [&"planks", &"tools"]
const FOOD_RECIPES: Array[StringName] = [&"food"]
const MINE_RECIPES: Array[StringName] = [&"mine_stone", &"mine_coal", &"mine_iron", &"mine_both"]
const POWER_PLANT_RECIPES: Array[StringName] = [&"electricity"]
const MILITARY_FACTORY_RECIPES: Array[StringName] = [&"armor", &"rifles"]
const FORESTRY_RECIPES: Array[StringName] = [&"forestry"]
const FACTORY_ELECTRICITY_PER_CYCLE := 1

@export var display_name := "Здание"
@export var building_kind := "residence"
@export var wood_required := 10
@export var stone_required := 0
@export var build_time := 5.0
@export var storage_capacity := 0
@export var electricity_capacity := 0
@export var max_workers := 0
@export var desired_workers := 5
@export var max_occupants := 8
@export var max_builders := 3
@export var faction_id := 0
@export var faction_name := "Игрок"
@export var network_id := 0
@export_range(100.0, 1200.0, 10.0) var construction_sound_max_distance := 520.0
@export_range(-30.0, 6.0, 0.5) var construction_sound_volume_db := -8.0
@export_range(0.5, 1.5, 0.01) var construction_pitch_min := 0.9
@export_range(0.5, 1.5, 0.01) var construction_pitch_max := 1.1
@export_range(0.1, 3.0, 0.05) var construction_sound_interval_min := 0.75
@export_range(0.1, 3.0, 0.05) var construction_sound_interval_max := 1.15

static var selected_building: Building

var delivered_wood := 0
var delivered_stone := 0
var build_progress := 0.0
var stored_wood := 0
var stored_stone := 0
var stored_products := {&"iron": 0, &"coal": 0, &"planks": 0, &"tools": 0, &"food": 0, &"armor": 0, &"rifles": 0}
var stored_electricity := 0
var storage_limits := {}
var under_construction := false
var assigned_workers: Array[Unit] = []
var occupants: Array[Unit] = []
var entry_reservations: Array[Unit] = []
var progress_bar: WorldProgressBar
var address := ""
var address_label: Label
var status_label: Label
var active_builders: Array[Unit] = []
var selected_recipe: StringName = &"planks"
var mouse_is_over := false
var placement_preview := false
var lod_active := true
var next_construction_sound_time_msec := 0
var world_index: Node
var world_navigation: Node
var world_audio_pool: Node
var housekeeping_timer := 0.0
var last_overlay_rotation := INF

@onready var building_sprite: Sprite2D = $Sprite2D


func _ready():
	add_to_group("buildings")
	world_index = get_tree().get_first_node_in_group("world_index")
	world_navigation = get_tree().get_first_node_in_group("world_navigation")
	world_audio_pool = get_tree().get_first_node_in_group("world_audio_pool")
	if is_instance_valid(world_index):
		world_index.register_building(self)
	if is_instance_valid(world_navigation):
		world_navigation.invalidate()
	if is_warehouse():
		storage_capacity = 300
		storage_limits = {&"wood": 40, &"stone": 40, &"iron": 40, &"coal": 40, &"planks": 40, &"tools": 20, &"food": 40, &"armor": 20, &"rifles": 20}
	var available_recipes := get_available_recipe_types()
	if is_factory() and selected_recipe not in available_recipes:
		selected_recipe = available_recipes[0]
	if is_factory():
		desired_workers = clampi(desired_workers, 0, max_workers)
	_create_progress_bar()
	_create_address_label()
	_create_status_label()


func _exit_tree():
	if is_instance_valid(world_index):
		world_index.unregister_building(self)
	if is_instance_valid(world_navigation):
		world_navigation.invalidate()
	if selected_building == self:
		selected_building = null
	for unit in occupants.duplicate():
		if is_instance_valid(unit):
			unit.force_exit_building(self)
	occupants.clear()
	entry_reservations.clear()


func dismantle():
	if placement_preview or is_queued_for_deletion():
		return
	var units: Array = world_index.get_units() if is_instance_valid(world_index) else get_tree().get_nodes_in_group("units")
	for unit in units:
		if unit is Unit:
			unit.on_building_dismantled(self)
	queue_free()


func _process(delta: float):
	housekeeping_timer -= delta
	if housekeeping_timer <= 0.0:
		housekeeping_timer = 0.5
		_cleanup_workers()
		_cleanup_builders()
		_cleanup_occupants()
		_cleanup_entry_reservations()
	if not is_equal_approx(last_overlay_rotation, rotation):
		last_overlay_rotation = rotation
		_update_overlay_orientation()
	if status_label == null:
		return
	if is_factory():
		status_label.text = ""
		status_label.visible = false
	elif (is_residence() or is_barracks()) and is_completed():
		status_label.text = ("Солдаты: %d/%d" if is_barracks() else "Жильцы: %d/%d") % [occupants.size(), max_occupants]
		status_label.visible = mouse_is_over
	else:
		status_label.visible = false


func set_lod_active(active: bool):
	if lod_active == active:
		return
	lod_active = active
	if not active:
		next_construction_sound_time_msec = 0
	visible = active
	input_pickable = active
	# Camera distance controls presentation only. Housekeeping, collisions and
	# area monitoring stay identical off-screen, otherwise builders and workers
	# can lose their targets merely because the player moved the camera.
	monitoring = true
	set_process(true)


func _update_overlay_orientation():
	# Само здание вращается к дороге, а интерфейсные подписи всегда остаются
	# горизонтальными и на прежнем месте относительно экрана.
	if is_instance_valid(address_label):
		address_label.rotation = -rotation
		address_label.position = Vector2(-55, -38).rotated(-rotation)
	if is_instance_valid(status_label):
		status_label.rotation = -rotation
		status_label.position = Vector2(-42, 19).rotated(-rotation)
	if is_instance_valid(progress_bar):
		progress_bar.rotation = -rotation
		progress_bar.position = Vector2(0, -24).rotated(-rotation)


func _create_address_label():
	address_label = Label.new()
	address_label.position = Vector2(-55, -38)
	address_label.scale = Vector2(0.7, 0.7)
	address_label.z_index = 20
	address_label.visible = false
	add_child(address_label)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _on_mouse_entered():
	mouse_is_over = true
	address_label.visible = not address.is_empty()


func _on_mouse_exited():
	mouse_is_over = false
	address_label.visible = false


func _create_status_label():
	status_label = Label.new()
	status_label.position = Vector2(-42, 19)
	status_label.scale = Vector2(0.55, 0.55)
	status_label.z_index = 20
	status_label.visible = false
	add_child(status_label)


func set_address(street_name: String, house_number: int):
	address = "%s — %s, %d" % [display_name, street_name, house_number]
	address_label.text = address


func rename_address_street(old_name: String, new_name: String):
	var prefix := "%s — %s, " % [display_name, old_name]
	if not address.begins_with(prefix):
		return
	address = "%s — %s, %s" % [display_name, new_name, address.substr(prefix.length())]
	if is_instance_valid(address_label):
		address_label.text = address


func _create_progress_bar():
	progress_bar = WorldProgressBar.new()
	progress_bar.position = Vector2(0, -24)
	progress_bar.bar_width = 36.0
	progress_bar.bar_height = 2.0
	progress_bar.fill_color = Color(0.95, 0.7, 0.2)
	progress_bar.z_index = 10
	progress_bar.visible = false
	add_child(progress_bar)


func begin_construction():
	placement_preview = false
	under_construction = true
	delivered_wood = 0
	delivered_stone = 0
	build_progress = 0.0
	next_construction_sound_time_msec = 0
	progress_bar.visible = true
	_update_visuals()
	notify_navigation_changed()


func _input_event(_viewport: Node, event: InputEvent, _shape_idx: int):
	if event is not InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		selected_building = self
		Unit.clear_selection()
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		var units := Unit.get_selected_units()
		var network_manager := get_node_or_null("/root/NetworkManager")
		if under_construction:
			if is_instance_valid(network_manager):
				network_manager.request_unit_command(units, &"build", {"building_id": network_id})
		elif is_completed() and (is_factory() or is_residence() or is_barracks()):
			if is_instance_valid(network_manager):
				network_manager.request_unit_command(units, &"enter_building", {"building_id": network_id})
		get_viewport().set_input_as_handled()


func needs_materials() -> bool:
	return under_construction and (delivered_wood < wood_required or delivered_stone < stone_required)


func deliver_material(amount: int) -> int:
	return deliver_resource(&"wood", amount)


func deliver_resource(resource_type: StringName, amount: int) -> int:
	var accepted := 0
	if resource_type == &"stone":
		accepted = mini(amount, stone_required - delivered_stone)
		delivered_stone += accepted
	else:
		accepted = mini(amount, wood_required - delivered_wood)
		delivered_wood += accepted
	_update_visuals()
	return accepted


func get_needed_resource_type() -> StringName:
	if delivered_stone < stone_required:
		return &"stone"
	return &"wood"


func get_remaining_resource(resource_type: StringName) -> int:
	return maxi(stone_required - delivered_stone, 0) if resource_type == &"stone" else maxi(wood_required - delivered_wood, 0)


func add_build_progress(delta: float):
	if not under_construction or needs_materials():
		return
	if delta > 0.0:
		_try_play_construction_sound()
	build_progress = minf(build_progress + delta, build_time)
	_update_visuals()
	if build_progress >= build_time:
		under_construction = false
		building_sprite.modulate.a = 1.0
		progress_bar.visible = false
		notify_navigation_changed()


func _try_play_construction_sound():
	if not lod_active:
		return
	var now_msec := Time.get_ticks_msec()
	if now_msec < next_construction_sound_time_msec:
		return
	if not is_instance_valid(world_audio_pool):
		world_audio_pool = get_tree().get_first_node_in_group("world_audio_pool")
	if not is_instance_valid(world_audio_pool):
		return
	var minimum_pitch := minf(construction_pitch_min, construction_pitch_max)
	var maximum_pitch := maxf(construction_pitch_min, construction_pitch_max)
	world_audio_pool.play_spatial(
		CONSTRUCTION_SOUND,
		global_position,
		construction_sound_max_distance,
		construction_sound_volume_db + randf_range(-1.5, 1.0),
		randf_range(minimum_pitch, maximum_pitch)
	)
	var minimum_interval := minf(construction_sound_interval_min, construction_sound_interval_max)
	var maximum_interval := maxf(construction_sound_interval_min, construction_sound_interval_max)
	next_construction_sound_time_msec = now_msec + int(randf_range(minimum_interval, maximum_interval) * 1000.0)


func notify_navigation_changed():
	if not is_instance_valid(world_navigation):
		world_navigation = get_tree().get_first_node_in_group("world_navigation")
	if is_instance_valid(world_navigation):
		world_navigation.invalidate()


func is_completed() -> bool:
	return not placement_preview and not under_construction


func get_interaction_radius() -> float:
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null and collision.shape is RectangleShape2D:
		return maxf(collision.shape.size.x * absf(global_scale.x), collision.shape.size.y * absf(global_scale.y)) * 0.5 + 10.0
	return 24.0


func get_approach_position(from: Vector2) -> Vector2:
	var direction := global_position.direction_to(from)
	if direction.is_zero_approx():
		direction = Vector2.DOWN
	return global_position + direction * get_interaction_radius()


func get_exit_position(unit: Unit = null) -> Vector2:
	var direction := Vector2.DOWN
	if is_instance_valid(unit):
		var slot := occupants.find(unit)
		direction = Vector2.from_angle(float(maxi(slot, 0)) * 1.7 + PI * 0.5)
	return global_position + direction * (get_interaction_radius() + 12.0)


func contains_world_point(point: Vector2, margin := 0.0) -> bool:
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape is not RectangleShape2D:
		return false
	var local_point := collision.to_local(point)
	var half_size: Vector2 = collision.shape.size * 0.5 + Vector2.ONE * margin
	return absf(local_point.x) <= half_size.x and absf(local_point.y) <= half_size.y


func try_assign_builder(unit: Unit) -> bool:
	if not is_instance_valid(unit) or unit.faction_id != faction_id:
		return false
	_cleanup_builders()
	if unit in active_builders:
		return true
	var builder_limit := 1 if building_kind == "road" else max_builders
	if active_builders.size() >= builder_limit:
		return false
	active_builders.append(unit)
	return true


func release_builder(unit: Unit):
	active_builders.erase(unit)


func _cleanup_builders():
	for index in range(active_builders.size() - 1, -1, -1):
		if not is_instance_valid(active_builders[index]):
			active_builders.remove_at(index)


func is_warehouse() -> bool:
	return building_kind == "warehouse"


func is_factory() -> bool:
	return building_kind in ["factory", "food_factory", "mine", "power_plant", "military_factory", "lumberjack_cabin"]


func is_lumberjack_cabin() -> bool:
	return building_kind == "lumberjack_cabin"


func is_food_factory() -> bool:
	return building_kind == "food_factory"


func is_mine() -> bool:
	return building_kind == "mine"


func is_power_plant() -> bool:
	return building_kind == "power_plant"


func is_military_factory() -> bool:
	return building_kind == "military_factory"


func is_residence() -> bool:
	return building_kind == "residence"


func is_barracks() -> bool:
	return building_kind == "barracks"


func is_government() -> bool:
	return building_kind == "government"


func get_total_stored() -> int:
	var total := 0
	for resource_type in RESOURCE_TYPES:
		total += get_stored_resource(resource_type)
	return total


func get_stored_resource(resource_type: StringName) -> int:
	if resource_type == &"wood":
		return stored_wood
	if resource_type == &"stone":
		return stored_stone
	return int(stored_products.get(resource_type, 0))


func get_storage_limit(resource_type: StringName) -> int:
	return int(storage_limits.get(resource_type, 0))


func get_total_storage_limits() -> int:
	var total := 0
	for resource_type in RESOURCE_TYPES:
		total += get_storage_limit(resource_type)
	return total


func set_storage_limit(resource_type: StringName, amount: int):
	if not is_warehouse() or resource_type not in RESOURCE_TYPES:
		return
	var stored_minimum := get_stored_resource(resource_type)
	var current_limit := get_storage_limit(resource_type)
	var requested_limit := clampi(amount, stored_minimum, storage_capacity)
	if requested_limit <= current_limit:
		storage_limits[resource_type] = requested_limit
		return

	var quota_needed := requested_limit - current_limit
	var unallocated := maxi(storage_capacity - get_total_storage_limits(), 0)
	quota_needed -= mini(quota_needed, unallocated)
	if quota_needed > 0:
		var other_resources: Array[StringName] = []
		for other_type in RESOURCE_TYPES:
			if other_type != resource_type:
				other_resources.append(other_type)
		# Сначала освобождаем самые большие незанятые квоты. Уже лежащие на
		# складе ресурсы никогда не удаляются и их квота не уменьшается ниже запаса.
		other_resources.sort_custom(func(a: StringName, b: StringName):
			return get_storage_limit(a) - get_stored_resource(a) > get_storage_limit(b) - get_stored_resource(b)
		)
		for other_type in other_resources:
			var other_limit := get_storage_limit(other_type)
			var reducible := maxi(other_limit - get_stored_resource(other_type), 0)
			var reduction := mini(reducible, quota_needed)
			storage_limits[other_type] = other_limit - reduction
			quota_needed -= reduction
			if quota_needed <= 0:
				break
	storage_limits[resource_type] = requested_limit - maxi(quota_needed, 0)


func has_storage_space() -> bool:
	if not is_warehouse() or not is_completed() or get_total_stored() >= storage_capacity:
		return false
	for resource_type in RESOURCE_TYPES:
		if has_resource_space(resource_type):
			return true
	return false


func get_resource_space(resource_type: StringName) -> int:
	if not is_warehouse() or not is_completed():
		return 0
	var quota_space := get_storage_limit(resource_type) - get_stored_resource(resource_type)
	var total_space := storage_capacity - get_total_stored()
	return maxi(mini(quota_space, total_space), 0)


func has_resource_space(resource_type: StringName) -> bool:
	return get_resource_space(resource_type) > 0


func can_accept_worker(resource_type: StringName = &"wood") -> bool:
	_cleanup_workers()
	return has_resource_space(resource_type) and assigned_workers.size() < max_workers


func assign_worker(unit: Unit) -> bool:
	if not is_instance_valid(unit) or unit.faction_id != faction_id:
		return false
	_cleanup_workers()
	if unit in assigned_workers:
		return true
	if not has_storage_space() or assigned_workers.size() >= max_workers:
		return false
	assigned_workers.append(unit)
	return true


func release_worker(unit: Unit):
	assigned_workers.erase(unit)


func store_wood(amount: int) -> int:
	return store_resource(&"wood", amount)


func store_resource(resource_type: StringName, amount: int) -> int:
	var accepted := mini(maxi(amount, 0), get_resource_space(resource_type))
	if resource_type == &"wood":
		stored_wood += accepted
	elif resource_type == &"stone":
		stored_stone += accepted
	else:
		stored_products[resource_type] = get_stored_resource(resource_type) + accepted
	return accepted


func has_stored_wood() -> bool:
	return has_stored_resource(&"wood")


func has_stored_resource(resource_type: StringName) -> bool:
	return is_warehouse() and is_completed() and get_stored_resource(resource_type) > 0


func take_wood(amount: int) -> int:
	return take_resource(&"wood", amount)


func take_resource(resource_type: StringName, amount: int) -> int:
	var taken := mini(maxi(amount, 0), get_stored_resource(resource_type))
	if resource_type == &"wood":
		stored_wood -= taken
	elif resource_type == &"stone":
		stored_stone -= taken
	else:
		stored_products[resource_type] = get_stored_resource(resource_type) - taken
	return taken


func get_entry_capacity() -> int:
	return get_worker_target() if is_factory() else max_occupants


func can_reserve_entry(unit: Unit) -> bool:
	_cleanup_occupants()
	_cleanup_entry_reservations()
	if not _can_accept_entry_unit(unit):
		return false
	if unit in occupants or unit in entry_reservations:
		return true
	return occupants.size() + entry_reservations.size() < get_entry_capacity()


func try_reserve_entry(unit: Unit) -> bool:
	if not can_reserve_entry(unit):
		return false
	if unit not in occupants and unit not in entry_reservations:
		entry_reservations.append(unit)
	return true


func release_entry_reservation(unit: Unit):
	entry_reservations.erase(unit)


func has_entry_reservation(unit: Unit) -> bool:
	_cleanup_entry_reservations()
	return unit in entry_reservations


func get_reserved_entry_count(excluded_unit: Unit = null) -> int:
	_cleanup_entry_reservations()
	var result := entry_reservations.size()
	if is_instance_valid(excluded_unit) and excluded_unit in entry_reservations:
		result -= 1
	return maxi(result, 0)


func try_enter(unit: Unit) -> bool:
	_cleanup_occupants()
	_cleanup_entry_reservations()
	if not _can_accept_entry_unit(unit):
		return false
	if unit in occupants:
		release_entry_reservation(unit)
		return true
	var has_reservation := unit in entry_reservations
	var capacity := get_entry_capacity()
	if occupants.size() >= capacity:
		return false
	# An unreserved direct entrant must not steal a slot already promised to a
	# unit that is walking here. Save restoration and migration still work when
	# there are genuinely free, unreserved places.
	if not has_reservation and occupants.size() + entry_reservations.size() >= capacity:
		return false
	release_entry_reservation(unit)
	occupants.append(unit)
	return true


func _can_accept_entry_unit(unit: Unit) -> bool:
	if not is_instance_valid(unit) or unit.faction_id != faction_id or placement_preview or not is_completed() or (not is_factory() and not is_residence() and not is_barracks()):
		return false
	if is_barracks() and not unit.is_mobilized:
		return false
	if is_residence() and unit.is_mobilized:
		return false
	return true


func leave(unit: Unit):
	occupants.erase(unit)
	release_entry_reservation(unit)


func get_worker_target() -> int:
	return clampi(desired_workers, 0, max_workers) if is_factory() else 0


func set_worker_target(value: int):
	if not is_factory():
		return
	desired_workers = clampi(value, 0, max_workers)
	while occupants.size() > desired_workers:
		var unit: Unit = occupants.back()
		if is_instance_valid(unit):
			unit.force_exit_building(self)
		else:
			occupants.pop_back()
	_cleanup_entry_reservations()


func get_recipe() -> Dictionary:
	var available_recipes := get_available_recipe_types()
	var fallback: StringName = available_recipes[0] if not available_recipes.is_empty() else &"planks"
	return FACTORY_RECIPES.get(selected_recipe, FACTORY_RECIPES[fallback])


func get_available_recipe_types() -> Array[StringName]:
	if is_lumberjack_cabin():
		return FORESTRY_RECIPES
	if is_food_factory():
		return FOOD_RECIPES
	if is_mine():
		return MINE_RECIPES
	if is_power_plant():
		return POWER_PLANT_RECIPES
	if is_military_factory():
		return MILITARY_FACTORY_RECIPES
	return INDUSTRIAL_RECIPES


func get_recipe_name(recipe_type: StringName) -> String:
	var recipe: Dictionary = FACTORY_RECIPES.get(recipe_type, {})
	return str(recipe.get("name", "Нет рецепта"))


func get_production_time() -> float:
	return float(get_recipe().get("time", 2.0))


func set_recipe(recipe_type: StringName):
	if FACTORY_RECIPES.has(recipe_type) and recipe_type in get_available_recipe_types():
		selected_recipe = recipe_type


func can_be_edited_locally() -> bool:
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		return network_manager.can_edit_faction(faction_id)
	return faction_id == 0


func can_produce_selected_recipe() -> bool:
	if not is_factory() or not is_completed():
		return false
	var recipe := get_recipe()
	for output in _get_recipe_outputs(recipe):
		if _get_output_space(output) < int(_get_recipe_outputs(recipe)[output]):
			return false
	if requires_electricity() and get_network_electricity_amount() < FACTORY_ELECTRICITY_PER_CYCLE:
		return false
	var inputs: Dictionary = recipe["inputs"]
	for resource_type in inputs:
		if _get_network_amount(resource_type) < int(inputs[resource_type]):
			return false
	return true


func get_factory_status_text() -> String:
	if not is_factory():
		return ""
	if not is_completed():
		return "Производство начнётся после завершения строительства."
	if get_worker_target() == 0:
		return "Остановлено: для этого здания задано 0 работников."
	var recipe := get_recipe()
	var outputs := _get_recipe_outputs(recipe)
	for output in outputs:
		if _get_output_space(output) < int(outputs[output]):
			if output == &"electricity":
				return "Остановлено: запас электричества заполнен (%d/%d)." % [stored_electricity, electricity_capacity]
			return "Остановлено: на складах нет места по квоте «%s»." % RESOURCE_NAMES.get(output, str(output))
	if requires_electricity() and get_network_electricity_amount() < FACTORY_ELECTRICITY_PER_CYCLE:
		return "Остановлено: в энергосети нет электричества."
	var inputs: Dictionary = recipe["inputs"]
	for resource_type in inputs:
		var required := int(inputs[resource_type])
		var available := _get_network_amount(resource_type)
		if available < required:
			return "Остановлено: не хватает ресурса «%s» (%d/%d)." % [RESOURCE_NAMES.get(resource_type, str(resource_type)), available, required]
	if occupants.is_empty():
		return "Ожидает рабочих: сырьё и место для продукции доступны."
	if is_power_plant():
		return "Электростанция работает. Запас: %d/%d." % [stored_electricity, electricity_capacity]
	return "Производство работает: сырьё и место для продукции доступны."


func produce_selected_recipe() -> bool:
	if not can_produce_selected_recipe():
		return false
	var recipe := get_recipe()
	if requires_electricity():
		_take_electricity_from_network(FACTORY_ELECTRICITY_PER_CYCLE)
	var inputs: Dictionary = recipe["inputs"]
	for resource_type in inputs:
		_take_from_network(resource_type, int(inputs[resource_type]))
	var produced_everything := true
	var outputs := _get_recipe_outputs(recipe)
	for output in outputs:
		var remaining := int(outputs[output])
		if output == &"electricity" and is_power_plant():
			var accepted := mini(remaining, maxi(electricity_capacity - stored_electricity, 0))
			stored_electricity += accepted
			remaining -= accepted
		else:
			for warehouse in _get_warehouses():
				remaining -= warehouse.store_resource(output, remaining)
				if remaining <= 0:
					break
		produced_everything = produced_everything and remaining <= 0
	return produced_everything


func _get_recipe_outputs(recipe: Dictionary) -> Dictionary:
	if recipe.has("outputs"):
		return recipe["outputs"]
	return {StringName(recipe.get("output", &"planks")): int(recipe.get("amount", 1))}


func _get_output_space(resource_type: StringName) -> int:
	if resource_type == &"electricity" and is_power_plant():
		return maxi(electricity_capacity - stored_electricity, 0)
	return _get_network_space(resource_type)


func take_electricity(amount: int) -> int:
	var taken := mini(maxi(amount, 0), stored_electricity)
	stored_electricity -= taken
	return taken


func requires_electricity() -> bool:
	# Шахта остаётся доступным источником первого угля, иначе новая экономика
	# попадает в цикл «для угля нужна энергия, для энергии нужен уголь».
	return is_factory() and not is_power_plant() and not is_mine() and not is_lumberjack_cabin()


func get_network_electricity_amount() -> int:
	var total := 0
	for building in _get_indexed_buildings("power_plant"):
		if building is Building and building.faction_id == faction_id and building.is_power_plant() and building.is_completed():
			total += building.stored_electricity
	return total


func get_factory_issues() -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if not is_factory() or not is_completed() or get_worker_target() <= 0:
		return issues
	if occupants.is_empty():
		issues.append({"kind": &"no_workers"})
	if requires_electricity() and get_network_electricity_amount() < FACTORY_ELECTRICITY_PER_CYCLE:
		issues.append({"kind": &"no_electricity"})
	var recipe := get_recipe()
	var outputs := _get_recipe_outputs(recipe)
	for output in outputs:
		if _get_output_space(output) < int(outputs[output]):
			# Заполненный внутренний аккумулятор электростанции — штатная пауза,
			# а не проблема, требующая постоянного предупреждения.
			if output != &"electricity":
				issues.append({"kind": &"output_full", "resource": output})
	var inputs: Dictionary = recipe["inputs"]
	for resource_type in inputs:
		if _get_network_amount(resource_type) < int(inputs[resource_type]):
			issues.append({"kind": &"missing_input", "resource": resource_type})
	return issues


func _take_electricity_from_network(amount: int) -> int:
	var remaining := maxi(amount, 0)
	for building in _get_indexed_buildings("power_plant"):
		if building is not Building or building.faction_id != faction_id or not building.is_power_plant() or not building.is_completed():
			continue
		remaining -= building.take_electricity(remaining)
		if remaining <= 0:
			break
	return amount - remaining


func _get_warehouses() -> Array[Building]:
	var warehouses: Array[Building] = []
	for building in _get_indexed_buildings("warehouse"):
		if building is Building and building.faction_id == faction_id and building.is_warehouse() and building.is_completed():
			warehouses.append(building)
	warehouses.sort_custom(func(a: Building, b: Building): return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	return warehouses


func _get_indexed_buildings(kind := "") -> Array:
	if not is_instance_valid(world_index):
		world_index = get_tree().get_first_node_in_group("world_index")
	if is_instance_valid(world_index):
		return world_index.get_buildings(faction_id, kind)
	var result: Array[Building] = []
	for candidate in get_tree().get_nodes_in_group("buildings"):
		if candidate is Building and candidate.faction_id == faction_id and (kind.is_empty() or candidate.building_kind == kind):
			result.append(candidate)
	return result


func _get_network_amount(resource_type: StringName) -> int:
	var total := 0
	for warehouse in _get_warehouses():
		total += warehouse.get_stored_resource(resource_type)
	return total


func _get_network_space(resource_type: StringName) -> int:
	var total := 0
	for warehouse in _get_warehouses():
		total += warehouse.get_resource_space(resource_type)
	return total


func _take_from_network(resource_type: StringName, amount: int):
	var remaining := amount
	for warehouse in _get_warehouses():
		remaining -= warehouse.take_resource(resource_type, remaining)
		if remaining <= 0:
			return


func _cleanup_workers():
	for index in range(assigned_workers.size() - 1, -1, -1):
		if not is_instance_valid(assigned_workers[index]):
			assigned_workers.remove_at(index)


func _cleanup_occupants():
	for index in range(occupants.size() - 1, -1, -1):
		if not is_instance_valid(occupants[index]):
			occupants.remove_at(index)


func _cleanup_entry_reservations():
	for index in range(entry_reservations.size() - 1, -1, -1):
		var unit := entry_reservations[index]
		if not is_instance_valid(unit) or unit.is_queued_for_deletion() or unit.task != Unit.Task.ENTER_BUILDING or unit.target_building != self or is_instance_valid(unit.inside_building):
			entry_reservations.remove_at(index)
	var available_slots := maxi(get_entry_capacity() - occupants.size(), 0)
	while entry_reservations.size() > available_slots:
		entry_reservations.pop_back()


func _update_visuals():
	var total_required := wood_required + stone_required
	var material_ratio := 1.0 if total_required <= 0 else float(delivered_wood + delivered_stone) / total_required
	var work_ratio := 1.0 if build_time <= 0.0 else build_progress / build_time
	var total_progress := material_ratio * 0.5 + work_ratio * 0.5
	progress_bar.value = total_progress * 100.0
	if under_construction:
		# Прозрачный силуэт постепенно становится плотнее по мере доставки
		# материалов и выполнения строительных работ.
		building_sprite.modulate.a = lerpf(0.35, 0.9, clampf(total_progress, 0.0, 1.0))
