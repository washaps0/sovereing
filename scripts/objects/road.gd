class_name RoadSegment
extends Building

const SEGMENT_LENGTH := 64.0
const ROAD_WIDTH := 30.0
const MIN_PARALLEL_SPACING := ROAD_WIDTH * 2.0
# Фактический размер CollisionShape2D с учётом масштаба корня road.tscn.
# Используется проверкой размещения до создания дорожного сегмента.
const FOOTPRINT_HALF_SIZE := Vector2(34.0, 16.0)

var street_name := "Улица"


func _ready():
	super._ready()
	add_to_group("roads")
	address = street_name
	address_label.text = street_name


func setup(new_name: String, angle: float):
	set_street_name(new_name)
	rotation = angle


func set_street_name(new_name: String):
	street_name = new_name.strip_edges()
	if street_name.is_empty():
		street_name = "Улица"
	address = street_name
	if is_instance_valid(address_label):
		address_label.text = street_name


func get_endpoints() -> Array[Vector2]:
	var half_direction := Vector2.RIGHT.rotated(global_rotation) * SEGMENT_LENGTH * 0.5
	return [global_position - half_direction, global_position + half_direction]
