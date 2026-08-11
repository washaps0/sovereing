extends CanvasLayer

var selected_squad_id := 0
var squad_list_key := ""
var current_ui_scale := -1.0

@onready var launcher: Button = $Launcher
@onready var panel: PanelContainer = $Panel
@onready var actions: GridContainer = $Panel/Scroll/Content/Actions
@onready var orders: GridContainer = $Panel/Scroll/Content/Orders
@onready var title: Label = $Panel/Scroll/Content/Header/Title
@onready var close_button: Button = $Panel/Scroll/Content/Header/Close
@onready var summary: Label = $Panel/Scroll/Content/Summary
@onready var squad_list: ItemList = $Panel/Scroll/Content/SquadList
@onready var details: Label = $Panel/Scroll/Content/Details
@onready var select_button: Button = $Panel/Scroll/Content/Actions/SelectSquad
@onready var organize_button: Button = $Panel/Scroll/Content/Actions/Organize
@onready var hold_button: Button = $Panel/Scroll/Content/Orders/Hold
@onready var spread_button: Button = $Panel/Scroll/Content/Orders/Spread
@onready var watch_button: Button = $Panel/Scroll/Content/Orders/Watch
@onready var regroup_button: Button = $Panel/Scroll/Content/Orders/Regroup
@onready var return_button: Button = $Panel/Scroll/Content/Orders/ReturnToBase


func _ready():
	current_ui_scale = SovereignUITheme.get_scale(get_viewport().get_visible_rect().size)
	var interface_theme := SovereignUITheme.create_theme(current_ui_scale)
	launcher.theme = interface_theme
	panel.theme = interface_theme
	launcher.pressed.connect(toggle_menu)
	close_button.pressed.connect(close_menu)
	squad_list.item_selected.connect(_on_squad_selected)
	squad_list.item_activated.connect(func(_index): _select_current_squad())
	select_button.pressed.connect(_select_current_squad)
	organize_button.pressed.connect(_organize_army)
	hold_button.pressed.connect(_issue_order.bind(&"hold"))
	spread_button.pressed.connect(_issue_order.bind(&"spread_out"))
	watch_button.pressed.connect(_issue_order.bind(&"watch_directions"))
	regroup_button.pressed.connect(_issue_order.bind(&"regroup"))
	return_button.pressed.connect(_issue_order.bind(&"return_to_base"))
	for button in [close_button, select_button, organize_button, hold_button, spread_button, watch_button, regroup_button, return_button]:
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_update_layout()


func _process(_delta: float):
	_update_layout()
	if panel.visible:
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
	var panel_size := Vector2(minf(460.0 * ui_scale, maxf(viewport_size.x - 16.0, 1.0)), minf(540.0 * ui_scale, maxf(viewport_size.y - 16.0, 1.0)))
	panel.custom_minimum_size = Vector2.ZERO
	panel.position = (viewport_size - panel_size) * 0.5
	panel.size = panel_size
	actions.columns = 1 if panel_size.x < 340.0 else 2
	orders.columns = 1 if panel_size.x < 340.0 else 2
	var list_height := 80.0 if compact else 125.0
	squad_list.custom_minimum_size.y = list_height * ui_scale
	details.custom_minimum_size.y = list_height * ui_scale
	title.add_theme_font_size_override("font_size", maxi(roundi(17.0 * ui_scale), 12))


func _refresh_army():
	var soldiers := _get_local_soldiers()
	var squads := _group_soldiers_by_squad(soldiers)
	var armored := 0
	var armed := 0
	var at_base := 0
	for soldier in soldiers:
		armored += 1 if soldier.has_armor else 0
		armed += 1 if soldier.has_rifle else 0
		at_base += 1 if is_instance_valid(soldier.inside_building) and soldier.inside_building.is_barracks() else 0
	summary.text = "Мобилизовано: %d • Отрядов: %d • На базе: %d\nБроня: %d/%d • Автоматы: %d/%d" % [soldiers.size(), squads.size(), at_base, armored, soldiers.size(), armed, soldiers.size()]
	var new_key := _make_squad_list_key(soldiers)
	if new_key != squad_list_key:
		squad_list_key = new_key
		_rebuild_squad_list(squads)
	_refresh_selected_squad(squads)


func _rebuild_squad_list(squads: Dictionary):
	squad_list.clear()
	var squad_ids: Array = squads.keys()
	squad_ids.sort()
	for squad_id_value in squad_ids:
		var squad_id := int(squad_id_value)
		var members: Array = squads[squad_id]
		var commander := _find_squad_commander(members)
		var commander_name := commander.unit_name if is_instance_valid(commander) else "не назначен"
		var index := squad_list.add_item("Отряд %d — %d/%d • командир: %s" % [squad_id, members.size(), GovernmentBuilding.SQUAD_SIZE, commander_name])
		squad_list.set_item_metadata(index, squad_id)
		if squad_id == selected_squad_id:
			squad_list.select(index)
	if selected_squad_id <= 0 or not squads.has(selected_squad_id):
		selected_squad_id = int(squad_ids[0]) if not squad_ids.is_empty() else 0
		if squad_list.item_count > 0:
			squad_list.select(0)


func _refresh_selected_squad(squads: Dictionary):
	var members: Array = squads.get(selected_squad_id, [])
	var has_squad := not members.is_empty()
	for button in [select_button, hold_button, spread_button, watch_button, regroup_button, return_button]:
		button.disabled = not has_squad
	organize_button.disabled = not is_instance_valid(_find_local_government())
	if not has_squad:
		details.text = "Отряды пока не сформированы. Мобилизуйте людей и нажмите «Переформировать»."
		return
	var commander := _find_squad_commander(members)
	var armored := 0
	var armed := 0
	var at_base := 0
	var member_lines := PackedStringArray()
	for member in members:
		armored += 1 if member.has_armor else 0
		armed += 1 if member.has_rifle else 0
		at_base += 1 if is_instance_valid(member.inside_building) and member.inside_building.is_barracks() else 0
		var equipment := "%s%s" % ["броня " if member.has_armor else "", "автомат" if member.has_rifle else ""]
		if equipment.strip_edges().is_empty():
			equipment = "без снаряжения"
		member_lines.append("• %s — %s, %s" % [member.unit_name, member.military_rank, equipment.strip_edges()])
	var order_text := commander.get_military_order_name() if is_instance_valid(commander) else "нет командира"
	var commander_name := commander.unit_name if is_instance_valid(commander) else "не назначен"
	details.text = "Командир: %s\nПриказ: %s\nНа базе: %d/%d • Броня: %d/%d • Автоматы: %d/%d\n%s" % [commander_name, order_text, at_base, members.size(), armored, members.size(), armed, members.size(), "\n".join(member_lines)]


func _on_squad_selected(index: int):
	if index >= 0 and index < squad_list.item_count:
		selected_squad_id = int(squad_list.get_item_metadata(index))
		_refresh_army()


func _select_current_squad():
	var members: Array[Unit] = []
	for soldier in _get_local_soldiers():
		if soldier.squad_id == selected_squad_id:
			members.append(soldier)
	Unit.set_selection(members)


func _organize_army():
	var government := _find_local_government()
	if is_instance_valid(government) and government.can_be_edited_locally():
		government.organize_army()
		squad_list_key = ""
		_refresh_army()


func _issue_order(order: StringName):
	var members: Array = _group_soldiers_by_squad(_get_local_soldiers()).get(selected_squad_id, [])
	var commander := _find_squad_commander(members)
	if is_instance_valid(commander) and commander.issue_squad_order(order):
		squad_list_key = ""
		_refresh_army()


func _get_local_soldiers() -> Array[Unit]:
	var soldiers: Array[Unit] = []
	var faction_id := _get_local_faction_id()
	for unit in get_tree().get_nodes_in_group("units"):
		if unit is Unit and unit.faction_id == faction_id and unit.is_mobilized and unit.can_be_controlled_locally():
			soldiers.append(unit)
	soldiers.sort_custom(func(a: Unit, b: Unit): return a.network_id < b.network_id)
	return soldiers


func _group_soldiers_by_squad(soldiers: Array[Unit]) -> Dictionary:
	var squads := {}
	for soldier in soldiers:
		if soldier.squad_id <= 0:
			continue
		if not squads.has(soldier.squad_id):
			squads[soldier.squad_id] = []
		squads[soldier.squad_id].append(soldier)
	return squads


func _find_squad_commander(members: Array) -> Unit:
	for member in members:
		if member is Unit and member.network_id == member.squad_commander_network_id:
			return member
	return members[0] as Unit if not members.is_empty() else null


func _find_local_government() -> GovernmentBuilding:
	var faction_id := _get_local_faction_id()
	for building in get_tree().get_nodes_in_group("buildings"):
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
		parts.append("%d:%d:%s:%d:%d:%d:%d" % [soldier.network_id, soldier.squad_id, soldier.military_order, soldier.health, int(soldier.has_armor), int(soldier.has_rifle), soldier.inside_building.get_instance_id() if is_instance_valid(soldier.inside_building) else 0])
	return "|".join(parts)
