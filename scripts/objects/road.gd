class_name RoadSegment
extends Building

const SEGMENT_LENGTH := 64.0
const ROAD_WIDTH := 30.0
const MIN_PARALLEL_SPACING := ROAD_WIDTH * 2.0

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
	set_street_name(new_name)
	rotation = angle
	if is_instance_valid(hover_label):
		hover_label.rotation = -rotation


func set_street_name(new_name: String):
	street_name = new_name.strip_edges()
	if street_name.is_empty():
		street_name = "Улица"
	if is_instance_valid(hover_label):
		hover_label.text = street_name


func get_endpoints() -> Array[Vector2]:
	var half_direction := Vector2.RIGHT.rotated(global_rotation) * SEGMENT_LENGTH * 0.5
	return [global_position - half_direction, global_position + half_direction]
