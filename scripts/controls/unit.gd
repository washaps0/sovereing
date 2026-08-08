extends CharacterBody2D

@export var speed := 100.0

static var selected_unit

var target_position := Vector2.ZERO
var selected := false

@onready var selection: Sprite2D = $selection


func _ready():
	add_to_group("units")
	target_position = global_position
	selection.visible = false


func _physics_process(_delta):
	if global_position.distance_to(target_position) > 3:
		var direction = global_position.direction_to(target_position)
		velocity = direction * speed
		move_and_slide()
	else:
		velocity = Vector2.ZERO


func _input_event(_viewport: Node, event: InputEvent, _shape_idx: int):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		select()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent):
	if selected and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		target_position = get_global_mouse_position()
		get_viewport().set_input_as_handled()


func select():
	if is_instance_valid(selected_unit) and selected_unit != self:
		selected_unit.deselect()

	selected_unit = self
	selected = true
	selection.visible = true


func deselect():
	selected = false
	selection.visible = false
