extends CanvasLayer

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
const ROAD_PREVIEW_VALID_COLOR := Color(0.95, 0.8, 0.2, 0.8)
const ROAD_PREVIEW_INVALID_COLOR := Color(1.0, 0.25, 0.25, 0.9)
const DISMANTLE_CONFIRMATION_TIME_MS := 4000
const PARALLEL_ROAD_ALIGNMENT := 0.985
const UNIT_PANEL_COLLAPSED_WIDTH := 160.0
const UNIT_PANEL_EXPANDED_WIDTH := 300.0
const MILITARY_CURVE_POINT_SPACING := 24.0
const MAX_MILITARY_CURVE_POINTS := 512
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
var build_scroll: ScrollContainer
var controls_panel: PanelContainer
var unit_panel: PanelContainer
var unit_scroll: ScrollContainer
var resource_panel: PanelContainer
var resource_scroll: ScrollContainer
var ghost: Building
var selected_scene: PackedScene
var placement_valid := false
var snapped_road: RoadSegment
var unit_status: Label
var unit_panel_collapsed := false
var resource_status: Label
var mode_button: Button
var road_mode := false
var road_start: Variant = null
var road_start_segment: RoadSegment
var road_start_direction := Vector2.ZERO
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
var platoon_line_mode: StringName = &""
var platoon_line_commanders: Array[Unit] = []
var platoon_line_points: Array[Vector2] = []
var platoon_line_drawing := false
var platoon_line_id := ""
var military_line_sequence := 0
var building_panel: PanelContainer
var building_scroll: ScrollContainer
var building_title: Label
var building_status: Label
var warehouse_settings: VBoxContainer
var factory_settings: VBoxContainer
var factory_diagnostic: Label
var recipe_hint: Label
var factory_worker_target_input: SpinBox
var road_settings: VBoxContainer
var road_name_input: LineEdit
var government_settings: VBoxContainer
var government_tabs: TabContainer
var government_statistics: Label
var migration_target_input: SpinBox
var army_statistics: Label
var mobilization_target_input: SpinBox
var organize_army_button: Button
var residents_settings: VBoxContainer
var residents_title: Label
var residents_list: VBoxContainer
var quota_sliders := {}
var quota_value_labels := {}
var recipe_picker: OptionButton
var factory_recipe_key := ""
var release_occupants_button: Button
var dismantle_button: Button
var dismantle_confirmation_id := 0
var dismantle_confirmation_deadline := 0
var updating_building_controls := false
var residents_list_key := ""
var building_rotation_offset := 0.0
var interface_theme: Theme
var current_ui_scale := -1.0
var build_buttons: Array[Button] = []
var government_build_button: Button
var world_index: Node
var hud_refresh_timer := 0.0

@onready var world: Node2D = get_parent()
@onready var buildings: Node2D = world.get_node("buildings")
@onready var roads: Node2D = world.get_node("roads")


func _ready():
	world_index = world.get_node_or_null("WorldIndex")
	naming_rng.randomize()
	current_ui_scale = SovereignUITheme.get_scale(get_viewport().get_visible_rect().size)
	interface_theme = SovereignUITheme.create_theme(current_ui_scale)
	tactical_overlay = TacticalOverlay.new()
	tactical_overlay.z_index = 100
	world.add_child.call_deferred(tactical_overlay)
	_create_interface()


func _panel(position: Vector2, minimum_size: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme = interface_theme
	panel.position = position
	panel.custom_minimum_size = minimum_size
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	return box


func _create_interface():
	var controls_box := _panel(Vector2(16, 16), Vector2(360, 0))
	controls_panel = controls_box.get_parent() as PanelContainer
	var controls := Label.new()
	controls.text = "ЛКМ: выбор/меню здания | ПКМ: приказ | B: стройка | M: войска | Q/E: поворот | R: добыча"
	controls_box.add_child(controls)

	var unit_box := _panel(Vector2(16, 58), Vector2(300, 0))
	unit_panel = unit_box.get_parent() as PanelContainer
	unit_panel.remove_child(unit_box)
	unit_scroll = ScrollContainer.new()
	unit_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	unit_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	unit_panel.add_child(unit_scroll)
	unit_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_scroll.add_child(unit_box)
	unit_status = Label.new()
	unit_status.text = "Юнит не выбран"
	unit_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unit_box.add_child(unit_status)

	resource_panel = PanelContainer.new()
	resource_panel.theme = interface_theme
	resource_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	resource_panel.position = Vector2(16, 16)
	resource_panel.custom_minimum_size = Vector2(250, 0)
	add_child(resource_panel)
	resource_scroll = ScrollContainer.new()
	resource_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	resource_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	resource_panel.add_child(resource_scroll)
	var resource_box := VBoxContainer.new()
	resource_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resource_scroll.add_child(resource_box)
	resource_status = Label.new()
	resource_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resource_box.add_child(resource_status)
	mode_button = Button.new()
	mode_button.pressed.connect(_toggle_harvest_mode)
	resource_box.add_child(mode_button)
	_update_mode_button()

	menu = PanelContainer.new()
	menu.theme = interface_theme
	menu.position = Vector2(16, 220)
	menu.visible = false
	menu.clip_contents = true
	add_child(menu)
	build_scroll = ScrollContainer.new()
	build_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	build_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	build_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu.add_child(build_scroll)
	var build_box := VBoxContainer.new()
	build_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_scroll.add_child(build_box)
	var title := Label.new()
	title.text = "Строительство"
	build_box.add_child(title)
	_add_build_button(build_box, "Жилой дом — 10 дерева", RESIDENCE_SCENE)
	_add_build_button(build_box, "Склад — 15 дерева", WAREHOUSE_SCENE)
	_add_build_button(build_box, "Завод — 25 дерева, 10 камня", FACTORY_SCENE)
	_add_build_button(build_box, "Пищевой завод — 20 дерева, 5 камня", FOOD_FACTORY_SCENE)
	_add_build_button(build_box, "Шахта — 20 дерева, 10 камня", MINE_SCENE)
	_add_build_button(build_box, "Электростанция — 30 дерева, 15 камня", POWER_PLANT_SCENE)
	_add_build_button(build_box, "Казарма — 25 дерева, 10 камня", BARRACKS_SCENE)
	_add_build_button(build_box, "Военный завод — 35 дерева, 25 камня", MILITARY_FACTORY_SCENE)
	government_build_button = _add_build_button(build_box, "Правительство — 30 дерева, 20 камня", GOVERNMENT_SCENE)
	var road_button := Button.new()
	road_button.text = "Построить дорогу линией"
	road_button.pressed.connect(_begin_road_mode)
	_configure_build_button(road_button, ROAD_SCENE)
	build_box.add_child(road_button)
	build_buttons.append(road_button)
	_create_building_panel()


func _create_building_panel():
	building_panel = PanelContainer.new()
	building_panel.theme = interface_theme
	building_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	building_panel.position = Vector2(16, 190)
	building_panel.custom_minimum_size = Vector2.ZERO
	building_panel.visible = false
	building_panel.clip_contents = true
	add_child(building_panel)
	building_scroll = ScrollContainer.new()
	building_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	building_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	building_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	building_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	building_panel.add_child(building_scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	building_scroll.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	building_title = Label.new()
	building_title.add_theme_font_size_override("font_size", maxi(roundi(16.0 * current_ui_scale), 11))
	building_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	building_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(building_title)
	var close_button := Button.new()
	close_button.text = "✕"
	close_button.tooltip_text = "Закрыть меню здания"
	close_button.pressed.connect(_close_building_menu)
	header.add_child(close_button)
	building_status = Label.new()
	building_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(building_status)
	residents_settings = VBoxContainer.new()
	box.add_child(residents_settings)
	residents_title = Label.new()
	residents_title.text = "Жильцы (нажмите для выбора):"
	residents_settings.add_child(residents_title)
	residents_list = VBoxContainer.new()
	residents_settings.add_child(residents_list)

	warehouse_settings = VBoxContainer.new()
	box.add_child(warehouse_settings)
	var quota_hint := Label.new()
	quota_hint.text = "Квоты хранения (всего 300). Увеличение одной квоты автоматически уменьшает свободные квоты остальных."
	quota_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warehouse_settings.add_child(quota_hint)
	for resource_type in Building.RESOURCE_TYPES:
		var row := VBoxContainer.new()
		warehouse_settings.add_child(row)
		var row_header := HBoxContainer.new()
		row.add_child(row_header)
		var label := Label.new()
		label.text = Building.RESOURCE_NAMES[resource_type]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_header.add_child(label)
		var value_label := Label.new()
		value_label.add_theme_color_override("font_color", SovereignUITheme.ACCENT_BRIGHT)
		row_header.add_child(value_label)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 300
		slider.step = 1
		slider.custom_minimum_size = Vector2(0, 16)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_storage_quota_changed.bind(resource_type))
		row.add_child(slider)
		quota_sliders[resource_type] = slider
		quota_value_labels[resource_type] = value_label

	factory_settings = VBoxContainer.new()
	box.add_child(factory_settings)
	var worker_target_label := Label.new()
	worker_target_label.text = "Работников в этом здании:"
	factory_settings.add_child(worker_target_label)
	factory_worker_target_input = SpinBox.new()
	factory_worker_target_input.min_value = 0
	factory_worker_target_input.max_value = 5
	factory_worker_target_input.step = 1
	factory_worker_target_input.update_on_text_changed = true
	factory_worker_target_input.value_changed.connect(_on_factory_worker_target_changed)
	factory_settings.add_child(factory_worker_target_input)
	var recipe_label := Label.new()
	recipe_label.text = "Производить:"
	factory_settings.add_child(recipe_label)
	recipe_picker = OptionButton.new()
	recipe_picker.fit_to_longest_item = false
	recipe_picker.item_selected.connect(_on_recipe_selected)
	factory_settings.add_child(recipe_picker)
	recipe_hint = Label.new()
	factory_settings.add_child(recipe_hint)
	factory_diagnostic = Label.new()
	factory_diagnostic.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	factory_settings.add_child(factory_diagnostic)
	road_settings = VBoxContainer.new()
	box.add_child(road_settings)
	var road_name_label := Label.new()
	road_name_label.text = "Название улицы:"
	road_settings.add_child(road_name_label)
	road_name_input = LineEdit.new()
	road_name_input.placeholder_text = "Введите новое название"
	road_name_input.text_submitted.connect(func(_new_text: String): _on_road_rename_requested())
	road_settings.add_child(road_name_input)
	var rename_road_button := Button.new()
	rename_road_button.text = "Переименовать улицу"
	rename_road_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rename_road_button.pressed.connect(_on_road_rename_requested)
	road_settings.add_child(rename_road_button)
	government_settings = VBoxContainer.new()
	box.add_child(government_settings)
	government_tabs = TabContainer.new()
	government_tabs.custom_minimum_size = Vector2(0, 230)
	government_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	government_settings.add_child(government_tabs)
	var population_settings := VBoxContainer.new()
	population_settings.name = "Население"
	government_tabs.add_child(population_settings)
	var migration_label := Label.new()
	migration_label.text = "Миграция до населения:"
	population_settings.add_child(migration_label)
	migration_target_input = SpinBox.new()
	migration_target_input.min_value = 0
	migration_target_input.max_value = 10000
	migration_target_input.step = 1
	migration_target_input.update_on_text_changed = true
	migration_target_input.value_changed.connect(_on_migration_target_changed)
	population_settings.add_child(migration_target_input)
	var migration_hint := Label.new()
	migration_hint.text = "0 — миграция отключена. Новые жители прибывают только при наличии свободного жилья."
	migration_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	population_settings.add_child(migration_hint)
	government_statistics = Label.new()
	government_statistics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	population_settings.add_child(government_statistics)
	var army_settings := VBoxContainer.new()
	army_settings.name = "Армия"
	government_tabs.add_child(army_settings)
	var mobilization_label := Label.new()
	mobilization_label.text = "Мобилизовать до человек:"
	army_settings.add_child(mobilization_label)
	mobilization_target_input = SpinBox.new()
	mobilization_target_input.min_value = 0
	mobilization_target_input.max_value = 10000
	mobilization_target_input.step = 1
	mobilization_target_input.update_on_text_changed = true
	mobilization_target_input.value_changed.connect(_on_mobilization_target_changed)
	army_settings.add_child(mobilization_target_input)
	var army_hint := Label.new()
	army_hint.text = "Одна готовая казарма размещает до 15 солдат. Мобилизованные жители перестают выполнять гражданскую работу."
	army_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	army_settings.add_child(army_hint)
	organize_army_button = Button.new()
	organize_army_button.text = "Сформировать отряды и взводы"
	organize_army_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	organize_army_button.pressed.connect(_on_organize_army_requested)
	army_settings.add_child(organize_army_button)
	army_statistics = Label.new()
	army_statistics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	army_settings.add_child(army_statistics)
	release_occupants_button = Button.new()
	release_occupants_button.text = "Выпустить всех юнитов"
	release_occupants_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	release_occupants_button.pressed.connect(_release_selected_building_occupants)
	box.add_child(release_occupants_button)
	dismantle_button = Button.new()
	dismantle_button.text = "Разобрать постройку"
	dismantle_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	dismantle_button.tooltip_text = "Удалить выбранную постройку"
	dismantle_button.pressed.connect(_on_dismantle_selected_building)
	box.add_child(dismantle_button)


func _add_build_button(box: VBoxContainer, text: String, scene: PackedScene) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(_begin_building_placement.bind(scene))
	_configure_build_button(button, scene)
	box.add_child(button)
	build_buttons.append(button)
	return button


func _configure_build_button(button: Button, scene: PackedScene):
	var preview := scene.instantiate() as Building
	var sprite := preview.get_node_or_null("Sprite2D") as Sprite2D
	if is_instance_valid(sprite):
		button.icon = sprite.texture
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.custom_minimum_size.y = maxf(26.0 * current_ui_scale, 22.0)
	preview.free()


func _process(delta: float):
	if is_instance_valid(ghost):
		_snap_building_to_road(world.get_global_mouse_position())
		_update_placement_validity()
	if road_mode and road_start != null and is_instance_valid(road_preview):
		var road_end := _snap_road_end(road_start, world.get_global_mouse_position())
		road_preview.points = PackedVector2Array([road_start, road_end])
		road_preview.default_color = ROAD_PREVIEW_INVALID_COLOR if _road_line_has_placement_conflict(road_start, road_end) else ROAD_PREVIEW_VALID_COLOR
	if selecting:
		tactical_overlay.show_selection(selection_start, world.get_global_mouse_position())
	if forming:
		tactical_overlay.show_formation(_get_formation_positions(formation_start, world.get_global_mouse_position()))
	if platoon_line_mode != &"" and platoon_line_drawing and not platoon_line_points.is_empty():
		var mouse_position := world.get_global_mouse_position()
		if platoon_line_points.back().distance_to(mouse_position) >= MILITARY_CURVE_POINT_SPACING and platoon_line_points.size() < MAX_MILITARY_CURVE_POINTS:
			platoon_line_points.append(mouse_position)
		var preview_points: Array[Vector2] = []
		preview_points.assign(platoon_line_points)
		if preview_points.back().distance_to(mouse_position) >= 1.0:
			preview_points.append(mouse_position)
		tactical_overlay.show_order_line_preview(preview_points, platoon_line_mode)
	hud_refresh_timer -= delta
	if hud_refresh_timer <= 0.0:
		hud_refresh_timer = 0.2
		_update_hud()
		_update_responsive_layout()
		_refresh_platoon_plan_overlay()


func _update_responsive_layout():
	var viewport_size := get_viewport().get_visible_rect().size
	var ui_scale := SovereignUITheme.get_scale(viewport_size)
	_apply_interface_scale(ui_scale)
	var narrow := viewport_size.x < 780.0 or viewport_size.y < 480.0
	var building_open := is_instance_valid(Building.selected_building)
	var unit_open := is_instance_valid(Unit.get_selected_unit())
	var margin := 8.0
	var available_size := Vector2(maxf(viewport_size.x - margin * 2.0, 1.0), maxf(viewport_size.y - margin * 2.0, 1.0))
	var right_width := minf(290.0 * ui_scale, available_size.x)

	if narrow:
		controls_panel.visible = false
		if menu.visible:
			resource_panel.visible = false
			unit_panel.visible = false
			building_panel.visible = false
			menu.position = Vector2(margin, margin)
			menu.custom_minimum_size = Vector2.ZERO
			menu.size = available_size
			return

		menu.custom_minimum_size = Vector2.ZERO
		if building_open:
			resource_panel.visible = false
			unit_panel.visible = false
			building_panel.visible = true
			building_panel.position = Vector2(margin, margin)
			building_panel.custom_minimum_size = Vector2.ZERO
			building_panel.size = available_size
		elif unit_open:
			resource_panel.visible = false
			building_panel.visible = false
			unit_panel.visible = true
			unit_panel.position = Vector2(margin, margin)
			unit_panel.custom_minimum_size = Vector2.ZERO
			unit_panel.size = available_size
		else:
			unit_panel.visible = false
			building_panel.visible = false
			resource_panel.visible = true
			resource_panel.position = Vector2(viewport_size.x - right_width - margin, margin)
			resource_panel.custom_minimum_size = Vector2.ZERO
			resource_panel.size = Vector2(right_width, minf(205.0 * ui_scale, available_size.y))
		return

	controls_panel.visible = true
	controls_panel.position = Vector2(12, 12)
	unit_panel.visible = true
	unit_panel.position = Vector2(12, 48.0 * ui_scale + 8.0)
	var unit_width := (UNIT_PANEL_COLLAPSED_WIDTH if not unit_open else UNIT_PANEL_EXPANDED_WIDTH) * ui_scale
	unit_panel.custom_minimum_size.x = unit_width
	unit_panel.size = Vector2(unit_width, minf((178.0 if unit_open else 34.0) * ui_scale, available_size.y))
	resource_panel.visible = true
	resource_panel.position = Vector2(viewport_size.x - right_width - 12.0, 12.0)
	resource_panel.custom_minimum_size = Vector2.ZERO
	resource_panel.size = Vector2(right_width, minf(205.0 * ui_scale, maxf(viewport_size.y - 24.0, 1.0)))
	# Keep the construction menu close to the unit panel instead of leaving a
	# large empty strip between them.
	var menu_top := minf(unit_panel.position.y + unit_panel.size.y + 8.0 * ui_scale, viewport_size.y * 0.32)
	# The notification toggle occupies the bottom-left corner of the viewport.
	var menu_bottom_margin := 54.0 * ui_scale
	var menu_width := minf(285.0 * ui_scale, available_size.x)
	menu.position = Vector2(12.0, menu_top)
	menu.custom_minimum_size = Vector2.ZERO
	menu.size = Vector2(menu_width, maxf(viewport_size.y - menu_top - menu_bottom_margin, 1.0))
	building_panel.visible = building_open
	if building_open:
		var building_top := resource_panel.position.y + resource_panel.size.y + 6.0
		building_panel.position = Vector2(viewport_size.x - right_width - 12.0, building_top)
		building_panel.custom_minimum_size = Vector2.ZERO
		building_panel.size = Vector2(right_width, maxf(viewport_size.y - building_top - 8.0, 1.0))


func _apply_interface_scale(ui_scale: float):
	if is_equal_approx(current_ui_scale, ui_scale):
		return
	current_ui_scale = ui_scale
	interface_theme = SovereignUITheme.create_theme(ui_scale)
	for panel in [controls_panel, unit_panel, resource_panel, menu, building_panel]:
		if is_instance_valid(panel):
			panel.theme = interface_theme
	if is_instance_valid(building_title):
		building_title.add_theme_font_size_override("font_size", maxi(roundi(16.0 * ui_scale), 11))
	for button in build_buttons:
		if is_instance_valid(button):
			button.custom_minimum_size.y = maxf(26.0 * ui_scale, 22.0)


func _update_hud():
	var selected_units := Unit.get_selected_units()
	if selected_units.size() == 1:
		var unit := selected_units[0]
		unit_status.text = "Имя: %s\nФракция: %s\nЗдоровье: %d/%d\nПитание: %s\nПрофессия: %s\nАрмия: %s\nСнаряжение: %s\nСейчас: %s\nГруз: дерево %d, камень %d (%d/%d)\nПроизведено предметов: %d" % [unit.unit_name, unit.faction_name, unit.health, unit.max_health, unit.get_food_status_text(), unit.get_profession_text(), unit.get_military_assignment_text(), unit.get_military_equipment_text(), unit.get_task_text(), unit.carried_wood, unit.carried_stone, unit.get_carried_total(), unit.carry_capacity, unit.produced_items]
	elif selected_units.size() > 1:
		unit_status.text = "Выбрано юнитов: %d" % selected_units.size()
	else:
		unit_status.text = "Юнит не выбран"
	_set_unit_panel_collapsed(selected_units.is_empty())
	var wood := 0
	var stone := 0
	var iron := 0
	var coal := 0
	var planks := 0
	var tools := 0
	var food := 0
	var armor := 0
	var rifles := 0
	var electricity := 0
	var electricity_capacity := 0
	var total_capacity := 0
	var workers := 0
	var factory_workers := 0
	var population := 0
	var mobilized := 0
	var army_capacity := 0
	var residence_count := 0
	var housing_capacity := 0
	var local_faction_id := _get_local_faction_id()
	var faction_units: Array = world_index.get_units(local_faction_id) if is_instance_valid(world_index) else get_tree().get_nodes_in_group("units")
	for unit in faction_units:
		if unit is Unit and unit.faction_id == local_faction_id:
			population += 1
			if unit.is_mobilized:
				mobilized += 1
	var faction_buildings: Array = world_index.get_buildings(local_faction_id) if is_instance_valid(world_index) else get_tree().get_nodes_in_group("buildings")
	var has_government := false
	for building in faction_buildings:
		if building is Building and building.faction_id == local_faction_id and building.is_government() and not building.placement_preview:
			has_government = true
		if building is Building and building.faction_id == local_faction_id and building.is_residence() and building.is_completed():
			residence_count += 1
			housing_capacity += building.max_occupants
		if building is Building and building.faction_id == local_faction_id and building.is_warehouse() and building.is_completed():
			wood += building.stored_wood
			stone += building.stored_stone
			iron += building.get_stored_resource(&"iron")
			coal += building.get_stored_resource(&"coal")
			planks += building.get_stored_resource(&"planks")
			tools += building.get_stored_resource(&"tools")
			food += building.get_stored_resource(&"food")
			armor += building.get_stored_resource(&"armor")
			rifles += building.get_stored_resource(&"rifles")
			total_capacity += building.storage_capacity
			workers += building.assigned_workers.size()
		elif building is Building and building.faction_id == local_faction_id and building.is_factory() and building.is_completed():
			factory_workers += building.occupants.size()
			if building.is_power_plant():
				electricity += building.stored_electricity
				electricity_capacity += building.electricity_capacity
		elif building is Building and building.faction_id == local_faction_id and building.is_barracks() and building.is_completed():
			army_capacity += building.max_occupants
	var food_per_minute := ceili(float(population) * 60.0 / Unit.FOOD_CONSUMPTION_INTERVAL)
	resource_status.text = "%s\nРесурсы: %d/%d\nДерево %d | Камень %d | Железо %d | Уголь %d\nДоски %d | Инструменты %d\nЕда %d | Расход %d/мин\nБроня %d | Автоматы %d\nЭлектричество %d/%d\nНаселение %d/%d | Дома %d\nАрмия %d/%d\nДобыча %d | Производство %d" % [_get_local_faction_name(), wood + stone + iron + coal + planks + tools + food + armor + rifles, total_capacity, wood, stone, iron, coal, planks, tools, food, food_per_minute, armor, rifles, electricity, electricity_capacity, population, housing_capacity, residence_count, mobilized, army_capacity, workers, factory_workers]
	if is_instance_valid(government_build_button):
		government_build_button.disabled = has_government
		government_build_button.tooltip_text = "У фракции уже есть правительство" if has_government else ""
	_update_building_panel()


func _set_unit_panel_collapsed(collapsed: bool):
	if unit_panel_collapsed == collapsed:
		return
	unit_panel_collapsed = collapsed
	var target_width := UNIT_PANEL_COLLAPSED_WIDTH if collapsed else UNIT_PANEL_EXPANDED_WIDTH
	unit_panel.custom_minimum_size.x = target_width
	# Панель не управляется внешним Container, поэтому после уменьшения текста
	# явно сбрасываем старый размер: иначе она сохраняет высоту полной карточки.
	unit_panel.size = Vector2(target_width, 0.0)


func _update_building_panel():
	var building := Building.selected_building
	if not is_instance_valid(building):
		dismantle_confirmation_id = 0
		dismantle_confirmation_deadline = 0
		building_panel.visible = false
		return
	building_panel.visible = true
	var editable := building.can_be_edited_locally()
	building_title.text = "Улица «%s»" % (building as RoadSegment).street_name if building is RoadSegment else (building.address if not building.address.is_empty() else building.display_name)
	if building.under_construction:
		building_status.text = "Строится: дерево %d/%d, камень %d/%d" % [building.delivered_wood, building.wood_required, building.delivered_stone, building.stone_required]
	else:
		building_status.text = "Готово"
	warehouse_settings.visible = building.is_warehouse() and building.is_completed()
	factory_settings.visible = building.is_factory() and building.is_completed()
	road_settings.visible = building is RoadSegment
	government_settings.visible = building.is_government() and building.is_completed()
	residents_settings.visible = (building.is_residence() or building.is_barracks()) and building.is_completed()
	release_occupants_button.visible = building.is_completed() and (building.is_factory() or building.is_residence() or building.is_barracks())
	release_occupants_button.disabled = building.occupants.is_empty() or not editable
	_update_dismantle_button(building, editable)
	if road_settings.visible:
		var road := building as RoadSegment
		building_status.text = "Строится" if road.under_construction else "Готово"
		road_name_input.editable = editable
		if not road_name_input.has_focus():
			road_name_input.text = road.street_name
	elif warehouse_settings.visible:
		var allocated := building.get_total_storage_limits()
		building_status.text = "Занято %d/%d  •  Квоты %d/%d  •  Свободно %d" % [building.get_total_stored(), building.storage_capacity, allocated, building.storage_capacity, maxi(building.storage_capacity - allocated, 0)]
		updating_building_controls = true
		for resource_type in Building.RESOURCE_TYPES:
			var slider: HSlider = quota_sliders[resource_type]
			var current_limit := building.get_storage_limit(resource_type)
			var stored_amount := building.get_stored_resource(resource_type)
			slider.min_value = 0
			slider.max_value = building.storage_capacity
			slider.editable = editable
			slider.value = current_limit
			var value_label: Label = quota_value_labels[resource_type]
			value_label.text = "квота %d  •  есть %d" % [current_limit, stored_amount]
		updating_building_controls = false
	elif factory_settings.visible:
		building_status.text = "Работают %d/%d (вместимость %d) | рецепт: %s" % [building.occupants.size(), building.get_worker_target(), building.max_workers, building.get_recipe_name(building.selected_recipe)]
		factory_diagnostic.text = building.get_factory_status_text()
		_sync_factory_recipe_controls(building)
		updating_building_controls = true
		recipe_picker.disabled = not editable
		factory_worker_target_input.editable = editable
		factory_worker_target_input.max_value = building.max_workers
		factory_worker_target_input.value = building.get_worker_target()
		for index in range(recipe_picker.item_count):
			if StringName(recipe_picker.get_item_metadata(index)) == building.selected_recipe:
				recipe_picker.select(index)
				break
		updating_building_controls = false
	elif government_settings.visible:
		var government := building as GovernmentBuilding
		var total_houses := government.get_total_residence_count()
		var completed_houses := government.get_completed_residence_count()
		var population := government.get_population_count()
		var capacity := government.get_housing_capacity()
		building_status.text = "Жители %d/%d | Свободное жильё %d" % [population, capacity, government.get_free_housing()]
		government_statistics.text = "Дома: %d всего, %d готово\nЖители: %d\n%s" % [total_houses, completed_houses, population, government.get_migration_status_text()]
		army_statistics.text = "Мобилизовано: %d/%d\nКазармы: %d\nЦель: %d\n%s\n\n%s\n\nСнаряжение на складах:\n%s" % [government.get_mobilized_count(), government.get_army_capacity(), government.get_completed_barracks_count(), government.mobilization_target, government.get_army_status_text(), government.get_army_hierarchy_text(), government.get_equipment_status_text()]
		updating_building_controls = true
		migration_target_input.editable = editable
		migration_target_input.value = government.migration_target
		mobilization_target_input.editable = editable
		mobilization_target_input.value = government.mobilization_target
		organize_army_button.disabled = not editable or government.get_mobilized_count() <= 0
		updating_building_controls = false
	elif (building.is_residence() or building.is_barracks()) and building.is_completed():
		residents_title.text = "Солдаты (нажмите для выбора):" if building.is_barracks() else "Жильцы (нажмите для выбора):"
		building_status.text = ("Солдаты %d/%d" if building.is_barracks() else "Жильцы %d/%d") % [building.occupants.size(), building.max_occupants]
		_update_residents_list(building)
	if not editable:
		building_status.text += "\nФракция: %s • только просмотр" % building.faction_name


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
		empty_label.text = "Казарма пока пуста" if building.is_barracks() else "Дом пока пуст"
		residents_list.add_child(empty_label)
		return
	for unit in building.occupants:
		if not is_instance_valid(unit):
			continue
		var resident_button := Button.new()
		resident_button.text = "%s — %s, здоровье %d/%d" % [unit.unit_name, unit.get_profession_text(), unit.health, unit.max_health]
		resident_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		resident_button.disabled = not unit.can_be_controlled_locally()
		resident_button.pressed.connect(_select_resident.bind(unit))
		residents_list.add_child(resident_button)


func _sync_factory_recipe_controls(building: Building):
	var recipe_types := building.get_available_recipe_types()
	var recipe_key := str(building.building_kind)
	if factory_recipe_key != recipe_key:
		factory_recipe_key = recipe_key
		var was_updating := updating_building_controls
		updating_building_controls = true
		recipe_picker.clear()
		for recipe_type in recipe_types:
			recipe_picker.add_item(Building.FACTORY_RECIPES[recipe_type]["name"])
			recipe_picker.set_item_metadata(recipe_picker.item_count - 1, recipe_type)
		updating_building_controls = was_updating
	var hint_lines := PackedStringArray()
	for recipe_type in recipe_types:
		var recipe: Dictionary = Building.FACTORY_RECIPES[recipe_type]
		var input_parts := PackedStringArray()
		for resource_type in recipe["inputs"]:
			input_parts.append("%d %s" % [int(recipe["inputs"][resource_type]), str(Building.RESOURCE_NAMES[resource_type]).to_lower()])
		var inputs_text := "без сырья" if input_parts.is_empty() else " + ".join(input_parts)
		var output_parts := PackedStringArray()
		var outputs: Dictionary = recipe.get("outputs", {recipe.get("output", &"planks"): int(recipe.get("amount", 1))})
		for resource_type in outputs:
			output_parts.append("%d %s" % [int(outputs[resource_type]), str(Building.RESOURCE_NAMES[resource_type]).to_lower()])
		hint_lines.append("%s: %s → %s за %.1f с" % [recipe["name"], inputs_text, " + ".join(output_parts), float(recipe["time"])])
	recipe_hint.text = "\n".join(hint_lines)


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
		if hit.collider is Building and hit.collider.building_kind in ["warehouse", "residence", "factory", "food_factory", "mine", "power_plant", "military_factory", "barracks", "government", "road"]:
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
	dismantle_confirmation_id = 0
	dismantle_confirmation_deadline = 0
	building_panel.visible = false


func _on_storage_quota_changed(value: float, resource_type: StringName):
	if updating_building_controls:
		return
	var building := Building.selected_building
	if is_instance_valid(building) and building.is_warehouse() and building.can_be_edited_locally():
		var network_manager := get_node_or_null("/root/NetworkManager")
		if is_instance_valid(network_manager):
			network_manager.request_building_action(building, &"storage_limit", {"resource_type": resource_type, "amount": int(value)})


func _on_recipe_selected(index: int):
	if updating_building_controls:
		return
	var building := Building.selected_building
	if is_instance_valid(building) and building.is_factory() and building.can_be_edited_locally():
		var network_manager := get_node_or_null("/root/NetworkManager")
		if is_instance_valid(network_manager):
			network_manager.request_building_action(building, &"recipe", {"recipe": StringName(recipe_picker.get_item_metadata(index))})


func _on_factory_worker_target_changed(value: float):
	if updating_building_controls:
		return
	var building := Building.selected_building
	if is_instance_valid(building) and building.is_factory() and building.can_be_edited_locally():
		var network_manager := get_node_or_null("/root/NetworkManager")
		if is_instance_valid(network_manager):
			network_manager.request_building_action(building, &"worker_target", {"amount": int(value)})


func _on_road_rename_requested():
	var selected := Building.selected_building
	if selected is not RoadSegment or not selected.can_be_edited_locally():
		return
	var selected_road := selected as RoadSegment
	var requested := road_name_input.text.strip_edges()
	if requested.is_empty():
		road_name_input.text = selected_road.street_name
		return
	var old_name: String = selected_road.street_name
	var new_name := _make_unique_street_name(requested, old_name)
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		network_manager.request_building_action(selected_road, &"rename_road", {"name": new_name})
	var last_number := int(house_numbers.get(old_name, 0))
	if last_number > 0:
		house_numbers[new_name] = maxi(int(house_numbers.get(new_name, 0)), last_number)
		house_numbers.erase(old_name)
	used_street_names.erase(old_name)
	used_street_names[new_name] = true
	road_name_input.text = new_name
	building_title.text = "Улица «%s»" % new_name


func _on_migration_target_changed(value: float):
	if updating_building_controls:
		return
	var building := Building.selected_building
	if building is GovernmentBuilding and building.can_be_edited_locally():
		var network_manager := get_node_or_null("/root/NetworkManager")
		if is_instance_valid(network_manager):
			network_manager.request_building_action(building, &"migration_target", {"amount": int(value)})


func _on_mobilization_target_changed(value: float):
	if updating_building_controls:
		return
	var building := Building.selected_building
	if building is GovernmentBuilding and building.can_be_edited_locally():
		var network_manager := get_node_or_null("/root/NetworkManager")
		if is_instance_valid(network_manager):
			network_manager.request_building_action(building, &"mobilization_target", {"amount": int(value)})


func _on_organize_army_requested():
	var building := Building.selected_building
	if building is GovernmentBuilding and building.can_be_edited_locally():
		var network_manager := get_node_or_null("/root/NetworkManager")
		if is_instance_valid(network_manager):
			network_manager.request_building_action(building, &"organize_army")


func _release_selected_building_occupants():
	var building := Building.selected_building
	if not is_instance_valid(building) or not building.can_be_edited_locally():
		return
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		network_manager.request_building_action(building, &"release_occupants")


func _update_dismantle_button(building: Building, editable: bool):
	var now := Time.get_ticks_msec()
	var building_id := building.get_instance_id()
	if dismantle_confirmation_id != 0 and (dismantle_confirmation_id != building_id or now > dismantle_confirmation_deadline):
		dismantle_confirmation_id = 0
		dismantle_confirmation_deadline = 0
	var awaiting_confirmation := dismantle_confirmation_id == building_id
	dismantle_button.disabled = not editable
	dismantle_button.tooltip_text = "Содержимое и материалы постройки не возвращаются"
	if awaiting_confirmation:
		dismantle_button.text = "Подтвердить разбор"
	else:
		dismantle_button.text = "Разобрать сегмент дороги" if building is RoadSegment else "Разобрать постройку"


func _on_dismantle_selected_building():
	var building := Building.selected_building
	if not is_instance_valid(building) or not building.can_be_edited_locally():
		return
	var now := Time.get_ticks_msec()
	var building_id := building.get_instance_id()
	if dismantle_confirmation_id != building_id or now > dismantle_confirmation_deadline:
		dismantle_confirmation_id = building_id
		dismantle_confirmation_deadline = now + DISMANTLE_CONFIRMATION_TIME_MS
		_update_dismantle_button(building, true)
		return
	dismantle_confirmation_id = 0
	dismantle_confirmation_deadline = 0
	Building.selected_building = null
	building_panel.visible = false
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		network_manager.request_building_action(building, &"dismantle")


func _input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and platoon_line_mode != &"":
			_cancel_platoon_line_mode()
			get_viewport().set_input_as_handled()
			return
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

	# GUI получает событие после _input(). Не обрабатываем здесь мышь над
	# панелями, иначе клик по миникарте или кнопке одновременно размещает
	# выбранную постройку/дорогу на земле под интерфейсом.
	if event is InputEventMouseButton and get_viewport().gui_get_hovered_control() != null:
		if platoon_line_mode != &"":
			_cancel_platoon_line_mode()
		if not event.pressed:
			if selecting:
				selecting = false
				tactical_overlay.hide_selection()
			if forming:
				forming = false
				tactical_overlay.hide_formation()
		return
	if platoon_line_mode != &"" and event is InputEventMouseButton:
		_handle_platoon_line_input(event)
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
		if selection_start.distance_to(finish) < 8.0:
			var clicked_unit := _has_visible_unit_at(finish)
			if not clicked_unit:
				if _try_open_building_menu(finish):
					get_viewport().set_input_as_handled()
					return
				# Одиночный клик по свободной земле снимает выбранное здание и
				# закрывает его панель. Клики по UI сюда не попадают.
				_close_building_menu()
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
			var destinations: Array[Vector2] = []
			for index in range(mini(units.size(), points.size())):
				destinations.append(points[index])
			var network_manager := get_node_or_null("/root/NetworkManager")
			if is_instance_valid(network_manager):
				network_manager.request_unit_command(units, &"move", {"destinations": destinations})
		get_viewport().set_input_as_handled()


func begin_platoon_line_drawing(commanders: Array[Unit], line_type: StringName, line_id: String = "") -> bool:
	if line_type not in [&"front_line", &"offensive_line"]:
		return false
	if line_type == &"front_line" and commanders.is_empty():
		return false
	if line_type == &"offensive_line" and line_id.is_empty():
		return false
	for commander in commanders:
		if not is_instance_valid(commander) or not commander.is_squad_commander():
			return false
	_cancel_all_placement()
	if selecting:
		selecting = false
		tactical_overlay.hide_selection()
	if forming:
		forming = false
		tactical_overlay.hide_formation()
	platoon_line_commanders.assign(commanders)
	platoon_line_mode = line_type
	platoon_line_id = line_id if not line_id.is_empty() else _make_military_line_id()
	platoon_line_points.clear()
	platoon_line_drawing = false
	return true


func _handle_platoon_line_input(event: InputEventMouseButton):
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel_platoon_line_mode()
		get_viewport().set_input_as_handled()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		var line_start: Vector2 = world.get_global_mouse_position()
		platoon_line_points.clear()
		platoon_line_points.append(line_start)
		platoon_line_drawing = true
		get_viewport().set_input_as_handled()
		return
	if not platoon_line_drawing or platoon_line_points.is_empty():
		return
	var line_end := world.get_global_mouse_position()
	if platoon_line_points.back().distance_to(line_end) >= 1.0 and platoon_line_points.size() < MAX_MILITARY_CURVE_POINTS:
		platoon_line_points.append(line_end)
	if _get_polyline_length(platoon_line_points) >= 16.0 and not platoon_line_commanders.is_empty():
		var network_manager := get_node_or_null("/root/NetworkManager")
		if is_instance_valid(network_manager):
			network_manager.request_unit_command(platoon_line_commanders, &"military_plan", {
				"plan_action": &"set_offensive" if platoon_line_mode == &"offensive_line" else &"create_front",
				"line_id": platoon_line_id,
				"points": platoon_line_points,
			})
		else:
			world.apply_military_plan_command(
				_get_local_faction_id(),
				platoon_line_commanders,
				&"set_offensive" if platoon_line_mode == &"offensive_line" else &"create_front",
				{"line_id": platoon_line_id, "points": platoon_line_points}
			)
	_cancel_platoon_line_mode()
	get_viewport().set_input_as_handled()


func _get_polyline_length(points: Array[Vector2]) -> float:
	var result := 0.0
	for index in range(points.size() - 1):
		result += points[index].distance_to(points[index + 1])
	return result


func _make_military_line_id() -> String:
	military_line_sequence += 1
	return "%d:%d:%d:%d" % [_get_local_faction_id(), multiplayer.get_unique_id(), Time.get_ticks_msec(), military_line_sequence]


func _cancel_platoon_line_mode():
	platoon_line_mode = &""
	platoon_line_commanders.clear()
	platoon_line_points.clear()
	platoon_line_drawing = false
	platoon_line_id = ""
	if is_instance_valid(tactical_overlay):
		tactical_overlay.hide_order_line_preview()


func _refresh_platoon_plan_overlay():
	if not is_instance_valid(tactical_overlay):
		return
	var plans: Array[Dictionary] = []
	var faction_id := _get_local_faction_id()
	if world.has_method("get_military_front_lines"):
		plans.assign(world.get_military_front_lines(faction_id))
	tactical_overlay.set_platoon_plans(plans)


func _has_visible_unit_at(point: Vector2) -> bool:
	var units: Array = world_index.get_units() if is_instance_valid(world_index) else get_tree().get_nodes_in_group("units")
	for unit in units:
		if unit is Unit and unit.visible and unit.global_position.distance_to(point) <= 16.0:
			return true
	return false


func _apply_box_selection(from: Vector2, to: Vector2, additive: bool):
	var selected: Array[Unit] = []
	if additive:
		for already_selected in Unit.get_selected_units():
			selected.append(already_selected)
	var rect := Rect2(from, to - from).abs()
	var units: Array = world_index.get_units() if is_instance_valid(world_index) else get_tree().get_nodes_in_group("units")
	if rect.size.length() < 8.0:
		for unit in units:
			if unit is Unit and unit.can_be_controlled_locally() and unit.global_position.distance_to(to) <= 16.0:
				if unit not in selected:
					selected.append(unit)
				break
	else:
		for unit in units:
			if unit is Unit and unit.can_be_controlled_locally() and rect.has_point(unit.global_position) and unit not in selected:
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
			var network_manager := get_node_or_null("/root/NetworkManager")
			if is_instance_valid(network_manager):
				network_manager.request_unit_command(Unit.get_selected_units(), &"build", {"building_id": hit.collider.network_id})
			return true
	for hit in hits:
		if hit.collider is Building and hit.collider.is_completed() and (hit.collider.is_factory() or hit.collider.is_residence() or hit.collider.is_barracks()):
			var network_manager := get_node_or_null("/root/NetworkManager")
			if is_instance_valid(network_manager):
				network_manager.request_unit_command(Unit.get_selected_units(), &"enter_building", {"building_id": hit.collider.network_id})
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
			var network_manager := get_node_or_null("/root/NetworkManager")
			if is_instance_valid(network_manager):
				network_manager.request_unit_command(Unit.get_selected_units(), &"harvest", {
					"resource_id": int(selected_resource.get("lod_record_id")),
					"resource_type": selected_resource.get_resource_type(),
					"position": selected_resource.global_position,
				})
			return true
	return false


func _toggle_harvest_mode():
	Unit.continuous_harvest_mode = not Unit.continuous_harvest_mode
	_update_mode_button()


func _update_mode_button():
	mode_button.text = "Сбор ресурсов: ВКЛ (R)" if Unit.continuous_harvest_mode else "Сбор ресурсов: ВЫКЛ (R)"


func _begin_building_placement(scene: PackedScene):
	_cancel_all_placement()
	if scene == GOVERNMENT_SCENE and _faction_has_government(_get_local_faction_id()):
		return
	building_rotation_offset = 0.0
	selected_scene = scene
	ghost = scene.instantiate() as Building
	ghost.faction_id = _get_local_faction_id()
	ghost.faction_name = _get_local_faction_name()
	ghost.placement_preview = true
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
	if ghost.is_government() and _faction_has_government(ghost.faction_id):
		placement_valid = false
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
	if ghost.is_government() and _faction_has_government(ghost.faction_id):
		return
	var street := snapped_road.street_name
	var number: int = house_numbers.get(street, 0) + 1
	house_numbers[street] = number
	var specification := {
		"kind": ghost.building_kind,
		"position": ghost.global_position,
		"rotation": ghost.global_rotation,
		"street_name": street,
		"address": "%s, %d" % [street, number],
	}
	var builder := Unit.get_selected_unit()
	var builders: Array = [builder] if is_instance_valid(builder) else []
	_cancel_building_placement()
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		network_manager.request_spawn_buildings([specification], builders)


func _begin_road_mode():
	_cancel_all_placement()
	road_mode = true
	menu.visible = false
	road_preview = Line2D.new()
	road_preview.width = 3.0
	road_preview.default_color = ROAD_PREVIEW_VALID_COLOR
	road_preview.z_index = 30
	roads.add_child(road_preview)


func _handle_road_click():
	var point := world.get_global_mouse_position()
	if road_start == null:
		var snap := _nearest_road_endpoint(point, 40.0)
		if not snap.is_empty():
			road_start = snap.position
			road_start_segment = snap.road
			road_start_direction = snap.outward_direction
		else:
			road_start = point
			road_start_segment = null
			road_start_direction = Vector2.ZERO
		return
	_create_road_line(road_start, _snap_road_end(road_start, point))
	road_start = null
	road_start_segment = null
	road_start_direction = Vector2.ZERO
	road_preview.clear_points()


func _create_road_line(start: Vector2, end: Vector2):
	var delta := end - start
	if delta.length() < 8.0:
		return
	if _road_line_has_placement_conflict(start, end):
		return
	var direction := delta.normalized()
	var street := _road_name_for_start(direction)
	var angle := direction.angle()
	var count := maxi(1, int(ceil(delta.length() / RoadSegment.SEGMENT_LENGTH)))
	var specifications: Array = []
	for i in range(count):
		var position := start + direction * (RoadSegment.SEGMENT_LENGTH * (i + 0.5))
		if _road_segment_overlaps_existing(position, angle):
			continue
		specifications.append({
			"kind": "road",
			"position": position,
			"rotation": angle,
			"street_name": street,
			"address": street,
		})
	if specifications.is_empty():
		return
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		network_manager.request_spawn_buildings(specifications, Unit.get_selected_units())


func _road_line_has_placement_conflict(start: Vector2, end: Vector2) -> bool:
	var delta := end - start
	if delta.length() < 8.0:
		return false
	var direction := delta.normalized()
	var angle := direction.angle()
	var count := maxi(1, int(ceil(delta.length() / RoadSegment.SEGMENT_LENGTH)))
	for index in range(count):
		var position := start + direction * (RoadSegment.SEGMENT_LENGTH * (index + 0.5))
		if _road_segment_overlaps_existing(position, angle):
			return true
	return false


func _road_segment_overlaps_existing(local_position: Vector2, local_angle: float) -> bool:
	var candidate_position := roads.to_global(local_position)
	var candidate_direction: Vector2 = Vector2.RIGHT.rotated(local_angle + roads.global_rotation)
	for existing in _get_indexed_roads():
		if existing is not RoadSegment or not is_instance_valid(existing):
			continue
		var existing_direction := Vector2.RIGHT.rotated(existing.global_rotation)
		# Перекрёстки разрешены. Ограничение действует только на параллельные
		# участки, проекции которых накладываются по длине.
		if absf(candidate_direction.dot(existing_direction)) < PARALLEL_ROAD_ALIGNMENT:
			continue
		var offset: Vector2 = existing.global_position - candidate_position
		var perpendicular_distance := absf(offset.cross(candidate_direction))
		if perpendicular_distance >= RoadSegment.MIN_PARALLEL_SPACING:
			continue
		var distance_along_road := absf(offset.dot(candidate_direction))
		# Центры соседних сегментов находятся в 64 px: они лишь соприкасаются
		# торцами и остаются допустимыми. Параллельные линии должны находиться
		# друг от друга минимум на расстоянии двух ширин дороги (60 px).
		if distance_along_road < RoadSegment.SEGMENT_LENGTH - 2.0:
			return true
	for existing in _get_indexed_buildings():
		if existing is not Building or existing is RoadSegment or not is_instance_valid(existing) or existing.placement_preview:
			continue
		if _road_footprint_overlaps_building(candidate_position, candidate_direction, existing):
			return true
	return false


func _road_footprint_overlaps_building(road_center: Vector2, road_axis_x: Vector2, building: Building) -> bool:
	var collision := building.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape is not RectangleShape2D:
		return false
	var rectangle := collision.shape as RectangleShape2D
	var building_transform: Transform2D = collision.global_transform
	var building_scale := Vector2(building_transform.x.length(), building_transform.y.length())
	var building_half_size: Vector2 = rectangle.size * building_scale * 0.5
	var building_axis_x: Vector2 = building_transform.x.normalized()
	var building_axis_y: Vector2 = building_transform.y.normalized()
	var road_axis_y: Vector2 = road_axis_x.orthogonal()
	return _oriented_rectangles_overlap(
		road_center,
		road_axis_x,
		road_axis_y,
		RoadSegment.FOOTPRINT_HALF_SIZE,
		collision.global_position,
		building_axis_x,
		building_axis_y,
		building_half_size
	)


func _oriented_rectangles_overlap(
	center_a: Vector2,
	axis_a_x: Vector2,
	axis_a_y: Vector2,
	half_size_a: Vector2,
	center_b: Vector2,
	axis_b_x: Vector2,
	axis_b_y: Vector2,
	half_size_b: Vector2
) -> bool:
	var offset: Vector2 = center_b - center_a
	var separating_axes: Array[Vector2] = [axis_a_x, axis_a_y, axis_b_x, axis_b_y]
	for axis in separating_axes:
		var radius_a: float = half_size_a.x * absf(axis_a_x.dot(axis)) + half_size_a.y * absf(axis_a_y.dot(axis))
		var radius_b: float = half_size_b.x * absf(axis_b_x.dot(axis)) + half_size_b.y * absf(axis_b_y.dot(axis))
		# Простое касание границ допустимо, пересечение площадей — нет.
		if absf(offset.dot(axis)) >= radius_a + radius_b - 0.01:
			return false
	return true


func _road_name_for_start(direction: Vector2) -> String:
	if is_instance_valid(road_start_segment):
		var source_direction := Vector2.RIGHT.rotated(road_start_segment.global_rotation)
		if absf(direction.dot(source_direction)) >= PARALLEL_ROAD_ALIGNMENT:
			return road_start_segment.street_name
	var generated := _make_unique_street_name(_generate_street_name())
	used_street_names[generated] = true
	return generated


func _make_unique_street_name(requested: String, except_name := "") -> String:
	var base := requested.strip_edges()
	if base.is_empty():
		base = _generate_street_name()
	var candidate := base
	var suffix := 2
	while _street_name_is_used(candidate, except_name):
		candidate = "%s %d" % [base, suffix]
		suffix += 1
	return candidate


func _street_name_is_used(street_name: String, except_name := "") -> bool:
	if street_name == except_name:
		return false
	if used_street_names.has(street_name):
		return true
	for road in _get_indexed_roads():
		if road is RoadSegment and road.street_name == street_name and road.street_name != except_name:
			return true
	return false


func _generate_street_name() -> String:
	var available: Array[String] = []
	for street_name in STREET_NAMES:
		if not _street_name_is_used(street_name):
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
			if not _street_name_is_used(combined):
				return combined

	# Практически недостижимый резерв после исчерпания всех комбинаций.
	var fallback := "%s-%s-%d" % [STREET_NAMES[0], STREET_NAMES[1], street_counter]
	street_counter += 1
	return fallback


func _nearest_road(point: Vector2, max_distance: float) -> RoadSegment:
	var nearest: RoadSegment
	var best := max_distance * max_distance
	for road in _get_indexed_roads():
		if road.faction_id != _get_local_faction_id() or road.under_construction:
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
	for road in _get_indexed_roads():
		if road is not RoadSegment or road.faction_id != _get_local_faction_id():
			continue
		var direction := Vector2.RIGHT.rotated(road.global_rotation)
		var endpoints: Array[Vector2] = road.get_endpoints()
		for endpoint_index in range(endpoints.size()):
			var connection: Vector2 = endpoints[endpoint_index]
			var distance := point.distance_squared_to(connection)
			if distance <= best:
				best = distance
				var outward_direction := direction if endpoint_index == 1 else -direction
				result = {
					"position": connection,
					"road": road,
					"outward_direction": outward_direction,
				}
	return result


func _snap_road_end(start: Vector2, point: Vector2) -> Vector2:
	var delta := point - start
	if is_instance_valid(road_start_segment) and not road_start_direction.is_zero_approx() and not delta.is_zero_approx():
		# Возле продолжения существующей улицы удерживаем линию на её оси.
		# Другие направления по-прежнему доступны для перекрёстков и ответвлений.
		if delta.normalized().dot(road_start_direction) >= 0.75:
			return start + road_start_direction * maxf(delta.dot(road_start_direction), 0.0)
	return _snap_road_axis(start, point)


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
	road_start_direction = Vector2.ZERO
	if is_instance_valid(road_preview):
		road_preview.queue_free()
	road_preview = null


func _cancel_all_placement():
	_cancel_building_placement()
	_cancel_road_mode()
	_cancel_platoon_line_mode()


func _get_local_faction_id() -> int:
	var network_manager := get_node_or_null("/root/NetworkManager")
	return network_manager.get_local_faction_id() if is_instance_valid(network_manager) else 0


func _get_indexed_roads() -> Array:
	if is_instance_valid(world_index):
		return world_index.get_buildings(-1, "road")
	return get_tree().get_nodes_in_group("roads")


func _get_indexed_buildings() -> Array:
	if is_instance_valid(world_index):
		return world_index.get_buildings()
	return get_tree().get_nodes_in_group("buildings")


func _faction_has_government(faction_id: int) -> bool:
	for building in _get_indexed_buildings():
		if building is Building and is_instance_valid(building) and building.faction_id == faction_id and building.is_government() and not building.placement_preview:
			return true
	return false


func _get_local_faction_name() -> String:
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		var slot: Dictionary = network_manager.get_faction_slot(_get_local_faction_id())
		if not slot.is_empty():
			return str(slot.get("nickname", "Игрок"))
	return "Игрок"
