extends Area2D

const TEXTURES: Array[Texture2D] = [
	preload("res://assets/objects/nature/rocks/rock1.png"),
	preload("res://assets/objects/nature/rocks/rock2.png"),
	preload("res://assets/objects/nature/rocks/rock3.png")
]

@export var stone_amount := 30
var rock_variant := 0
var harvest_progress := {}
var progress_bar: WorldProgressBar
var lod_active := true
var lod_record_id := 0
@onready var rock_sprite: Sprite2D = $Sprite2D


func _ready():
	add_to_group("resources")
	add_to_group("rocks")
	rock_variant = clampi(rock_variant, 0, TEXTURES.size() - 1)
	rock_sprite.texture = TEXTURES[rock_variant]
	progress_bar = WorldProgressBar.new()
	progress_bar.position = Vector2(0, -18)
	progress_bar.bar_width = 24.0
	progress_bar.bar_height = 2.0
	progress_bar.fill_color = Color(0.55, 0.65, 0.75)
	progress_bar.z_index = 10
	progress_bar.visible = false
	add_child(progress_bar)


func _process(_delta: float):
	progress_bar.visible = not harvest_progress.is_empty()
	var highest := 0.0
	for value in harvest_progress.values():
		highest = maxf(highest, value)
	progress_bar.value = highest * 100.0


func set_lod_active(active: bool):
	if lod_active == active:
		return
	lod_active = active
	visible = active
	input_pickable = active
	monitoring = active
	set_process(active)
	$CollisionShape2D.set_deferred("disabled", not active)


func harvest(amount: int, source_faction_id := -1) -> int:
	var mined := mini(amount, stone_amount)
	stone_amount -= mined
	_sync_lod_amount(source_faction_id)
	if stone_amount <= 0:
		queue_free()
	return mined


func _sync_lod_amount(source_faction_id := -1):
	if lod_record_id <= 0:
		return
	var manager := get_tree().get_first_node_in_group("simulation_lod_manager")
	if is_instance_valid(manager) and manager.has_method("update_resource_amount"):
		manager.update_resource_amount(lod_record_id, stone_amount, source_faction_id)


func is_depleted() -> bool:
	return stone_amount <= 0


func get_resource_type() -> StringName:
	return &"stone"


func set_harvest_progress(unit: Unit, progress: float):
	harvest_progress[unit.get_instance_id()] = progress


func stop_harvest(unit: Unit):
	harvest_progress.erase(unit.get_instance_id())


func get_harvester_count() -> int:
	return harvest_progress.size()
