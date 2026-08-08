extends Node2D

const MAP_WIDTH := 200
const MAP_HEIGHT := 200
const TILE_SIZE := 64
const FOREST_NOISE_FREQUENCY := 0.0003
const FOREST_THRESHOLD := 0.2
const TREE_SPACING := 32

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
	var tree = Sprite2D.new()
	
	tree.texture = tree_textures[rng.randi_range(0, tree_textures.size() - 1)]
	tree.position = pos
	
	$trees.add_child(tree)

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
