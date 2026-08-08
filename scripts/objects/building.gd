class_name Building
extends Area2D

@export var display_name := "Здание"
@export var building_kind := "residence"
@export var wood_required := 10
@export var stone_required := 0
@export var build_time := 5.0
@export var storage_capacity := 0
@export var max_workers := 0

var delivered_wood := 0
var delivered_stone := 0
var build_progress := 0.0
var stored_wood := 0
var stored_stone := 0
var under_construction := false
var assigned_workers: Array[Unit] = []
var progress_bar: WorldProgressBar
var address := ""
var address_label: Label

@onready var building_sprite: Sprite2D = $Sprite2D


func _ready():
	add_to_group("buildings")
	_create_progress_bar()
	_create_address_label()


func _create_address_label():
	address_label = Label.new()
	address_label.position = Vector2(-55, -38)
	address_label.scale = Vector2(0.7, 0.7)
	address_label.z_index = 20
	address_label.visible = false
	add_child(address_label)
	mouse_entered.connect(func(): address_label.visible = not address.is_empty())
	mouse_exited.connect(func(): address_label.visible = false)


func set_address(street_name: String, house_number: int):
	address = "%s — %s, %d" % [display_name, street_name, house_number]
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
	under_construction = true
	delivered_wood = 0
	delivered_stone = 0
	build_progress = 0.0
	progress_bar.visible = true
	_update_visuals()


func _input_event(_viewport: Node, event: InputEvent, _shape_idx: int):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and under_construction:
		var unit := Unit.get_selected_unit()
		if is_instance_valid(unit):
			unit.command_build(self)
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
	build_progress = minf(build_progress + delta, build_time)
	_update_visuals()
	if build_progress >= build_time:
		under_construction = false
		building_sprite.modulate.a = 1.0
		progress_bar.visible = false


func is_completed() -> bool:
	return not under_construction


func is_warehouse() -> bool:
	return building_kind == "warehouse"


func has_storage_space() -> bool:
	return is_warehouse() and is_completed() and (stored_wood < storage_capacity or stored_stone < storage_capacity)


func has_resource_space(resource_type: StringName) -> bool:
	if not is_warehouse() or not is_completed():
		return false
	return stored_stone < storage_capacity if resource_type == &"stone" else stored_wood < storage_capacity


func can_accept_worker(resource_type: StringName = &"wood") -> bool:
	_cleanup_workers()
	return has_resource_space(resource_type) and assigned_workers.size() < max_workers


func assign_worker(unit: Unit) -> bool:
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
	var accepted := mini(amount, storage_capacity - stored_wood)
	stored_wood += accepted
	return accepted


func store_resource(resource_type: StringName, amount: int) -> int:
	if resource_type == &"stone":
		var accepted := mini(amount, storage_capacity - stored_stone)
		stored_stone += accepted
		return accepted
	return store_wood(amount)


func has_stored_wood() -> bool:
	return is_warehouse() and is_completed() and stored_wood > 0


func has_stored_resource(resource_type: StringName) -> bool:
	return is_warehouse() and is_completed() and (stored_stone > 0 if resource_type == &"stone" else stored_wood > 0)


func take_wood(amount: int) -> int:
	var taken := mini(amount, stored_wood)
	stored_wood -= taken
	return taken


func take_resource(resource_type: StringName, amount: int) -> int:
	if resource_type == &"stone":
		var taken := mini(amount, stored_stone)
		stored_stone -= taken
		return taken
	return take_wood(amount)


func _cleanup_workers():
	for index in range(assigned_workers.size() - 1, -1, -1):
		if not is_instance_valid(assigned_workers[index]):
			assigned_workers.remove_at(index)


func _update_visuals():
	var total_required := wood_required + stone_required
	var material_ratio := 1.0 if total_required <= 0 else float(delivered_wood + delivered_stone) / total_required
	var work_ratio := 1.0 if build_time <= 0.0 else build_progress / build_time
	progress_bar.value = material_ratio * 50.0 + work_ratio * 50.0
	building_sprite.modulate.a = lerpf(0.5, 1.0, work_ratio)
