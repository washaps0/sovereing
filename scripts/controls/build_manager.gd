extends CanvasLayer

const RESIDENCE_SCENE := preload("res://scenes/objects/buildings/residence.tscn")
const WAREHOUSE_SCENE := preload("res://scenes/objects/buildings/warehouse.tscn")
const ROAD_SCENE := preload("res://scenes/objects/buildings/road.tscn")
const STREET_NAMES: Array[String] = [
	"Садовая", "Лесная", "Полевая", "Речная", "Озёрная",
	"Центральная", "Северная", "Южная", "Восточная", "Западная",
	"Берёзовая", "Сосновая", "Кленовая", "Липовая", "Дубовая",
	"Зелёная", "Солнечная", "Лунная", "Звёздная", "Тихая",
	"Широкая", "Дальняя", "Новая", "Старая", "Мирная",
	"Мельничная", "Рыночная", "Кузнечная", "Почтовая", "Замковая",
	"Горная", "Луговая", "Степная", "Прибрежная", "Ремесленная"
]

var menu: PanelContainer
var ghost: Building
var selected_scene: PackedScene
var placement_valid := false
var snapped_road: RoadSegment
var unit_status: Label
var resource_status: Label
var mode_button: Button
var street_input: LineEdit
var road_mode := false
var road_start: Variant = null
var road_start_segment: RoadSegment
var road_preview: Line2D
var street_counter := 1
var used_street_names := {}
var house_numbers := {}
var naming_rng := RandomNumberGenerator.new()

@onready var world: Node2D = get_parent()
@onready var buildings: Node2D = world.get_node("buildings")
@onready var roads: Node2D = world.get_node("roads")


func _ready():
	naming_rng.randomize()
	_create_interface()


func _panel(position: Vector2, minimum_size: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = position
	panel.custom_minimum_size = minimum_size
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	return box


func _create_interface():
	var controls_box := _panel(Vector2(16, 16), Vector2(360, 0))
	var controls := Label.new()
	controls.text = "ЛКМ: выбор | ПКМ: приказ | B: стройка | R: добыча"
	controls_box.add_child(controls)

	var unit_box := _panel(Vector2(16, 58), Vector2(250, 0))
	unit_status = Label.new()
	unit_status.text = "Юнит не выбран"
	unit_box.add_child(unit_status)

	var resource_panel := PanelContainer.new()
	resource_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	resource_panel.position = Vector2(-270, 16)
	resource_panel.custom_minimum_size = Vector2(250, 0)
	add_child(resource_panel)
	var resource_box := VBoxContainer.new()
	resource_panel.add_child(resource_box)
	resource_status = Label.new()
	resource_box.add_child(resource_status)
	mode_button = Button.new()
	mode_button.pressed.connect(_toggle_harvest_mode)
	resource_box.add_child(mode_button)
	_update_mode_button()

	menu = PanelContainer.new()
	menu.position = Vector2(16, 105)
	menu.visible = false
	add_child(menu)
	var build_box := VBoxContainer.new()
	menu.add_child(build_box)
	var title := Label.new()
	title.text = "Строительство"
	build_box.add_child(title)
	_add_build_button(build_box, "Жилой дом — 10 дерева", RESIDENCE_SCENE)
	_add_build_button(build_box, "Склад — 15 дерева", WAREHOUSE_SCENE)
	street_input = LineEdit.new()
	street_input.placeholder_text = "Название улицы (пусто = автоматически)"
	build_box.add_child(street_input)
	var road_button := Button.new()
	road_button.text = "Построить дорогу линией"
	road_button.pressed.connect(_begin_road_mode)
	build_box.add_child(road_button)


func _add_build_button(box: VBoxContainer, text: String, scene: PackedScene):
	var button := Button.new()
	button.text = text
	button.pressed.connect(_begin_building_placement.bind(scene))
	box.add_child(button)


func _process(_delta: float):
	if is_instance_valid(ghost):
		_snap_building_to_road(world.get_global_mouse_position())
		_update_placement_validity()
	if road_mode and road_start != null and is_instance_valid(road_preview):
		road_preview.points = PackedVector2Array([road_start, _snap_road_axis(road_start, world.get_global_mouse_position())])
	_update_hud()


func _update_hud():
	var unit := Unit.get_selected_unit()
	if is_instance_valid(unit):
		unit_status.text = "%s | дерево %d, камень %d | груз %d/%d" % [unit.get_task_text(), unit.carried_wood, unit.carried_stone, unit.get_carried_total(), unit.carry_capacity]
	else:
		unit_status.text = "Юнит не выбран"
	var wood := 0
	var stone := 0
	var workers := 0
	for building in get_tree().get_nodes_in_group("buildings"):
		if building is Building and building.is_warehouse() and building.is_completed():
			wood += building.stored_wood
			stone += building.stored_stone
			workers += building.assigned_workers.size()
	resource_status.text = "Ресурсы\nДерево: %d   Камень: %d\nРабочие на добыче: %d" % [wood, stone, workers]


func _input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_toggle_harvest_mode()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_B:
			_cancel_all_placement()
			menu.visible = not menu.visible
			get_viewport().set_input_as_handled()
			return

	if event is not InputEventMouseButton or not event.pressed:
		return
	if road_mode:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_road_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_road_mode()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(ghost):
		if event.button_index == MOUSE_BUTTON_LEFT:
			_place_building()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_building_placement()
		get_viewport().set_input_as_handled()


func _toggle_harvest_mode():
	Unit.continuous_harvest_mode = not Unit.continuous_harvest_mode
	_update_mode_button()


func _update_mode_button():
	mode_button.text = "Добыча ИИ: ВКЛ (R)" if Unit.continuous_harvest_mode else "Добыча ИИ: ВЫКЛ (R)"


func _begin_building_placement(scene: PackedScene):
	_cancel_all_placement()
	selected_scene = scene
	ghost = scene.instantiate() as Building
	ghost.collision_layer = 0
	ghost.collision_mask = 0
	ghost.monitoring = false
	ghost.monitorable = false
	buildings.add_child(ghost)
	menu.visible = false


func _snap_building_to_road(mouse_position: Vector2):
	snapped_road = _nearest_road(mouse_position, 100.0)
	if not is_instance_valid(snapped_road):
		ghost.global_position = mouse_position
		return
	var direction: Vector2 = Vector2.RIGHT.rotated(snapped_road.rotation)
	var perpendicular := Vector2(-direction.y, direction.x)
	var along: float = clampf((mouse_position - snapped_road.global_position).dot(direction), -RoadSegment.SEGMENT_LENGTH * 0.5, RoadSegment.SEGMENT_LENGTH * 0.5)
	var side := signf((mouse_position - snapped_road.global_position).dot(perpendicular))
	if side == 0.0:
		side = 1.0
	ghost.global_position = snapped_road.global_position + direction * along + perpendicular * 40.0 * side


func _update_placement_validity():
	placement_valid = is_instance_valid(snapped_road)
	var collision := ghost.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if placement_valid and collision != null and collision.shape != null:
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = collision.shape
		query.transform = collision.global_transform
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.collision_mask = 1
		var hits := world.get_world_2d().direct_space_state.intersect_shape(query, 32)
		for hit in hits:
			if hit.collider is Building:
				placement_valid = false
				break
	ghost.modulate = Color(1, 1, 1, 0.5) if placement_valid else Color(1, 0.25, 0.25, 0.65)


func _place_building():
	if not placement_valid or not is_instance_valid(snapped_road):
		return
	ghost.modulate = Color.WHITE
	ghost.collision_layer = 1
	ghost.collision_mask = 1
	ghost.monitoring = true
	ghost.monitorable = true
	var street := snapped_road.street_name
	var number: int = house_numbers.get(street, 0) + 1
	house_numbers[street] = number
	ghost.set_address(street, number)
	_clear_resources_for_shape(ghost.get_node("CollisionShape2D"))
	ghost.begin_construction()
	var builder := Unit.get_selected_unit()
	if is_instance_valid(builder):
		builder.command_build(ghost)
	ghost = null
	selected_scene = null


func _begin_road_mode():
	_cancel_all_placement()
	road_mode = true
	menu.visible = false
	road_preview = Line2D.new()
	road_preview.width = 3.0
	road_preview.default_color = Color(0.95, 0.8, 0.2, 0.8)
	road_preview.z_index = 30
	roads.add_child(road_preview)


func _handle_road_click():
	var point := world.get_global_mouse_position()
	if road_start == null:
		var snap := _nearest_road_endpoint(point, 40.0)
		if not snap.is_empty():
			road_start = snap.position
			road_start_segment = snap.road
		else:
			road_start = point
			road_start_segment = null
		return
	_create_road_line(road_start, _snap_road_axis(road_start, point))
	road_start = null
	road_start_segment = null
	road_preview.clear_points()


func _create_road_line(start: Vector2, end: Vector2):
	var street := _road_name_for_start(start)
	var delta := end - start
	if delta.length() < 8.0:
		return
	var direction := delta.normalized()
	var angle := direction.angle()
	var count := maxi(1, int(ceil(delta.length() / RoadSegment.SEGMENT_LENGTH)))
	var segments: Array[Building] = []
	for i in range(count):
		var position := start + direction * (RoadSegment.SEGMENT_LENGTH * (i + 0.5))
		var segment := ROAD_SCENE.instantiate() as RoadSegment
		segment.position = position
		roads.add_child(segment)
		segment.setup(street, angle)
		_clear_resources_for_shape(segment.get_node("CollisionShape2D"))
		segment.begin_construction()
		segments.append(segment)
	var builder := Unit.get_selected_unit()
	if is_instance_valid(builder):
		builder.command_build_line(segments)


func _road_name_for_start(start: Vector2) -> String:
	var typed := street_input.text.strip_edges()
	if typed.is_empty() and is_instance_valid(road_start_segment):
		return road_start_segment.street_name
	if typed.is_empty():
		typed = _generate_street_name()
	var base := typed
	var suffix := 2
	while used_street_names.has(typed):
		typed = "%s %d" % [base, suffix]
		suffix += 1
	used_street_names[typed] = true
	street_input.text = ""
	return typed


func _generate_street_name() -> String:
	var available: Array[String] = []
	for street_name in STREET_NAMES:
		if not used_street_names.has(street_name):
			available.append(street_name)
	if not available.is_empty():
		return available[naming_rng.randi_range(0, available.size() - 1)]

	# После одиночных названий перебираем случайные уникальные пары.
	var first_offset := naming_rng.randi_range(0, STREET_NAMES.size() - 1)
	var second_offset := naming_rng.randi_range(0, STREET_NAMES.size() - 1)
	for first_index in range(STREET_NAMES.size()):
		for second_index in range(STREET_NAMES.size()):
			var first := STREET_NAMES[(first_index + first_offset) % STREET_NAMES.size()]
			var second := STREET_NAMES[(second_index + second_offset) % STREET_NAMES.size()]
			var combined := "%s-%s" % [first, second]
			if not used_street_names.has(combined):
				return combined

	# Практически недостижимый резерв после исчерпания всех комбинаций.
	var fallback := "%s-%s-%d" % [STREET_NAMES[0], STREET_NAMES[1], street_counter]
	street_counter += 1
	return fallback


func _nearest_road(point: Vector2, max_distance: float) -> RoadSegment:
	var nearest: RoadSegment
	var best := max_distance * max_distance
	for road in get_tree().get_nodes_in_group("roads"):
		if road.under_construction:
			continue
		var direction: Vector2 = Vector2.RIGHT.rotated(road.rotation)
		var along: float = clampf((point - road.global_position).dot(direction), -RoadSegment.SEGMENT_LENGTH * 0.5, RoadSegment.SEGMENT_LENGTH * 0.5)
		var closest: Vector2 = road.global_position + direction * along
		var distance := point.distance_squared_to(closest)
		if distance <= best:
			best = distance
			nearest = road
	return nearest


func _nearest_road_endpoint(point: Vector2, max_distance: float) -> Dictionary:
	var result := {}
	var best := max_distance * max_distance
	for road in get_tree().get_nodes_in_group("roads"):
		if road.under_construction:
			continue
		var direction: Vector2 = Vector2.RIGHT.rotated(road.rotation)
		var along: float = clampf((point - road.global_position).dot(direction), -RoadSegment.SEGMENT_LENGTH * 0.5, RoadSegment.SEGMENT_LENGTH * 0.5)
		var connection: Vector2 = road.global_position + direction * along
		var distance := point.distance_squared_to(connection)
		if distance <= best:
			best = distance
			result = {"position": connection, "road": road}
	return result


func _snap_road_axis(start: Vector2, point: Vector2) -> Vector2:
	var delta := point - start
	if absf(delta.y) <= absf(delta.x) * 0.22:
		return Vector2(point.x, start.y)
	if absf(delta.x) <= absf(delta.y) * 0.22:
		return Vector2(start.x, point.y)
	return point


func _clear_resources_for_shape(collision: CollisionShape2D):
	if collision == null or collision.shape == null:
		return
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision.shape
	query.transform = collision.global_transform
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 1
	for hit in world.get_world_2d().direct_space_state.intersect_shape(query, 64):
		var collider = hit.collider
		if collider is Node and collider.is_in_group("resources"):
			collider.queue_free()


func _cancel_building_placement():
	if is_instance_valid(ghost):
		ghost.queue_free()
	ghost = null
	selected_scene = null


func _cancel_road_mode():
	road_mode = false
	road_start = null
	road_start_segment = null
	if is_instance_valid(road_preview):
		road_preview.queue_free()
	road_preview = null


func _cancel_all_placement():
	_cancel_building_placement()
	_cancel_road_mode()
