extends Node2D

const MAP_WIDTH := 200
const MAP_HEIGHT := 200
const TILE_SIZE := 64
const FOREST_NOISE_FREQUENCY := 0.0003
const FOREST_THRESHOLD := 0.2
const TREE_SPACING := 32
const UNIT_SCENE := preload("res://scenes/objects/unit.tscn")

@export var starting_unit_count := 5
@export var unit_spawn_position := Vector2(300, 300)
@export var unit_spacing := 40.0


func spawn_starting_units():
	for i in range(starting_unit_count):
		var unit = UNIT_SCENE.instantiate()
		unit.position = unit_spawn_position + Vector2(i * unit_spacing, 0)
		add_child(unit)

var forest_noise := FastNoiseLite.new()

var grass_textures = [
	preload("res://assets/terrain/grass/grass1.png"),
	preload("res://assets/terrain/grass/grass2.png"),
	preload("res://assets/terrain/grass/grass3.png")
]

var tree_textures = [
	preload("res://assets/objects/nature/trees/tree1.png"),
	preload("res://assets/objects/nature/trees/tree2.png"),
	preload("res://assets/objects/nature/trees/tree3.png")
]

const TREE_SCENE := preload("res://scenes/objects/tree.tscn")
const ROCK_SCENE := preload("res://scenes/objects/rock.tscn")

var rng := RandomNumberGenerator.new()

func generate_ground():
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var grass_texture = grass_textures[rng.randi_range(0, grass_textures.size() - 1)]
			var grass_sprite = Sprite2D.new()
			grass_sprite.texture = grass_texture
			grass_sprite.position = Vector2(x * TILE_SIZE, y * TILE_SIZE)
			$ground.add_child(grass_sprite)


func spawn_tree(pos: Vector2):
	var tree = TREE_SCENE.instantiate()
	tree.tree_variant = rng.randi_range(0, tree_textures.size() - 1)
	tree.position = pos
	$trees.add_child(tree)


func spawn_rock(pos: Vector2):
	var rock = ROCK_SCENE.instantiate()
	rock.rock_variant = rng.randi_range(0, 2)
	rock.position = pos
	$rocks.add_child(rock)


func generate_rock_deposits():
	# Редкие небольшие залежи по 2–5 камней.
	for x in range(96, MAP_WIDTH * TILE_SIZE, 192):
		for y in range(96, MAP_HEIGHT * TILE_SIZE, 192):
			if rng.randf() > 0.06:
				continue
			var center := Vector2(x, y) + Vector2(rng.randf_range(-64, 64), rng.randf_range(-64, 64))
			for i in range(rng.randi_range(2, 5)):
				var angle := rng.randf_range(0.0, TAU)
				var offset := Vector2.from_angle(angle) * rng.randf_range(10.0, 35.0)
				spawn_rock(center + offset)

func generate_forest():
	for x in range(0, MAP_WIDTH * TILE_SIZE, TREE_SPACING):
		for y in range(0, MAP_HEIGHT * TILE_SIZE, TREE_SPACING):
			
			var value = forest_noise.get_noise_2d(x, y)
			
			if value > FOREST_THRESHOLD:
				spawn_tree(Vector2(x + rng.randf_range(0, 16), y + rng.randf_range(0, 16)))

				
func _ready():
	rng.seed = 12345

	forest_noise.seed = 12345
	forest_noise.frequency = FOREST_NOISE_FREQUENCY

	generate_ground()
	generate_forest()
	generate_rock_deposits()
	spawn_starting_units()


func _unhandled_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_tree().call_group("units", "deselect")
