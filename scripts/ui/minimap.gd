class_name Minimap
extends Control

@export var world_size := Vector2(12800.0, 12800.0)
@export_range(0.02, 1.0, 0.01) var refresh_interval := 0.08
@export var background_color := Color("183c2b")
@export var road_color := Color("c5cbd0a8")
@export var camera_fill_color := Color("ffffff24")
@export var camera_border_color := Color("ffffffe6")
@export_range(80.0, 260.0, 1.0) var minimum_map_size := 96.0
@export_range(80.0, 320.0, 1.0) var maximum_map_size := 180.0

var world: Node2D
var camera: Camera2D
var panel: PanelContainer
var title: Label
var refresh_timer := 0.0
var dragging := false
var current_ui_scale := -1.0
var last_viewport_size := Vector2.ZERO
var world_index: Node


func _ready():
	world = get_tree().current_scene as Node2D
	if is_instance_valid(world):
		camera = world.get_node_or_null("Camera2D") as Camera2D
		world_index = world.get_node_or_null("WorldIndex")
	panel = get_parent().get_parent() as PanelContainer
	title = get_parent().get_node_or_null("Title") as Label
	if is_instance_valid(panel):
		current_ui_scale = SovereignUITheme.get_scale(get_viewport_rect().size)
		panel.theme = SovereignUITheme.create_theme(current_ui_scale)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_update_layout()
	queue_redraw()


func _process(delta: float):
	var viewport_size := get_viewport_rect().size
	if viewport_size != last_viewport_size:
		_update_layout()
	refresh_timer -= delta
	if refresh_timer <= 0.0:
		refresh_timer = refresh_interval
		queue_redraw()


func _update_layout():
	if not is_instance_valid(panel):
		return
	var viewport_size := get_viewport_rect().size
	last_viewport_size = viewport_size
	var ui_scale := SovereignUITheme.get_scale(viewport_size)
	if not is_equal_approx(current_ui_scale, ui_scale):
		current_ui_scale = ui_scale
		panel.theme = SovereignUITheme.create_theme(ui_scale)
	var available_width := maxf(viewport_size.x - 24.0, 1.0)
	var title_visible := viewport_size.y >= 300.0 and viewport_size.x >= 300.0
	if is_instance_valid(title):
		title.visible = title_visible
	var vertical_reserve := 48.0 if title_visible else 24.0
	var available_height := maxf(viewport_size.y - vertical_reserve, 1.0)
	var desired_size := clampf(minf(viewport_size.x * 0.22, viewport_size.y * 0.26), minimum_map_size, maximum_map_size)
	var map_size := minf(desired_size, minf(available_width, available_height))
	custom_minimum_size = Vector2.ONE * map_size
	var padding := 18.0 * ui_scale
	var title_height := 20.0 * ui_scale if title_visible else 0.0
	var panel_size := Vector2(map_size + padding, map_size + padding + title_height)
	panel.offset_right = -8.0
	panel.offset_bottom = -8.0
	panel.offset_left = panel.offset_right - panel_size.x
	panel.offset_top = panel.offset_bottom - panel_size.y


func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		if event.pressed:
			_move_camera_to_map_point(event.position)
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		_move_camera_to_map_point(event.position)
		accept_event()


func _draw():
	var map_rect := _get_map_rect()
	draw_rect(map_rect, background_color, true)
	_draw_roads(map_rect)
	_draw_buildings(map_rect)
	_draw_units(map_rect)
	_draw_camera_view(map_rect)
	draw_rect(map_rect, Color("6d8792"), false, 1.0)


func _draw_roads(map_rect: Rect2):
	if not is_instance_valid(world):
		return
	var roads: Array = world_index.get_buildings(-1, "road") if is_instance_valid(world_index) else get_tree().get_nodes_in_group("roads")
	for candidate in roads:
		if candidate is not RoadSegment or not world.is_ancestor_of(candidate):
			continue
		var road := candidate as RoadSegment
		var endpoints := road.get_endpoints()
		var color := road_color
		if road.under_construction:
			color.a *= 0.4
		draw_line(_world_to_map(endpoints[0], map_rect), _world_to_map(endpoints[1], map_rect), color, 1.0)


func _draw_buildings(map_rect: Rect2):
	if not is_instance_valid(world):
		return
	var buildings: Array = world_index.get_buildings() if is_instance_valid(world_index) else get_tree().get_nodes_in_group("buildings")
	for candidate in buildings:
		if candidate is not Building or candidate is RoadSegment or not world.is_ancestor_of(candidate):
			continue
		var building := candidate as Building
		var marker_position := _world_to_map(building.global_position, map_rect)
		var marker_color := _get_faction_color(building.faction_id)
		if building.under_construction:
			marker_color.a = 0.45
		draw_rect(Rect2(marker_position - Vector2.ONE * 2.0, Vector2.ONE * 4.0), marker_color, true)


func _draw_units(map_rect: Rect2):
	if not is_instance_valid(world):
		return
	var units: Array = world_index.get_units() if is_instance_valid(world_index) else get_tree().get_nodes_in_group("units")
	for candidate in units:
		if candidate is not Unit or not world.is_ancestor_of(candidate):
			continue
		var unit := candidate as Unit
		var marker_position := _world_to_map(unit.global_position, map_rect)
		draw_circle(marker_position, 1.5, _get_faction_color(unit.faction_id))


func _draw_camera_view(map_rect: Rect2):
	if not is_instance_valid(camera):
		return
	var safe_zoom := Vector2(maxf(absf(camera.zoom.x), 0.001), maxf(absf(camera.zoom.y), 0.001))
	var camera_world_size := camera.get_viewport_rect().size / safe_zoom
	var camera_world_rect := Rect2(camera.global_position - camera_world_size * 0.5, camera_world_size)
	var world_rect := Rect2(Vector2.ZERO, world_size)
	var visible_world_rect := camera_world_rect.intersection(world_rect)
	if visible_world_rect.size.x <= 0.0 or visible_world_rect.size.y <= 0.0:
		return
	var view_position := _world_to_map(visible_world_rect.position, map_rect)
	var view_size := visible_world_rect.size / world_size * map_rect.size
	var view_rect := Rect2(view_position, view_size)
	draw_rect(view_rect, camera_fill_color, true)
	draw_rect(view_rect, camera_border_color, false, 1.5)


func _move_camera_to_map_point(local_point: Vector2):
	if not is_instance_valid(camera):
		return
	var map_rect := _get_map_rect()
	var clamped_point := Vector2(
		clampf(local_point.x, map_rect.position.x, map_rect.end.x),
		clampf(local_point.y, map_rect.position.y, map_rect.end.y)
	)
	var normalized_position := (clamped_point - map_rect.position) / map_rect.size
	var target := normalized_position * world_size
	var safe_zoom := Vector2(maxf(absf(camera.zoom.x), 0.001), maxf(absf(camera.zoom.y), 0.001))
	var half_view := camera.get_viewport_rect().size / safe_zoom * 0.5
	for axis in range(2):
		if half_view[axis] * 2.0 >= world_size[axis]:
			target[axis] = world_size[axis] * 0.5
		else:
			target[axis] = clampf(target[axis], half_view[axis], world_size[axis] - half_view[axis])
	camera.global_position = target
	queue_redraw()


func _get_map_rect() -> Rect2:
	var safe_world_size := Vector2(maxf(world_size.x, 1.0), maxf(world_size.y, 1.0))
	var map_scale := minf(size.x / safe_world_size.x, size.y / safe_world_size.y)
	var displayed_size := safe_world_size * map_scale
	return Rect2((size - displayed_size) * 0.5, displayed_size)


func _world_to_map(world_position: Vector2, map_rect: Rect2) -> Vector2:
	var normalized_position := world_position / world_size
	return map_rect.position + normalized_position * map_rect.size


func _get_faction_color(faction_id: int) -> Color:
	return Unit.FACTION_COLORS[posmod(faction_id, Unit.FACTION_COLORS.size())]
