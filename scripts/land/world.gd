extends Node2D

const MAP_WIDTH := 20
const MAP_HEIGHT := 20
const TILE_SIZE := 64

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
			add_child(grass_sprite)


func _ready():
	rng.seed = 12345
	
	generate_ground()
