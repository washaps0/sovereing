extends CanvasLayer

const RESIDENCE_SCENE := preload("res://scenes/objects/buildings/residence.tscn")
const WAREHOUSE_SCENE := preload("res://scenes/objects/buildings/warehouse.tscn")
const FACTORY_SCENE := preload("res://scenes/objects/buildings/fabric.tscn")
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
var auto_work_button: Button
var street_input: LineEdit
var road_mode := false
var road_start: Variant = null
var road_start_segment: RoadSegment
var road_preview: Line2D
var street_counter := 1
var used_street_names := {}
var house_numbers := {}
var naming_rng := RandomNumberGenerator.new()
var tactical_overlay: TacticalOverlay
var selecting := false
var selection_start := Vector2.ZERO
var selection_additive := false
var forming := false
var formation_start := Vector2.ZERO
var building_panel: PanelContainer
var building_title: Label
var building_status: Label
var warehouse_settings: VBoxContainer
var factory_settings: VBoxContainer
var factory_diagnostic: Label
var residents_settings: VBoxContainer
var residents_list: VBoxContainer
var quota_spins := {}
var recipe_picker: OptionButton
var release_occupants_button: Button
var updating_building_controls := false
var residents_list_key := ""
var building_rotation_offset := 0.0

@onready var world: Node2D = get_parent()
@onready var buildings: Node2D = world.get_node("buildings")
@onready var roads: Node2D = world.get_node("roads")


func _ready():
	naming_rng.randomize()
	tactical_overlay = TacticalOverlay.new()
	tactical_overlay.z_index = 100
	world.add_child.call_deferred(tactical_overlay)
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
	controls.text = "ЛКМ: выбор/меню здания | ПКМ: приказ | B: стройка | Q/E: поворот | R: добыча"
	controls_box.add_child(controls)

	var unit_box := _panel(Vector2(16, 58), Vector2(300, 0))
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
	auto_work_button = Button.new()
	auto_work_button.pressed.connect(_toggle_auto_work)
	resource_box.add_child(auto_work_button)
	_update_auto_work_button()

	menu = PanelContainer.new()
	menu.position = Vector2(16, 220)
	menu.visible = false
	add_child(menu)
	var build_box := VBoxContainer.new()
	menu.add_child(build_box)
	var title := Label.new()
	title.text = "Строительство"
	build_box.add_child(title)
	_add_build_button(build_box, "Жилой дом — 10 дерева", RESIDENCE_SCENE)
	_add_build_button(build_box, "Склад — 15 дерева", WAREHOUSE_SCENE)
	_add_build_button(build_box, "Завод — 25 дерева, 10 камня", FACTORY_SCENE)
	street_input = LineEdit.new()
	street_input.placeholder_text = "Название улицы (пусто = автоматически)"
	build_box.add_child(street_input)
	var road_button := Button.new()
	road_button.text = "Построить дорогу линией"
	road_button.pressed.connect(_begin_road_mode)
	build_box.add_child(road_button)
	_create_building_panel()


func _create_building_panel():
	building_panel = PanelContainer.new()
	building_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	building_panel.position = Vector2(-315, 190)
	building_panel.custom_minimum_size = Vector2(295, 0)
	building_panel.visible = false
	add_child(building_panel)
	var box := VBoxContainer.new()
	building_panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	building_title = Label.new()
	building_title.add_theme_font_size_override("font_size", 18)
	building_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(building_title)
	var close_button := Button.new()
	close_button.text = "✕"
	close_button.tooltip_text = "Закрыть меню здания"
	close_button.pressed.connect(_close_building_menu)
	header.add_child(close_button)
	building_status = Label.new()
	box.add_child(building_status)
	residents_settings = VBoxContainer.new()
	box.add_child(residents_settings)
	var residents_title := Label.new()
	residents_title.text = "Жильцы (нажмите для выбора):"
	residents_settings.add_child(residents_title)
	residents_list = VBoxContainer.new()
	residents_settings.add_child(residents_list)

	warehouse_settings = VBoxContainer.new()
	box.add_child(warehouse_settings)
	var quota_hint := Label.new()
	quota_hint.text = "Квоты хранения (всего не более 300)"
	warehouse_settings.add_child(quota_hint)
	for resource_type in Building.RESOURCE_TYPES:
		var row := HBoxContainer.new()
		warehouse_settings.add_child(row)
		var label := Label.new()
		label.text = Building.RESOURCE_NAMES[resource_type]
		label.custom_minimum_size.x = 125
		row.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 300
		spin.step = 5
		spin.custom_minimum_size.x = 110
		spin.value_changed.connect(_on_storage_quota_changed.bind(resource_type))
		row.add_child(spin)
		quota_spins[resource_type] = spin

	factory_settings = VBoxContainer.new()
	box.add_child(factory_settings)
	var recipe_label := Label.new()
	recipe_label.text = "Производить:"
	factory_settings.add_child(recipe_label)
	recipe_picker = OptionButton.new()
	for recipe_type in Building.FACTORY_RECIPES:
		recipe_picker.add_item(Building.FACTORY_RECIPES[recipe_type]["name"])
		recipe_picker.set_item_metadata(recipe_picker.item_count - 1, recipe_type)
	recipe_picker.item_selected.connect(_on_recipe_selected)
	factory_settings.add_child(recipe_picker)
	var recipes_hint := Label.new()
	recipes_hint.text = "Доски: 2 дерева\nИнструменты: 1 дерево + 2 камня"
	factory_settings.add_child(recipes_hint)
	factory_diagnostic = Label.new()
	factory_diagnostic.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	factory_diagnostic.custom_minimum_size.x = 270
	factory_settings.add_child(factory_diagnostic)
	release_occupants_button = Button.new()
	release_occupants_button.text = "Выпустить всех юнитов"
	release_occupants_button.pressed.connect(_release_selected_building_occupants)
	box.add_child(release_occupants_button)


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
	if selecting:
		tactical_overlay.show_selection(selection_start, world.get_global_mouse_position())
	if forming:
		tactical_overlay.show_formation(_get_formation_positions(formation_start, world.get_global_mouse_position()))
	_update_hud()


func _update_hud():
	var unit := Unit.get_selected_unit()
	if is_instance_valid(unit):
		unit_status.text = "Имя: %s\nЗдоровье: %d/%d\nПрофессия: %s\nСейчас: %s\nГруз: дерево %d, камень %d (%d/%d)\nПроизведено предметов: %d" % [unit.unit_name, unit.health, unit.max_health, unit.get_profession_text(), unit.get_task_text(), unit.carried_wood, unit.carried_stone, unit.get_carried_total(), unit.carry_capacity, unit.produced_items]
	else:
		unit_status.text = "Юнит не выбран"
	var wood := 0
	var stone := 0
	var planks := 0
	var tools := 0
	var total_capacity := 0
	var workers := 0
	var factory_workers := 0
	for building in get_tree().get_nodes_in_group("buildings"):
		if building is Building and building.is_warehouse() and building.is_completed():
			wood += building.stored_wood
			stone += building.stored_stone
			planks += building.get_stored_resource(&"planks")
			tools += building.get_stored_resource(&"tools")
			total_capacity += building.storage_capacity
			workers += building.assigned_workers.size()
		elif building is Building and building.is_factory() and building.is_completed():
			factory_workers += building.occupants.size()
	resource_status.text = "Ресурсы: %d/%d\nДерево %d | Камень %d\nДоски %d | Инструменты %d\nДобыча %d | Заводы %d" % [wood + stone + planks + tools, total_capacity, wood, stone, planks, tools, workers, factory_workers]
	_update_building_panel()


func _update_building_panel():
	var building := Building.selected_building
	if not is_instance_valid(building):
		building_panel.visible = false
		return
	building_panel.visible = true
	building_title.text = building.address if not building.address.is_empty() else building.display_name
	if building.under_construction:
		building_status.text = "Строится: дерево %d/%d, камень %d/%d" % [building.delivered_wood, building.wood_required, building.delivered_stone, building.stone_required]
	else:
		building_status.text = "Готово"
	warehouse_settings.visible = building.is_warehouse() and building.is_completed()
	factory_settings.visible = building.is_factory() and building.is_completed()
	residents_settings.visible = building.is_residence() and building.is_completed()
	release_occupants_button.visible = building.is_completed() and (building.is_factory() or building.is_residence())
	release_occupants_button.disabled = building.occupants.is_empty()
	if warehouse_settings.visible:
		building_status.text = "Занято %d/300" % building.get_total_stored()
		updating_building_controls = true
		for resource_type in Building.RESOURCE_TYPES:
			var spin: SpinBox = quota_spins[resource_type]
			if not spin.get_line_edit().has_focus():
				spin.value = building.get_storage_limit(resource_type)
			spin.suffix = " (есть %d)" % building.get_stored_resource(resource_type)
		updating_building_controls = false
	elif factory_settings.visible:
		building_status.text = "Работают %d/%d | рецепт: %s" % [building.occupants.size(), building.max_workers, building.get_recipe_name(building.selected_recipe)]
		factory_diagnostic.text = building.get_factory_status_text()
		updating_building_controls = true
		for index in range(recipe_picker.item_count):
			if StringName(recipe_picker.get_item_metadata(index)) == building.selected_recipe:
				recipe_picker.select(index)
				break
		updating_building_controls = false
	elif building.is_residence() and building.is_completed():
		building_status.text = "Жильцы %d/%d" % [building.occupants.size(), building.max_occupants]
		_update_residents_list(building)


func _update_residents_list(building: Building):
	var new_key := str(building.get_instance_id())
	for unit in building.occupants:
		if is_instance_valid(unit):
			new_key += ":%d:%d:%d" % [unit.get_instance_id(), unit.health, unit.task]
	if new_key == residents_list_key:
		return
	residents_list_key = new_key
	for child in residents_list.get_children():
		child.queue_free()
	if building.occupants.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Дом пока пуст"
		residents_list.add_child(empty_label)
		return
	for unit in building.occupants:
		if not is_instance_valid(unit):
			continue
		var resident_button := Button.new()
		resident_button.text = "%s — %s, здоровье %d/%d" % [unit.unit_name, unit.get_profession_text(), unit.health, unit.max_health]
		resident_button.pressed.connect(_select_resident.bind(unit))
		residents_list.add_child(resident_button)


func _select_resident(unit: Unit):
	if not is_instance_valid(unit):
		return
	Building.selected_building = null
	var units: Array[Unit] = [unit]
	Unit.set_selection(units)


func _try_open_building_menu(point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 1
	for hit in world.get_world_2d().direct_space_state.intersect_point(query, 32):
		if hit.collider is Building and hit.collider.building_kind in ["warehouse", "residence", "factory"]:
			_open_building_menu(hit.collider)
			return true
	return false


func _open_building_menu(building: Building):
	if not is_instance_valid(building):
		return
	Unit.clear_selection()
	Building.selected_building = building
	residents_list_key = ""
	_update_building_panel()


func _close_building_menu():
	Building.selected_building = null
	building_panel.visible = false


func _on_storage_quota_changed(value: float, resource_type: StringName):
	if updating_building_controls:
		return
	var building := Building.selected_building
	if is_instance_valid(building) and building.is_warehouse():
		building.set_storage_limit(resource_type, int(value))


func _on_recipe_selected(index: int):
	if updating_building_controls:
		return
	var building := Building.selected_building
	if is_instance_valid(building) and building.is_factory():
		building.set_recipe(StringName(recipe_picker.get_item_metadata(index)))


func _release_selected_building_occupants():
	var building := Building.selected_building
	if not is_instance_valid(building):
		return
	for unit in building.occupants.duplicate():
		if is_instance_valid(unit):
			unit.force_exit_building(building)


func _input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		if is_instance_valid(ghost) and event.keycode in [KEY_Q, KEY_E]:
			_rotate_building_preview(-PI * 0.5 if event.keycode == KEY_Q else PI * 0.5)
			get_viewport().set_input_as_handled()
			return
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
		if event is InputEventMouseButton and not event.pressed:
			_handle_tactical_release(event)
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
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_rotate_building_preview(-PI * 0.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_rotate_building_preview(PI * 0.5)
		get_viewport().set_input_as_handled()
		return

	if get_viewport().gui_get_hovered_control() != null:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		selecting = true
		selection_start = world.get_global_mouse_position()
		selection_additive = event.shift_pressed
		tactical_overlay.show_selection(selection_start, selection_start)
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_RIGHT and not Unit.get_selected_units().is_empty():
		forming = true
		formation_start = world.get_global_mouse_position()
		tactical_overlay.show_formation(_get_formation_positions(formation_start, formation_start))
		get_viewport().set_input_as_handled()


func _handle_tactical_release(event: InputEventMouseButton):
	if event.button_index == MOUSE_BUTTON_LEFT and selecting:
		selecting = false
		tactical_overlay.hide_selection()
		var finish := world.get_global_mouse_position()
		if selection_start.distance_to(finish) < 8.0 and not _has_visible_unit_at(finish) and _try_open_building_menu(finish):
			get_viewport().set_input_as_handled()
			return
		_apply_box_selection(selection_start, finish, selection_additive)
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_RIGHT and forming:
		forming = false
		var finish := world.get_global_mouse_position()
		var points := _get_formation_positions(formation_start, finish)
		tactical_overlay.hide_formation()
		if formation_start.distance_to(finish) < 10.0 and _issue_group_context_command(formation_start):
			pass
		else:
			var units := Unit.get_selected_units()
			for index in range(mini(units.size(), points.size())):
				units[index].command_move(points[index])
		get_viewport().set_input_as_handled()


func _has_visible_unit_at(point: Vector2) -> bool:
	for unit in get_tree().get_nodes_in_group("units"):
		if unit is Unit and unit.visible and unit.global_position.distance_to(point) <= 16.0:
			return true
	return false


func _apply_box_selection(from: Vector2, to: Vector2, additive: bool):
	var selected: Array[Unit] = []
	if additive:
		for already_selected in Unit.get_selected_units():
			selected.append(already_selected)
	var rect := Rect2(from, to - from).abs()
	if rect.size.length() < 8.0:
		for unit in get_tree().get_nodes_in_group("units"):
			if unit.global_position.distance_to(to) <= 16.0:
				if unit not in selected:
					selected.append(unit)
				break
	else:
		for unit in get_tree().get_nodes_in_group("units"):
			if rect.has_point(unit.global_position) and unit not in selected:
				selected.append(unit)
	Unit.set_selection(selected)


func _get_formation_positions(origin: Vector2, drag_end: Vector2) -> Array[Vector2]:
	var count := Unit.get_selected_units().size()
	var result: Array[Vector2] = []
	var drag := drag_end - origin
	if drag.length() >= 20.0:
		var direction := drag.normalized()
		var spacing := 0.0 if count <= 1 else drag.length() / float(count - 1)
		for index in range(count):
			result.append(origin + direction * spacing * index)
	else:
		var columns := maxi(1, ceili(sqrt(float(count))))
		var rows := ceili(float(count) / columns)
		for index in range(count):
			var column := index % columns
			var row := index / columns
			result.append(origin + Vector2((column - (columns - 1) * 0.5) * 18.0, (row - (rows - 1) * 0.5) * 18.0))
	return result


func _issue_group_context_command(point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hits := world.get_world_2d().direct_space_state.intersect_point(query, 32)
	for hit in hits:
		if hit.collider is Building and hit.collider.under_construction:
			for unit in Unit.get_selected_units():
				unit.command_build(hit.collider)
			return true
	for hit in hits:
		if hit.collider is Building and hit.collider.is_completed() and (hit.collider.is_factory() or hit.collider.is_residence()):
			for unit in Unit.get_selected_units():
				unit.command_enter_building(hit.collider)
			return true
	if Unit.continuous_harvest_mode:
		var selected_resource: Node2D
		var nearest_distance := INF
		for hit in hits:
			if hit.collider is Node and hit.collider.is_in_group("resources"):
				var distance: float = point.distance_squared_to(hit.collider.global_position)
				if distance < nearest_distance:
					nearest_distance = distance
					selected_resource = hit.collider
		if is_instance_valid(selected_resource):
			for unit in Unit.get_selected_units():
				unit.command_harvest(selected_resource)
			return true
	return false


func _toggle_harvest_mode():
	Unit.continuous_harvest_mode = not Unit.continuous_harvest_mode
	_update_mode_button()


func _update_mode_button():
	mode_button.text = "Добыча ИИ: ВКЛ (R)" if Unit.continuous_harvest_mode else "Добыча ИИ: ВЫКЛ (R)"


func _toggle_auto_work():
	Unit.auto_work_enabled = not Unit.auto_work_enabled
	if not Unit.auto_work_enabled:
		for building in get_tree().get_nodes_in_group("buildings"):
			if building is Building and building.is_residence():
				for unit in building.occupants.duplicate():
					if is_instance_valid(unit):
						unit.force_exit_building(building)
	_update_auto_work_button()


func _update_auto_work_button():
	auto_work_button.text = "Авторабота: ВКЛ" if Unit.auto_work_enabled else "Авторабота: ВЫКЛ"


func _begin_building_placement(scene: PackedScene):
	_cancel_all_placement()
	building_rotation_offset = 0.0
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
		ghost.rotation = building_rotation_offset
		return
	var direction: Vector2 = Vector2.RIGHT.rotated(snapped_road.rotation)
	var perpendicular := Vector2(-direction.y, direction.x)
	var along: float = clampf((mouse_position - snapped_road.global_position).dot(direction), -RoadSegment.SEGMENT_LENGTH * 0.5, RoadSegment.SEGMENT_LENGTH * 0.5)
	var side := signf((mouse_position - snapped_road.global_position).dot(perpendicular))
	if side == 0.0:
		side = 1.0
	ghost.global_position = snapped_road.global_position + direction * along + perpendicular * 40.0 * side
	# Нулевая ориентация здания смотрит входом вниз. Поэтому здание над
	# дорогой повторяет её угол, а здание под дорогой разворачивается на 180°.
	var automatic_rotation := snapped_road.rotation + (PI if side > 0.0 else 0.0)
	ghost.rotation = wrapf(automatic_rotation + building_rotation_offset, -PI, PI)


func _rotate_building_preview(angle: float):
	building_rotation_offset = wrapf(building_rotation_offset + angle, -PI, PI)
	if is_instance_valid(ghost):
		_snap_building_to_road(world.get_global_mouse_position())


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
	for builder in Unit.get_selected_units():
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
	building_rotation_offset = 0.0


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
