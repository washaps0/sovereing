class_name TacticalOverlay
extends Node2D

const UNIT_TEXTURE := preload("res://assets/char/character.png")

var selection_visible := false
var selection_start := Vector2.ZERO
var selection_end := Vector2.ZERO
var formation_points: Array[Vector2] = []


func _draw():
	if selection_visible:
		var rect := Rect2(selection_start, selection_end - selection_start).abs()
		draw_rect(rect, Color(0.15, 0.65, 1.0, 0.22), true)
		draw_rect(rect, Color(0.4, 0.9, 1.0, 1.0), false, 2.0)
	for point in formation_points:
		var preview_rect := Rect2(point - Vector2(8, 8), Vector2(16, 16))
		draw_texture_rect(UNIT_TEXTURE, preview_rect, false, Color(1.0, 1.0, 1.0, 0.48))
		draw_arc(point, 9.0, 0.0, TAU, 20, Color(0.35, 1.0, 0.5, 0.85), 1.0)


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
