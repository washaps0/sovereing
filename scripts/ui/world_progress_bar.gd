class_name WorldProgressBar
extends Node2D

var bar_width := 32.0
var bar_height := 2.0
var value := 0.0:
	set(new_value):
		value = clampf(new_value, 0.0, 100.0)
		queue_redraw()
var fill_color := Color(0.35, 0.85, 0.25)
var background_color := Color(0.05, 0.05, 0.05, 0.9)


func _draw():
	var background_rect := Rect2(-bar_width * 0.5, 0.0, bar_width, bar_height)
	draw_rect(background_rect, background_color)
	var fill_width := bar_width * value / 100.0
	if fill_width > 0.0:
		draw_rect(Rect2(-bar_width * 0.5, 0.0, fill_width, bar_height), fill_color)
