class_name TacticalOverlay
extends Node2D

const UNIT_TEXTURE := preload("res://assets/char/character.png")

var selection_visible := false
var selection_start := Vector2.ZERO
var selection_end := Vector2.ZERO
var formation_points: Array[Vector2] = []
var platoon_plans: Array[Dictionary] = []
var order_line_preview_visible := false
var order_line_preview_points: Array[Vector2] = []
var order_line_preview_type: StringName = &"front_line"


func _draw():
	if selection_visible:
		var rect := Rect2(selection_start, selection_end - selection_start).abs()
		draw_rect(rect, Color(0.15, 0.65, 1.0, 0.22), true)
		draw_rect(rect, Color(0.4, 0.9, 1.0, 1.0), false, 2.0)
	for point in formation_points:
		var preview_rect := Rect2(point - Vector2(8, 8), Vector2(16, 16))
		draw_texture_rect(UNIT_TEXTURE, preview_rect, false, Color(1.0, 1.0, 1.0, 0.48))
		draw_arc(point, 9.0, 0.0, TAU, 20, Color(0.35, 1.0, 0.5, 0.85), 1.0)
	for plan in platoon_plans:
		var front_points := _as_vector_points(plan.get("front_points", []))
		var offensive_points := _as_vector_points(plan.get("offensive_points", []))
		var has_front := front_points.size() >= 2
		var has_offensive := bool(plan.get("has_offensive", false))
		var offensive_active := bool(plan.get("offensive_active", false))
		if has_front:
			_draw_order_polyline(front_points, Color(0.15, 0.75, 1.0, 0.92), 5.0)
		if has_offensive and offensive_points.size() >= 2:
			var offensive_color := Color(1.0, 0.2, 0.08, 0.98) if offensive_active else Color(1.0, 0.62, 0.18, 0.72)
			_draw_order_polyline(offensive_points, offensive_color, 5.0)
		if has_front and offensive_active and offensive_points.size() >= 2:
			var offensive_center := _polyline_center(offensive_points)
			_draw_advance_arrow(_nearest_polyline_point(front_points, offensive_center), offensive_center)
	if order_line_preview_visible and order_line_preview_points.size() >= 2:
		var preview_color := Color(1.0, 0.4, 0.15, 0.9) if order_line_preview_type == &"offensive_line" else Color(0.2, 0.85, 1.0, 0.9)
		_draw_order_polyline(order_line_preview_points, preview_color, 4.0)


func _draw_order_polyline(points: Array[Vector2], color: Color, width: float):
	var packed := PackedVector2Array(points)
	draw_polyline(packed, Color(0.02, 0.05, 0.08, 0.8), width + 3.0, true)
	draw_polyline(packed, color, width, true)
	draw_circle(points[0], width + 2.0, color)
	draw_circle(points.back(), width + 2.0, color)


func _polyline_center(points: Array[Vector2]) -> Vector2:
	return points[int(points.size() / 2)]


func _nearest_polyline_point(points: Array[Vector2], target: Vector2) -> Vector2:
	var nearest := points[0] if not points.is_empty() else target
	var nearest_distance := INF
	for index in range(points.size() - 1):
		var segment := points[index + 1] - points[index]
		if segment.length_squared() <= 0.001:
			continue
		var ratio := clampf((target - points[index]).dot(segment) / segment.length_squared(), 0.0, 1.0)
		var candidate := points[index] + segment * ratio
		var distance := candidate.distance_squared_to(target)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate
	return nearest


func _as_vector_points(raw_points) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if raw_points is not Array:
		return result
	for point in raw_points:
		if point is Vector2:
			var vector_point: Vector2 = point
			result.append(vector_point)
	return result


func _draw_advance_arrow(from: Vector2, to: Vector2):
	var delta := to - from
	if delta.length() < 12.0:
		return
	var direction := delta.normalized()
	var normal := direction.orthogonal()
	var color := Color(1.0, 0.75, 0.12, 0.9)
	draw_line(from, to - direction * 12.0, color, 3.0, true)
	draw_colored_polygon(PackedVector2Array([
		to,
		to - direction * 18.0 + normal * 8.0,
		to - direction * 18.0 - normal * 8.0,
	]), color)


func show_selection(from: Vector2, to: Vector2):
	selection_visible = true
	selection_start = from
	selection_end = to
	queue_redraw()


func hide_selection():
	selection_visible = false
	queue_redraw()


func show_formation(points: Array[Vector2]):
	formation_points = points
	queue_redraw()


func hide_formation():
	formation_points.clear()
	queue_redraw()


func set_platoon_plans(plans: Array[Dictionary]):
	platoon_plans = plans
	queue_redraw()


func show_order_line_preview(points: Array[Vector2], line_type: StringName):
	order_line_preview_visible = true
	order_line_preview_points.assign(points)
	order_line_preview_type = line_type
	queue_redraw()


func hide_order_line_preview():
	order_line_preview_visible = false
	order_line_preview_points.clear()
	queue_redraw()
