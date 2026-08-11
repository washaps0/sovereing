extends Area2D

const NORMAL_TEXTURES: Array[Texture2D] = [
	preload("res://assets/objects/nature/trees/tree1.png"),
	preload("res://assets/objects/nature/trees/tree2.png"),
	preload("res://assets/objects/nature/trees/tree3.png")
]
const OCCLUDED_TEXTURES: Array[Texture2D] = [
	preload("res://assets/objects/nature/trees/tree1_ocap.png"),
	preload("res://assets/objects/nature/trees/tree2_ocap.png"),
	preload("res://assets/objects/nature/trees/tree3_ocap.png")
]

@export var wood_amount := 20

var tree_variant := 0
var units_inside := 0
var harvest_progress := {}
var progress_bar: WorldProgressBar
var lod_active := true
var lod_record_id := 0

@onready var tree_sprite: Sprite2D = $Sprite2D


func _ready():
	add_to_group("trees")
	add_to_group("resources")
	set_process(false)
	tree_variant = clampi(tree_variant, 0, NORMAL_TEXTURES.size() - 1)
	tree_sprite.texture = NORMAL_TEXTURES[tree_variant]
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _input_event(_viewport: Node, event: InputEvent, _shape_idx: int):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var unit := Unit.get_selected_unit()
		if is_instance_valid(unit):
			unit.request_harvest(self)
			get_viewport().set_input_as_handled()


func _process(_delta: float):
	if not is_instance_valid(progress_bar):
		set_process(false)
		return
	if harvest_progress.is_empty():
		progress_bar.visible = false
		set_process(false)
		return
	progress_bar.visible = true
	var highest_progress := 0.0
	for value in harvest_progress.values():
		highest_progress = maxf(highest_progress, value)
	progress_bar.value = highest_progress * 100.0


func set_lod_active(active: bool):
	if lod_active == active:
		return
	lod_active = active
	visible = active
	input_pickable = active
	monitoring = active
	set_process(active and not harvest_progress.is_empty())
	$CollisionShape2D.set_deferred("disabled", not active)


func _create_progress_bar():
	if is_instance_valid(progress_bar):
		return
	progress_bar = WorldProgressBar.new()
	progress_bar.position = Vector2(0, -22)
	progress_bar.bar_width = 24.0
	progress_bar.bar_height = 2.0
	progress_bar.z_index = 10
	progress_bar.visible = false
	add_child(progress_bar)


func set_harvest_progress(unit: Unit, progress: float):
	_create_progress_bar()
	harvest_progress[unit.get_instance_id()] = progress
	set_process(lod_active)


func stop_harvest(unit: Unit):
	harvest_progress.erase(unit.get_instance_id())
	if harvest_progress.is_empty():
		if is_instance_valid(progress_bar):
			progress_bar.visible = false
		set_process(false)


func get_harvester_count() -> int:
	return harvest_progress.size()


func harvest(amount: int, source_faction_id := -1) -> int:
	var harvested := mini(amount, wood_amount)
	wood_amount -= harvested
	_sync_lod_amount(source_faction_id)
	if wood_amount <= 0:
		queue_free()
	return harvested


func _sync_lod_amount(source_faction_id := -1):
	if lod_record_id <= 0:
		return
	var manager := get_tree().get_first_node_in_group("simulation_lod_manager")
	if is_instance_valid(manager) and manager.has_method("update_resource_amount"):
		manager.update_resource_amount(lod_record_id, wood_amount, source_faction_id)


func is_depleted() -> bool:
	return wood_amount <= 0


func get_resource_type() -> StringName:
	return &"wood"


func _on_body_entered(body: Node2D):
	if body is Unit:
		units_inside += 1
		tree_sprite.texture = OCCLUDED_TEXTURES[tree_variant]


func _on_body_exited(body: Node2D):
	if body is Unit:
		units_inside = maxi(units_inside - 1, 0)
		if units_inside == 0:
			tree_sprite.texture = NORMAL_TEXTURES[tree_variant]
