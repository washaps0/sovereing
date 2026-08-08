extends Camera2D

var speed := 500.0
var zoom_step := 0.1
var min_zoom := 0.2
var max_zoom := 3.0


func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		var zoom_direction := 0.0

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_direction = 1.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_direction = -1.0

		if zoom_direction != 0.0:
			var mouse_position := get_global_mouse_position()
			var new_zoom: float = clamp(zoom.x + zoom_step * zoom_direction, min_zoom, max_zoom)
			zoom = Vector2.ONE * new_zoom
			position += mouse_position - get_global_mouse_position()

func _process(delta):
	var direction := Vector2.ZERO

	if Input.is_key_pressed(KEY_W):
		direction.y -= 1
	if Input.is_key_pressed(KEY_S):
		direction.y += 1
	if Input.is_key_pressed(KEY_A):
		direction.x -= 1
	if Input.is_key_pressed(KEY_D):
		direction.x += 1

	if Input.is_key_pressed(KEY_SHIFT):
		speed = 1000.0
	else:
		speed = 500.0
	position += direction.normalized() * speed * delta
