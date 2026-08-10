class_name GovernmentBuilding
extends Building

const UNIT_SCENE := preload("res://scenes/objects/unit.tscn")

@export_range(0, 10000, 1) var migration_target := 0
@export_range(1.0, 120.0, 0.5) var migration_interval := 5.0

var migration_timer := 0.0


func _ready():
	super._ready()
	migration_timer = migration_interval


func _process(delta: float):
	super._process(delta)
	if placement_preview or not is_completed() or migration_target <= 0:
		return
	migration_timer -= delta
	if migration_timer > 0.0:
		return
	migration_timer += migration_interval
	_attempt_migration()


func set_migration_target(value: int):
	migration_target = maxi(value, 0)


func get_total_residence_count() -> int:
	var total := 0
	for building in get_tree().get_nodes_in_group("buildings"):
		if _is_in_same_world(building) and building is Building and building.faction_id == faction_id and building.is_residence():
			total += 1
	return total


func get_completed_residence_count() -> int:
	var total := 0
	for building in get_tree().get_nodes_in_group("buildings"):
		if _is_in_same_world(building) and building is Building and building.faction_id == faction_id and building.is_residence() and building.is_completed():
			total += 1
	return total


func get_housing_capacity() -> int:
	var total := 0
	for building in get_tree().get_nodes_in_group("buildings"):
		if _is_in_same_world(building) and building is Building and building.faction_id == faction_id and building.is_residence() and building.is_completed():
			total += building.max_occupants
	return total


func get_population_count() -> int:
	var total := 0
	for unit in get_tree().get_nodes_in_group("units"):
		if _is_in_same_world(unit) and unit is Unit and unit.faction_id == faction_id:
			total += 1
	return total


func get_free_housing() -> int:
	return maxi(get_housing_capacity() - get_population_count(), 0)


func get_migration_status_text() -> String:
	var population := get_population_count()
	var capacity := get_housing_capacity()
	if migration_target <= 0:
		return "Миграция отключена."
	if population >= migration_target:
		return "Цель миграции достигнута."
	if population >= capacity:
		return "Миграция ожидает свободное жильё."
	return "Миграция активна: следующий житель прибудет в течение %d сек." % maxi(ceili(migration_timer), 0)


func _attempt_migration() -> bool:
	var population := get_population_count()
	if migration_target <= population or population >= get_housing_capacity():
		return false
	var residence := _find_residence_for_migrant()
	if not is_instance_valid(residence):
		return false
	var world := _get_world_root()
	if not is_instance_valid(world):
		return false
	var unit := UNIT_SCENE.instantiate() as Unit
	_configure_migrant(unit)
	unit.global_position = residence.global_position
	world.add_child(unit)
	if not unit.settle_in_residence(residence):
		unit.queue_free()
		return false
	return true


func _find_residence_for_migrant() -> Building:
	var nearest: Building
	var nearest_distance := INF
	for building in get_tree().get_nodes_in_group("buildings"):
		if not _is_in_same_world(building) or building is not Building or building.faction_id != faction_id or not building.is_residence() or not building.is_completed():
			continue
		if building.occupants.size() >= building.max_occupants:
			continue
		var distance := global_position.distance_squared_to(building.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = building
	return nearest


func _get_world_root() -> Node2D:
	var parent_node := get_parent()
	if parent_node != null and parent_node.get_parent() is Node2D:
		return parent_node.get_parent() as Node2D
	return null


func _is_in_same_world(node: Node) -> bool:
	var world := _get_world_root()
	return is_instance_valid(world) and is_instance_valid(node) and world.is_ancestor_of(node)


func _configure_migrant(unit: Unit):
	var controller_peer_id := 1 if faction_id == 0 else 0
	var ai_controlled := faction_id != 0
	var resolved_faction_name := faction_name
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		var slot: Dictionary = network_manager.get_faction_slot(faction_id)
		if not slot.is_empty():
			controller_peer_id = int(slot.get("controller_peer_id", controller_peer_id))
			ai_controlled = bool(slot.get("is_ai", ai_controlled))
			resolved_faction_name = str(slot.get("nickname", resolved_faction_name))
	unit.configure_faction(faction_id, controller_peer_id, ai_controlled, resolved_faction_name)
	unit.network_id = _next_unit_network_id()
	unit.name = "Unit_%d" % unit.network_id


func _next_unit_network_id() -> int:
	var result := faction_id * 100000 + 10000
	for unit in get_tree().get_nodes_in_group("units"):
		if _is_in_same_world(unit) and unit is Unit and unit.faction_id == faction_id:
			result = maxi(result, unit.network_id + 1)
	return result
