extends CanvasLayer

var selected_squad_id := 0
var selected_platoon_id := 0
var selected_front_line_id := ""
var selected_force_level: StringName = &"army"
var squad_list_key := ""
var front_line_list_key := ""
var current_ui_scale := -1.0
var refresh_timer := 0.0
var world_index: Node

@onready var launcher: Button = $Launcher
@onready var panel: PanelContainer = $Panel
@onready var actions: GridContainer = $Panel/Scroll/Content/Actions
@onready var orders: GridContainer = $Panel/Scroll/Content/Orders
@onready var title: Label = $Panel/Scroll/Content/Header/Title
@onready var close_button: Button = $Panel/Scroll/Content/Header/Close
@onready var summary: Label = $Panel/Scroll/Content/Summary
@onready var platoon_list: ItemList = $Panel/Scroll/Content/PlatoonList
@onready var platoon_details: Label = $Panel/Scroll/Content/PlatoonDetails
@onready var front_line_button: Button = $Panel/Scroll/Content/PlatoonPlans/FrontLine
@onready var offensive_line_button: Button = $Panel/Scroll/Content/PlatoonPlans/OffensiveLine
@onready var front_line_list: ItemList = $Panel/Scroll/Content/FrontLineList
@onready var attach_front_button: Button = $Panel/Scroll/Content/FrontAssignments/Attach
@onready var detach_front_button: Button = $Panel/Scroll/Content/FrontAssignments/Detach
@onready var delete_front_button: Button = $Panel/Scroll/Content/FrontAssignments/Delete
@onready var squad_list: ItemList = $Panel/Scroll/Content/SquadList
@onready var details: Label = $Panel/Scroll/Content/Details
@onready var organize_button: Button = $Panel/Scroll/Content/Actions/Organize
@onready var hold_button: Button = $Panel/Scroll/Content/Orders/Hold
@onready var spread_button: Button = $Panel/Scroll/Content/Orders/Spread
@onready var watch_button: Button = $Panel/Scroll/Content/Orders/Watch
@onready var regroup_button: Button = $Panel/Scroll/Content/Orders/Regroup
@onready var return_button: Button = $Panel/Scroll/Content/Orders/ReturnToBase


func _ready():
	var world := get_tree().current_scene
	world_index = world.get_node_or_null("WorldIndex") if is_instance_valid(world) else null
	current_ui_scale = SovereignUITheme.get_scale(get_viewport().get_visible_rect().size)
	var interface_theme := SovereignUITheme.create_theme(current_ui_scale)
	launcher.theme = interface_theme
	panel.theme = interface_theme
	launcher.pressed.connect(toggle_menu)
	close_button.pressed.connect(close_menu)
	platoon_list.item_selected.connect(_on_platoon_selected)
	platoon_list.item_activated.connect(_on_platoon_selected)
	front_line_list.item_selected.connect(_on_front_line_selected)
	front_line_list.item_activated.connect(_on_front_line_selected)
	squad_list.item_selected.connect(_on_squad_selected)
	squad_list.item_activated.connect(_on_squad_selected)
	organize_button.pressed.connect(_organize_army)
	hold_button.pressed.connect(_issue_order.bind(&"hold"))
	spread_button.pressed.connect(_issue_order.bind(&"spread_out"))
	watch_button.pressed.connect(_issue_order.bind(&"watch_directions"))
	regroup_button.pressed.connect(_issue_order.bind(&"regroup"))
	return_button.pressed.connect(_issue_order.bind(&"return_to_base"))
	front_line_button.pressed.connect(_begin_platoon_line.bind(&"front_line"))
	offensive_line_button.pressed.connect(_begin_platoon_line.bind(&"offensive_line"))
	attach_front_button.pressed.connect(_change_front_assignment.bind(&"attach"))
	detach_front_button.pressed.connect(_change_front_assignment.bind(&"detach"))
	delete_front_button.pressed.connect(_delete_selected_front)
	for button in [close_button, organize_button, front_line_button, offensive_line_button, attach_front_button, detach_front_button, delete_front_button, hold_button, spread_button, watch_button, regroup_button, return_button]:
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_update_layout()


func _process(delta: float):
	_update_layout()
	refresh_timer -= delta
	if panel.visible and refresh_timer <= 0.0:
		refresh_timer = 0.15
		_refresh_army()


func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		toggle_menu()
		get_viewport().set_input_as_handled()


func toggle_menu():
	panel.visible = not panel.visible
	launcher.text = "Закрыть войска (M)" if panel.visible else "Управление войсками (M)"
	if panel.visible:
		squad_list_key = ""
		front_line_list_key = ""
		_refresh_army()


func close_menu():
	panel.visible = false
	launcher.text = "Управление войсками (M)"


func _update_layout():
	var viewport_size := get_viewport().get_visible_rect().size
	var ui_scale := SovereignUITheme.get_scale(viewport_size)
	if not is_equal_approx(current_ui_scale, ui_scale):
		current_ui_scale = ui_scale
		var interface_theme := SovereignUITheme.create_theme(ui_scale)
		launcher.theme = interface_theme
		panel.theme = interface_theme
	var compact := viewport_size.x < 520.0 or viewport_size.y < 420.0
	launcher.text = ("Закрыть (M)" if panel.visible else "Войска (M)") if compact else ("Закрыть войска (M)" if panel.visible else "Управление войсками (M)")
	var launcher_width := minf(116.0 if compact else 205.0, maxf(viewport_size.x - 16.0, 1.0))
	launcher.custom_minimum_size = Vector2(launcher_width, 32.0)
	launcher.add_theme_font_size_override("font_size", 13 if compact else 14)
	launcher.size = launcher.custom_minimum_size
	launcher.position = Vector2(maxf((viewport_size.x - launcher.size.x) * 0.5, 8.0), maxf(viewport_size.y - launcher.size.y - 8.0, 8.0))
	if not panel.visible:
		return
	var panel_width := minf(330.0 * ui_scale, maxf(viewport_size.x - 16.0, 1.0))
	var panel_height := minf(590.0 * ui_scale, maxf(viewport_size.y - 80.0, 1.0))
	var panel_size := Vector2(panel_width, panel_height)
	panel.custom_minimum_size = Vector2.ZERO
	panel.position = Vector2(maxf(viewport_size.x - panel_size.x - 8.0, 8.0), maxf((viewport_size.y - panel_size.y) * 0.5, 8.0))
	panel.size = panel_size
	actions.columns = 1
	orders.columns = 1 if panel_size.x < 260.0 else 2
	var list_height := 76.0 if compact else 112.0
	squad_list.custom_minimum_size.y = list_height * ui_scale
	platoon_list.custom_minimum_size.y = (64.0 if compact else 92.0) * ui_scale
	front_line_list.custom_minimum_size.y = (64.0 if compact else 92.0) * ui_scale
	details.custom_minimum_size.y = (58.0 if compact else 76.0) * ui_scale
	platoon_details.custom_minimum_size.y = (48.0 if compact else 58.0) * ui_scale
	title.add_theme_font_size_override("font_size", maxi(roundi(17.0 * ui_scale), 12))


func _refresh_army():
	var soldiers := _get_local_soldiers()
	var squads := _group_soldiers_by_squad(soldiers)
	var platoons := _group_soldiers_by_platoon(soldiers)
	var front_lines: Array[Dictionary] = []
	var current_world := get_tree().current_scene
	if is_instance_valid(current_world) and current_world.has_method("get_military_front_lines"):
		front_lines.assign(current_world.get_military_front_lines(_get_local_faction_id()))
	var armored := 0
	var armed := 0
	var at_base := 0
	for soldier in soldiers:
		armored += 1 if soldier.has_armor else 0
		armed += 1 if soldier.has_rifle else 0
		at_base += 1 if is_instance_valid(soldier.inside_building) and soldier.inside_building.is_barracks() else 0
	summary.text = "Мобилизовано: %d • Взводов: %d • Отрядов: %d • На базе: %d\nБроня: %d/%d • Автоматы: %d/%d" % [soldiers.size(), platoons.size(), squads.size(), at_base, armored, soldiers.size(), armed, soldiers.size()]
	var new_key := _make_squad_list_key(soldiers)
	if new_key != squad_list_key:
		squad_list_key = new_key
		_rebuild_platoon_list(platoons)
		_rebuild_squad_list(squads)
	var new_front_key := _make_front_line_list_key(front_lines)
	if new_front_key != front_line_list_key:
		front_line_list_key = new_front_key
		_rebuild_front_line_list(front_lines)
	_refresh_selected_platoon(platoons)
	_refresh_selected_squad(squads)


func _rebuild_platoon_list(platoons: Dictionary):
	platoon_list.clear()
	var platoon_ids: Array = platoons.keys()
	platoon_ids.sort()
	if not platoon_ids.is_empty():
		var all_index := platoon_list.add_item("Вся армия • %d взводов" % platoon_ids.size())
		platoon_list.set_item_metadata(all_index, 0)
		if selected_platoon_id == 0:
			platoon_list.select(all_index)
	for platoon_id_value in platoon_ids:
		var platoon_id := int(platoon_id_value)
		var members: Array = platoons[platoon_id]
		var commander := _find_platoon_commander(members)
		var squad_count := _group_soldiers_by_squad(members).size()
		var commander_name := commander.unit_name if is_instance_valid(commander) else "не назначен"
		var index := platoon_list.add_item("Взвод %d • %d отр. • %s" % [platoon_id, squad_count, commander_name])
		platoon_list.set_item_metadata(index, platoon_id)
		if platoon_id == selected_platoon_id:
			platoon_list.select(index)
	if selected_platoon_id > 0 and not platoons.has(selected_platoon_id):
		selected_platoon_id = 0
		if platoon_list.item_count > 0:
			platoon_list.select(0)


func _rebuild_squad_list(squads: Dictionary):
	squad_list.clear()
	var squad_ids: Array = squads.keys()
	squad_ids.sort()
	for squad_id_value in squad_ids:
		var squad_id := int(squad_id_value)
		var members: Array = squads[squad_id]
		var commander := _find_squad_commander(members)
		var commander_name := commander.unit_name if is_instance_valid(commander) else "не назначен"
		var index := squad_list.add_item("Отряд %d • %d/%d • %s" % [squad_id, members.size(), GovernmentBuilding.SQUAD_SIZE, commander_name])
		squad_list.set_item_metadata(index, squad_id)
		if squad_id == selected_squad_id:
			squad_list.select(index)
	if selected_squad_id <= 0 or not squads.has(selected_squad_id):
		selected_squad_id = int(squad_ids[0]) if not squad_ids.is_empty() else 0
		if squad_list.item_count > 0:
			squad_list.select(0)


func _rebuild_front_line_list(front_lines: Array[Dictionary]):
	front_line_list.clear()
	var selected_found := false
	for plan in front_lines:
		var line_id := str(plan.get("line_id", ""))
		var attached_squads: Array = plan.get("squad_ids", [])
		var attached_count := attached_squads.size()
		var offensive_marker := " • наступление" if bool(plan.get("has_offensive", false)) else ""
		var index := front_line_list.add_item("%s • %d отр.%s" % [str(plan.get("name", "Линия фронта")), attached_count, offensive_marker])
		front_line_list.set_item_metadata(index, line_id)
		if line_id == selected_front_line_id:
			front_line_list.select(index)
			selected_found = true
	if not selected_found:
		selected_front_line_id = str(front_lines[0].get("line_id", "")) if not front_lines.is_empty() else ""
		if front_line_list.item_count > 0:
			front_line_list.select(0)


func _refresh_selected_squad(squads: Dictionary):
	var members: Array = squads.get(selected_squad_id, [])
	var has_squad := not members.is_empty()
	for button in [hold_button, spread_button, watch_button, regroup_button, return_button]:
		button.disabled = not has_squad
	organize_button.disabled = not is_instance_valid(_find_local_government())
	if not has_squad:
		details.text = "Отряды пока не сформированы. Мобилизуйте людей и нажмите «Переформировать»."
		return
	var commander := _find_squad_commander(members)
	var armored := 0
	var armed := 0
	var at_base := 0
	for member in members:
		armored += 1 if member.has_armor else 0
		armed += 1 if member.has_rifle else 0
		at_base += 1 if is_instance_valid(member.inside_building) and member.inside_building.is_barracks() else 0
	var order_text := commander.get_military_order_name() if is_instance_valid(commander) else "нет командира"
	var commander_name := commander.unit_name if is_instance_valid(commander) else "не назначен"
	details.text = "Командир: %s • приказ: %s\nНа базе: %d/%d • броня: %d/%d • автоматы: %d/%d" % [commander_name, order_text, at_base, members.size(), armored, members.size(), armed, members.size()]


func _refresh_selected_platoon(platoons: Dictionary):
	var members := _get_selected_platoon_members(platoons)
	var commanders := _find_platoon_commanders(members)
	var has_platoon := not commanders.is_empty()
	front_line_button.disabled = not has_platoon
	offensive_line_button.disabled = selected_front_line_id.is_empty()
	attach_front_button.disabled = selected_front_line_id.is_empty() or _get_selected_squad_commanders().is_empty()
	detach_front_button.disabled = attach_front_button.disabled
	delete_front_button.disabled = selected_front_line_id.is_empty()
	if not has_platoon:
		platoon_details.text = "Взводы пока не сформированы."
		return
	var squad_count := _group_soldiers_by_squad(members).size()
	if selected_platoon_id == 0:
		platoon_details.text = "Вся армия: %d взводов • %d отрядов\nВыберите план фронта или отдельный взвод/отряд." % [commanders.size(), squad_count]
	else:
		var commander := commanders[0]
		platoon_details.text = "Командир взвода: %s • отрядов: %d\nМожно прикрепить весь взвод к выбранной линии." % [commander.unit_name, squad_count]


func _on_platoon_selected(index: int):
	if index >= 0 and index < platoon_list.item_count:
		selected_platoon_id = int(platoon_list.get_item_metadata(index))
		selected_force_level = &"army" if selected_platoon_id == 0 else &"platoon"
		_refresh_army()
		_select_current_platoon(true)


func _on_squad_selected(index: int):
	if index >= 0 and index < squad_list.item_count:
		selected_squad_id = int(squad_list.get_item_metadata(index))
		selected_force_level = &"squad"
		var members: Array = _group_soldiers_by_squad(_get_local_soldiers()).get(selected_squad_id, [])
		if not members.is_empty():
			selected_platoon_id = members[0].platoon_id
		_refresh_army()
		_select_current_squad(true)


func _on_front_line_selected(index: int):
	if index >= 0 and index < front_line_list.item_count:
		selected_front_line_id = str(front_line_list.get_item_metadata(index))
		_refresh_army()


func _select_current_platoon(focus_camera := false):
	var members: Array[Unit] = []
	for soldier in _get_local_soldiers():
		if selected_platoon_id == 0 or soldier.platoon_id == selected_platoon_id:
			members.append(soldier)
	Unit.set_selection(members)
	if not focus_camera or members.is_empty():
		return
	var commanders := _find_platoon_commanders(members)
	var commander: Unit = commanders[0] if not commanders.is_empty() else null
	var focus_unit := commander if is_instance_valid(commander) else members[0]
	var current_world := get_tree().current_scene
	var camera: Camera2D
	if is_instance_valid(current_world):
		camera = current_world.get_node_or_null("Camera2D") as Camera2D
	if is_instance_valid(camera):
		camera.global_position = focus_unit.global_position


func _select_current_squad(focus_camera := false):
	var members: Array[Unit] = []
	for soldier in _get_local_soldiers():
		if soldier.squad_id == selected_squad_id:
			members.append(soldier)
	Unit.set_selection(members)
	if not focus_camera or members.is_empty():
		return
	var commander := _find_squad_commander(members)
	var focus_unit := commander if is_instance_valid(commander) else members[0]
	var current_world := get_tree().current_scene
	var camera: Camera2D
	if is_instance_valid(current_world):
		camera = current_world.get_node_or_null("Camera2D") as Camera2D
	if is_instance_valid(camera):
		camera.global_position = focus_unit.global_position


func _organize_army():
	var government := _find_local_government()
	if is_instance_valid(government) and government.can_be_edited_locally():
		var network_manager := get_node_or_null("/root/NetworkManager")
		if is_instance_valid(network_manager):
			network_manager.request_building_action(government, &"organize_army")
		squad_list_key = ""
		_refresh_army()


func _issue_order(order: StringName):
	for commander in _get_selected_squad_commanders():
		commander.request_squad_order(order)
	squad_list_key = ""
	_refresh_army()


func _begin_platoon_line(line_type: StringName):
	var commanders := _get_selected_squad_commanders()
	var current_world := get_tree().current_scene
	var build_manager := current_world.get_node_or_null("BuildManager") if is_instance_valid(current_world) else null
	var target_line_id := selected_front_line_id if line_type == &"offensive_line" else ""
	if is_instance_valid(build_manager) and build_manager.begin_platoon_line_drawing(commanders, line_type, target_line_id):
		close_menu()


func _change_front_assignment(action: StringName):
	if selected_front_line_id.is_empty():
		return
	var commanders := _get_selected_squad_commanders()
	var network_manager := get_node_or_null("/root/NetworkManager")
	if not commanders.is_empty() and is_instance_valid(network_manager):
		network_manager.request_unit_command(commanders, &"military_plan", {
			"plan_action": action,
			"line_id": selected_front_line_id,
		})
		front_line_list_key = ""
		_refresh_army()


func _delete_selected_front():
	if selected_front_line_id.is_empty():
		return
	var commanders := _get_selected_squad_commanders()
	if commanders.is_empty():
		commanders = _find_all_squad_commanders(_get_local_soldiers())
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		var command_units: Array = [commanders[0]] if not commanders.is_empty() else []
		network_manager.request_unit_command(command_units, &"military_plan", {
			"plan_action": &"delete",
			"line_id": selected_front_line_id,
		})
		selected_front_line_id = ""
		front_line_list_key = ""
		_refresh_army()


func _get_local_soldiers() -> Array[Unit]:
	var soldiers: Array[Unit] = []
	var faction_id := _get_local_faction_id()
	var units: Array = world_index.get_units(faction_id) if is_instance_valid(world_index) else get_tree().get_nodes_in_group("units")
	for unit in units:
		if unit is Unit and unit.faction_id == faction_id and unit.is_mobilized and unit.can_be_controlled_locally():
			soldiers.append(unit)
	soldiers.sort_custom(func(a: Unit, b: Unit): return a.network_id < b.network_id)
	return soldiers


func _get_selected_squad_commanders() -> Array[Unit]:
	var selected_members: Array[Unit] = []
	for soldier in _get_local_soldiers():
		match selected_force_level:
			&"squad":
				if soldier.squad_id == selected_squad_id:
					selected_members.append(soldier)
			&"platoon":
				if soldier.platoon_id == selected_platoon_id:
					selected_members.append(soldier)
			_:
				selected_members.append(soldier)
	return _find_all_squad_commanders(selected_members)


func _find_all_squad_commanders(members: Array) -> Array[Unit]:
	var commanders: Array[Unit] = []
	for member in members:
		if member is Unit and member.is_squad_commander() and member not in commanders:
			commanders.append(member)
	commanders.sort_custom(func(a: Unit, b: Unit):
		return a.platoon_id < b.platoon_id if a.platoon_id != b.platoon_id else a.squad_id < b.squad_id
	)
	return commanders


func _group_soldiers_by_squad(soldiers: Array) -> Dictionary:
	var squads := {}
	for soldier in soldiers:
		if soldier.squad_id <= 0:
			continue
		if not squads.has(soldier.squad_id):
			squads[soldier.squad_id] = []
		squads[soldier.squad_id].append(soldier)
	return squads


func _group_soldiers_by_platoon(soldiers: Array) -> Dictionary:
	var platoons := {}
	for soldier in soldiers:
		if soldier.platoon_id <= 0:
			continue
		if not platoons.has(soldier.platoon_id):
			platoons[soldier.platoon_id] = []
		platoons[soldier.platoon_id].append(soldier)
	return platoons


func _get_selected_platoon_members(platoons: Dictionary) -> Array[Unit]:
	var members: Array[Unit] = []
	if selected_platoon_id > 0:
		members.assign(platoons.get(selected_platoon_id, []))
		return members
	var platoon_ids: Array = platoons.keys()
	platoon_ids.sort()
	for platoon_id in platoon_ids:
		for member in platoons[platoon_id]:
			if member is Unit:
				members.append(member)
	return members


func _find_squad_commander(members: Array) -> Unit:
	for member in members:
		if member is Unit and member.network_id == member.squad_commander_network_id:
			return member
	return members[0] as Unit if not members.is_empty() else null


func _find_platoon_commander(members: Array) -> Unit:
	for member in members:
		if member is Unit and member.network_id == member.platoon_commander_network_id:
			return member
	return null


func _find_platoon_commanders(members: Array) -> Array[Unit]:
	var commanders: Array[Unit] = []
	for member in members:
		if member is Unit and member.is_platoon_commander() and member not in commanders:
			commanders.append(member)
	commanders.sort_custom(func(a: Unit, b: Unit): return a.platoon_id < b.platoon_id)
	return commanders


func _find_local_government() -> GovernmentBuilding:
	var faction_id := _get_local_faction_id()
	var buildings: Array = world_index.get_buildings(faction_id, "government") if is_instance_valid(world_index) else get_tree().get_nodes_in_group("buildings")
	for building in buildings:
		if building is GovernmentBuilding and building.faction_id == faction_id and building.is_completed():
			return building
	return null


func _get_local_faction_id() -> int:
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		return int(network_manager.get_local_faction_id())
	return 0


func _make_squad_list_key(soldiers: Array[Unit]) -> String:
	var parts := PackedStringArray()
	for soldier in soldiers:
		parts.append("%d:%d:%d:%s:%d:%d:%d:%d:%d:%d" % [soldier.network_id, soldier.squad_id, soldier.platoon_id, soldier.military_order, soldier.health, int(soldier.has_armor), int(soldier.has_rifle), int(soldier.has_platoon_front_line), int(soldier.has_platoon_offensive_line), soldier.inside_building.get_instance_id() if is_instance_valid(soldier.inside_building) else 0])
	return "|".join(parts)


func _make_front_line_list_key(front_lines: Array[Dictionary]) -> String:
	var parts := PackedStringArray()
	for plan in front_lines:
		parts.append("%s:%d:%d:%d" % [
			str(plan.get("line_id", "")),
			plan.get("front_points", []).size(),
			plan.get("squad_ids", []).size(),
			int(bool(plan.get("has_offensive", false))),
		])
	return "|".join(parts)
