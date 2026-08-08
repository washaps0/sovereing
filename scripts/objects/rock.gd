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


func harvest(amount: int) -> int:
	var mined := mini(amount, stone_amount)
	stone_amount -= mined
	if stone_amount <= 0:
		queue_free()
	return mined


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
