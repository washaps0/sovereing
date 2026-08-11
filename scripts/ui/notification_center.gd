class_name NotificationCenter
extends CanvasLayer

@export_range(0.5, 10.0, 0.5) var scan_interval := 2.0
@export_range(1, 10, 1) var maximum_visible_messages := 4
@export var panel_width := 380.0
@export var panel_height := 220.0

var world: Node2D
var scan_timer := 0.0
var current_signature := ""
var current_ui_scale := -1.0
var last_viewport_size := Vector2.ZERO
var user_collapsed := false
var active_warning_count := 0

@onready var panel: PanelContainer = $Panel
@onready var toggle_button: Button = $Toggle
@onready var title: Label = $Panel/Content/Header/Title
@onready var messages: VBoxContainer = $Panel/Content/Scroll/Messages


func _ready():
	world = get_tree().current_scene as Node2D
	toggle_button.pressed.connect(_toggle_notifications)
	_update_layout()
	_scan_notifications()


func _process(delta: float):
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size != last_viewport_size:
		_update_layout()
	scan_timer -= delta
	if scan_timer <= 0.0:
		scan_timer = scan_interval
		_scan_notifications()


func _update_layout():
	var viewport_size := get_viewport().get_visible_rect().size
	last_viewport_size = viewport_size
	var ui_scale := SovereignUITheme.get_scale(viewport_size)
	if not is_equal_approx(current_ui_scale, ui_scale):
		current_ui_scale = ui_scale
		var interface_theme := SovereignUITheme.create_theme(ui_scale)
		panel.theme = interface_theme
		toggle_button.theme = interface_theme
	var width := minf(panel_width * ui_scale, maxf(viewport_size.x - 24.0, 180.0))
	var height := minf(panel_height * ui_scale, maxf(viewport_size.y - 24.0, 120.0))
	var margin := 12.0 * ui_scale
	var toggle_height := 34.0 * ui_scale
	var toggle_width := minf(190.0 * ui_scale, width)
	toggle_button.offset_left = margin
	toggle_button.offset_right = margin + toggle_width
	toggle_button.offset_top = -margin - toggle_height
	toggle_button.offset_bottom = -margin
	panel.offset_left = margin
	panel.offset_right = margin + width
	panel.offset_top = -margin - toggle_height - 6.0 * ui_scale - height
	panel.offset_bottom = -margin - toggle_height - 6.0 * ui_scale


func _scan_notifications():
	if not is_instance_valid(world):
		world = get_tree().current_scene as Node2D
	if not is_instance_valid(world):
		return
	var warnings: Array[Dictionary] = []
	var faction_id := _get_local_faction_id()
	var units := _get_faction_units(faction_id)
	var buildings := _get_faction_buildings(faction_id)
	_collect_food_warnings(warnings, units, buildings)
	_collect_storage_warnings(warnings, units, buildings)
	_collect_factory_warnings(warnings, buildings)
	_collect_housing_warnings(warnings, units, buildings)
	_collect_army_warnings(warnings, units)
	warnings.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.severity) > int(b.severity))
	var total_warning_count := warnings.size()
	if warnings.size() > maximum_visible_messages:
		warnings.resize(maximum_visible_messages)
	var signature := JSON.stringify({"total": total_warning_count, "warnings": warnings})
	if signature == current_signature:
		return
	current_signature = signature
	_rebuild_messages(warnings, total_warning_count)


func _collect_food_warnings(warnings: Array[Dictionary], units: Array[Unit], buildings: Array[Building]):
	if units.is_empty():
		return
	var food := 0
	var food_factories := 0
	for building in buildings:
		if building.is_warehouse() and building.is_completed():
			food += building.get_stored_resource(&"food")
		elif building.is_food_factory() and building.is_completed():
			food_factories += 1
	var starving := 0
	for unit in units:
		if unit.missed_meals > 0:
			starving += 1
	if starving > 0:
		var starvation_advice := "Постройте пищевой завод и выделите место под еду на складе." if food_factories <= 0 else "Проверьте пищевые заводы, электричество и место под еду на складах."
		_add_warning(warnings, 3, "%d жителей голодают. %s" % [starving, starvation_advice])
	elif food <= maxi(int(ceil(float(units.size()) * 0.5)), 1):
		var low_food_advice := " Постройте пищевой завод." if food_factories <= 0 else " Проверьте производство и электричество."
		_add_warning(warnings, 2, "Запасы еды заканчиваются: %d на %d жителей.%s" % [food, units.size(), low_food_advice])


func _collect_storage_warnings(warnings: Array[Dictionary], units: Array[Unit], buildings: Array[Building]):
	var warehouses: Array[Building] = []
	var stored_total := 0
	var capacity_total := 0
	for building in buildings:
		if building.is_warehouse() and building.is_completed():
			warehouses.append(building)
			stored_total += building.get_total_stored()
			capacity_total += building.storage_capacity
	var blocked_carriers := 0
	for unit in units:
		if unit.get_carried_total() <= 0 or is_instance_valid(unit.target_building):
			continue
		if not unit.continuous_harvest and unit.task not in [Unit.Task.DELIVER_TO_WAREHOUSE, Unit.Task.IDLE]:
			continue
		var can_store := false
		for warehouse in warehouses:
			if (unit.carried_wood > 0 and warehouse.has_resource_space(&"wood")) or (unit.carried_stone > 0 and warehouse.has_resource_space(&"stone")):
				can_store = true
				break
		if not can_store:
			blocked_carriers += 1
	if blocked_carriers > 0:
		_add_warning(warnings, 2, "%d юнитам некуда разгрузить ресурсы. Постройте склад или измените складские квоты." % blocked_carriers)
	elif not warehouses.is_empty() and capacity_total > 0 and stored_total >= capacity_total:
		_add_warning(warnings, 2, "Все склады заполнены. Расширьте складскую сеть или переработайте накопленные ресурсы.")
	elif warehouses.is_empty() and not units.is_empty():
		_add_warning(warnings, 1, "Нет готового склада: добытые ресурсы будет некуда складывать.")


func _collect_factory_warnings(warnings: Array[Dictionary], buildings: Array[Building]):
	var issue_counts := {}
	for building in buildings:
		for issue in building.get_factory_issues():
			var kind := StringName(issue.get("kind", &""))
			var resource := StringName(issue.get("resource", &""))
			var key := "%s:%s" % [kind, resource]
			issue_counts[key] = int(issue_counts.get(key, 0)) + 1
	for key in issue_counts:
		var parts := str(key).split(":", true, 1)
		var kind := StringName(parts[0])
		var resource := StringName(parts[1]) if parts.size() > 1 else &""
		var count := int(issue_counts[key])
		match kind:
			&"no_electricity":
				_add_warning(warnings, 2, "%d заводов остановлены: нет электричества. Запустите электростанцию и обеспечьте её углём." % count)
			&"no_workers":
				_add_warning(warnings, 1, "%d заводов ожидают работников. Увеличьте население или освободите занятых жителей." % count)
			&"output_full":
				_add_warning(warnings, 2, "%d заводов остановлены: на складах нет места для ресурса «%s»." % [count, Building.RESOURCE_NAMES.get(resource, str(resource))])
			&"missing_input":
				var advice := " Настройте шахту на добычу угля." if resource == &"coal" else ""
				_add_warning(warnings, 2, "%d заводов остановлены: не хватает ресурса «%s».%s" % [count, Building.RESOURCE_NAMES.get(resource, str(resource)), advice])


func _collect_housing_warnings(warnings: Array[Dictionary], units: Array[Unit], buildings: Array[Building]):
	var housing_capacity := 0
	var migration_target := 0
	for building in buildings:
		if building.is_residence() and building.is_completed():
			housing_capacity += building.max_occupants
		elif building is GovernmentBuilding and building.is_completed():
			migration_target = maxi(migration_target, building.migration_target)
	if migration_target > units.size() and housing_capacity <= units.size():
		_add_warning(warnings, 1, "Миграция остановлена: нет свободного жилья. Постройте жилые дома.")


func _collect_army_warnings(warnings: Array[Dictionary], units: Array[Unit]):
	var mobilized := 0
	var without_rifles := 0
	var without_armor := 0
	for unit in units:
		if not unit.is_mobilized:
			continue
		mobilized += 1
		without_rifles += 0 if unit.has_rifle else 1
		without_armor += 0 if unit.has_armor else 1
	if mobilized > 0 and without_rifles > 0:
		_add_warning(warnings, 1, "%d из %d солдат без автоматов. Настройте военный завод на их производство." % [without_rifles, mobilized])
	if mobilized > 0 and without_armor > mobilized / 2:
		_add_warning(warnings, 1, "%d из %d солдат без брони." % [without_armor, mobilized])


func _add_warning(warnings: Array[Dictionary], severity: int, message: String):
	warnings.append({"severity": severity, "message": message})


func _rebuild_messages(warnings: Array[Dictionary], total_warning_count: int):
	for child in messages.get_children():
		child.queue_free()
	active_warning_count = total_warning_count
	title.text = "Оповещения: %d" % active_warning_count
	for warning in warnings:
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%s %s" % [_get_severity_icon(int(warning.severity)), str(warning.message)]
		label.add_theme_color_override("font_color", _get_severity_color(int(warning.severity)))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		messages.add_child(label)
	_update_visibility()


func _toggle_notifications():
	if active_warning_count <= 0:
		return
	user_collapsed = not user_collapsed
	_update_visibility()


func _update_visibility():
	panel.visible = active_warning_count > 0 and not user_collapsed
	toggle_button.disabled = active_warning_count <= 0
	if panel.visible:
		toggle_button.text = "Скрыть оповещения"
	else:
		toggle_button.text = "Оповещения: %d" % active_warning_count


func _get_severity_icon(severity: int) -> String:
	if severity >= 3:
		return "●"
	if severity == 2:
		return "▲"
	return "◆"


func _get_severity_color(severity: int) -> Color:
	if severity >= 3:
		return SovereignUITheme.DANGER.lightened(0.12)
	if severity == 2:
		return Color("f0b95b")
	return SovereignUITheme.ACCENT_BRIGHT


func _get_local_faction_id() -> int:
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager) and network_manager.has_method("get_local_faction_id"):
		return int(network_manager.get_local_faction_id())
	return 0


func _get_faction_units(faction_id: int) -> Array:
	var index := world.get_node_or_null("WorldIndex") if is_instance_valid(world) else null
	if is_instance_valid(index):
		return index.get_units(faction_id)
	var result: Array[Unit] = []
	for candidate in get_tree().get_nodes_in_group("units"):
		if candidate is Unit and world.is_ancestor_of(candidate) and candidate.faction_id == faction_id:
			result.append(candidate)
	return result


func _get_faction_buildings(faction_id: int) -> Array:
	var index := world.get_node_or_null("WorldIndex") if is_instance_valid(world) else null
	if is_instance_valid(index):
		return index.get_buildings(faction_id)
	var result: Array[Building] = []
	for candidate in get_tree().get_nodes_in_group("buildings"):
		if candidate is Building and world.is_ancestor_of(candidate) and candidate.faction_id == faction_id:
			result.append(candidate)
	return result
