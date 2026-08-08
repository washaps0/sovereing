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

var tree_variant := 0
var units_inside := 0

@onready var tree_sprite: Sprite2D = $Sprite2D


func _ready():
	tree_variant = clampi(tree_variant, 0, NORMAL_TEXTURES.size() - 1)
	tree_sprite.texture = NORMAL_TEXTURES[tree_variant]
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D):
	if body is CharacterBody2D:
		units_inside += 1
		tree_sprite.texture = OCCLUDED_TEXTURES[tree_variant]


func _on_body_exited(body: Node2D):
	if body is CharacterBody2D:
		units_inside = maxi(units_inside - 1, 0)
		if units_inside == 0:
			tree_sprite.texture = NORMAL_TEXTURES[tree_variant]
