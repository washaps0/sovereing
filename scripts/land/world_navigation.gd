class_name WorldNavigation
extends Node

const PATH_CELL_SIZE := 32.0
const PATH_MAP_SIZE := Vector2i(400, 400)
const ROAD_PATH_WEIGHT := 1.0 / 1.5
const ROAD_PATH_MARGIN := 8.0
const BUILDING_AVOIDANCE_WEIGHT := 9.0
const MAX_CACHED_PATHS := 768

var _grid: AStarGrid2D
var _dirty := true
var _path_cache := {}
var _path_cache_order: Array[Vector4i] = []
var _road_segments_by_cell := {}
var _world_index: Node


func _ready():
	add_to_group("world_navigation")
	_world_index = get_node_or_null("../WorldIndex")


func invalidate():
	_dirty = true
	_path_cache.clear()
	_path_cache_order.clear()


func find_path(from_position: Vector2, destination: Vector2) -> PackedVector2Array:
	_ensure_grid()
	if _grid == null:
		return PackedVector2Array()
	var start := world_to_cell(from_position)
	var finish := world_to_cell(destination)
	if not _grid.region.has_point(start) or not _grid.region.has_point(finish):
		return PackedVector2Array()
	var cache_key := Vector4i(start.x, start.y, finish.x, finish.y)
	if _path_cache.has(cache_key):
		var cached_path: PackedVector2Array = _path_cache[cache_key]
		return cached_path
	var result := _grid.get_point_path(start, finish)
	_path_cache[cache_key] = result
	_path_cache_order.append(cache_key)
	if _path_cache_order.size() > MAX_CACHED_PATHS:
		_path_cache.erase(_path_cache_order.pop_front())
	return result


func has_completed_road_at(point: Vector2, margin := ROAD_PATH_MARGIN) -> bool:
	_ensure_grid()
	for road in _road_segments_by_cell.get(world_to_cell(point), []):
		if is_instance_valid(road) and not road.under_construction and road.contains_world_point(point, margin):
			return true
	return false


func world_to_cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / PATH_CELL_SIZE), floori(point.y / PATH_CELL_SIZE))


func _ensure_grid():
	if not _dirty and _grid != null:
		return
	_dirty = false
	_path_cache.clear()
	_path_cache_order.clear()
	_road_segments_by_cell.clear()
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(Vector2i.ZERO, PATH_MAP_SIZE)
	_grid.cell_size = Vector2.ONE * PATH_CELL_SIZE
	_grid.offset = Vector2.ONE * PATH_CELL_SIZE * 0.5
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	_apply_road_weights()
	_apply_building_weights()


func _apply_road_weights():
	for building in _get_buildings():
		if building is not RoadSegment or building.under_construction:
			continue
		var road := building as RoadSegment
		var collision := road.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collision == null or collision.shape is not RectangleShape2D:
			continue
		var rectangle := collision.shape as RectangleShape2D
		var half_size := rectangle.size * 0.5
		var bounds := _get_collision_bounds(collision, half_size, ROAD_PATH_MARGIN)
		var minimum := world_to_cell(bounds.position)
		var maximum := world_to_cell(bounds.end)
		var inverse_transform := collision.global_transform.affine_inverse()
		for x in range(minimum.x, maximum.x + 1):
			for y in range(minimum.y, maximum.y + 1):
				var cell := Vector2i(x, y)
				if not _grid.region.has_point(cell):
					continue
				var cell_center := (Vector2(cell) + Vector2.ONE * 0.5) * PATH_CELL_SIZE
				var local_point := inverse_transform * cell_center
				if absf(local_point.x) > half_size.x + ROAD_PATH_MARGIN or absf(local_point.y) > half_size.y + ROAD_PATH_MARGIN:
					continue
				_grid.set_point_weight_scale(cell, ROAD_PATH_WEIGHT)
				if not _road_segments_by_cell.has(cell):
					_road_segments_by_cell[cell] = []
				_road_segments_by_cell[cell].append(road)


func _apply_building_weights():
	for building in _get_buildings():
		if building.building_kind == "road" or building.placement_preview:
			continue
		var collision := building.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collision == null or collision.shape is not RectangleShape2D:
			continue
		var half_size: Vector2 = collision.shape.size * 0.5
		var bounds := _get_collision_bounds(collision, half_size, 12.0)
		var minimum := world_to_cell(bounds.position)
		var maximum := world_to_cell(bounds.end)
		for x in range(minimum.x, maximum.x + 1):
			for y in range(minimum.y, maximum.y + 1):
				var cell := Vector2i(x, y)
				if _grid.region.has_point(cell) and not _road_segments_by_cell.has(cell):
					_grid.set_point_weight_scale(cell, BUILDING_AVOIDANCE_WEIGHT)


func _get_collision_bounds(collision: CollisionShape2D, half_size: Vector2, margin: float) -> Rect2:
	var world_minimum := Vector2(INF, INF)
	var world_maximum := Vector2(-INF, -INF)
	for corner in [Vector2(-half_size.x, -half_size.y), Vector2(half_size.x, -half_size.y), Vector2(half_size.x, half_size.y), Vector2(-half_size.x, half_size.y)]:
		var world_corner: Vector2 = collision.global_transform * corner
		world_minimum = world_minimum.min(world_corner)
		world_maximum = world_maximum.max(world_corner)
	return Rect2(world_minimum - Vector2.ONE * margin, world_maximum - world_minimum + Vector2.ONE * margin * 2.0)


func _get_buildings() -> Array:
	if is_instance_valid(_world_index):
		return _world_index.get_buildings()
	var result: Array[Building] = []
	for candidate in get_tree().get_nodes_in_group("buildings"):
		if candidate is Building and get_parent().is_ancestor_of(candidate):
			result.append(candidate)
	return result
