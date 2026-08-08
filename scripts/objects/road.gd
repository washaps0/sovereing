class_name RoadSegment
extends Building

const SEGMENT_LENGTH := 64.0

var street_name := "Улица"
var hover_label: Label


func _ready():
	super._ready()
	add_to_group("roads")
	hover_label = Label.new()
	hover_label.position = Vector2(-32, -30)
	hover_label.scale = Vector2(0.5, 0.57)
	hover_label.z_index = 20
	hover_label.visible = false
	hover_label.text = street_name
	add_child(hover_label)
	mouse_entered.connect(func(): hover_label.visible = true)
	mouse_exited.connect(func(): hover_label.visible = false)


func setup(new_name: String, angle: float):
	street_name = new_name
	rotation = angle
	if is_instance_valid(hover_label):
		hover_label.text = street_name
		hover_label.rotation = -rotation


func get_endpoints() -> Array[Vector2]:
	var half_direction := Vector2.RIGHT.rotated(rotation) * SEGMENT_LENGTH * 0.5
	return [global_position - half_direction, global_position + half_direction]
