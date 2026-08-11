class_name GovernmentBuilding
extends Building

const UNIT_SCENE := preload("res://scenes/objects/unit.tscn")
const SQUAD_SIZE := 8
const SQUADS_PER_PLATOON := 3

@export_range(0, 10000, 1) var migration_target := 0
@export_range(1.0, 120.0, 0.5) var migration_interval := 5.0
@export_range(0, 10000, 1) var mobilization_target := 0
@export_range(0.5, 30.0, 0.5) var mobilization_interval := 2.0

var migration_timer := 0.0
var mobilization_timer := 0.0


func _ready():
	super._ready()
	migration_timer = migration_interval
	mobilization_timer = mobilization_interval


func _process(delta: float):
	super._process(delta)
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager) and network_manager.is_remote_client():
		return
	if placement_preview or not is_completed():
		return
	if migration_target > 0:
		migration_timer -= delta
		if migration_timer <= 0.0:
			migration_timer += migration_interval
			_attempt_migration()
	mobilization_timer -= delta
	if mobilization_timer <= 0.0:
		mobilization_timer += mobilization_interval
		_supply_soldiers_at_base()
		_attempt_mobilization_change()


func set_migration_target(value: int):
	migration_target = maxi(value, 0)


func set_mobilization_target(value: int):
	mobilization_target = maxi(value, 0)
	mobilization_timer = minf(mobilization_timer, 0.25)


func get_completed_barracks_count() -> int:
	var total := 0
	for building in get_tree().get_nodes_in_group("buildings"):
		if _is_in_same_world(building) and building is Building and building.faction_id == faction_id and building.is_barracks() and building.is_completed():
			total += 1
	return total


func get_army_capacity() -> int:
	var total := 0
	for building in get_tree().get_nodes_in_group("buildings"):
		if _is_in_same_world(building) and building is Building and building.faction_id == faction_id and building.is_barracks() and building.is_completed():
			total += building.max_occupants
	return total


func get_mobilized_count() -> int:
	return _get_mobilized_units().size()


func get_unassigned_soldier_count() -> int:
	var total := 0
	for unit in _get_mobilized_units():
		if unit.squad_id <= 0:
			total += 1
	return total


func get_squad_count() -> int:
	var squad_ids := {}
	for unit in _get_mobilized_units():
		if unit.squad_id > 0:
			squad_ids[unit.squad_id] = true
	return squad_ids.size()


func get_platoon_count() -> int:
	var platoon_ids := {}
	for unit in _get_mobilized_units():
		if unit.platoon_id > 0:
			platoon_ids[unit.platoon_id] = true
	return platoon_ids.size()


func get_army_status_text() -> String:
	var mobilized := get_mobilized_count()
	var capacity := get_army_capacity()
	var desired := mini(mobilization_target, mini(capacity, get_population_count()))
	if mobilization_target <= 0 and mobilized <= 0:
		return "Мобилизация отключена."
	if mobilized > desired:
		return "Идёт демобилизация до %d человек." % desired
	if mobilization_target > capacity:
		return "Не хватает казарм: цель %d, доступно мест %d." % [mobilization_target, capacity]
	if mobilization_target > get_population_count():
		return "Не хватает жителей для заданной численности армии."
	if mobilized < desired:
		return "Идёт мобилизация: %d из %d." % [mobilized, desired]
	return "Цель мобилизации достигнута."


func get_army_hierarchy_text() -> String:
	return "Отряды: %d (до %d солдат)\nВзводы: %d (до %d отрядов)\nБез отряда: %d" % [get_squad_count(), SQUAD_SIZE, get_platoon_count(), SQUADS_PER_PLATOON, get_unassigned_soldier_count()]


func get_equipment_amount(resource_type: StringName) -> int:
	var total := 0
	for building in get_tree().get_nodes_in_group("buildings"):
		if _is_in_same_world(building) and building is Building and building.faction_id == faction_id and building.is_warehouse() and building.is_completed():
			total += building.get_stored_resource(resource_type)
	return total


func get_ready_rifleman_set_count() -> int:
	return mini(get_equipment_amount(&"armor"), get_equipment_amount(&"rifles"))


func get_equipment_status_text() -> String:
	var mobilized := get_mobilized_count()
	var ready_sets := get_ready_rifleman_set_count()
	return "На складах — броня: %d, автоматы: %d\nВыдано — броня: %d/%d, автоматы: %d/%d\nГотовых комплектов на складах: %d" % [get_equipment_amount(&"armor"), get_equipment_amount(&"rifles"), _get_issued_equipment_count(&"armor"), mobilized, _get_issued_equipment_count(&"rifles"), mobilized, ready_sets]


func organize_army():
	var soldiers := _get_mobilized_units()
	soldiers.sort_custom(func(a: Unit, b: Unit): return a.network_id < b.network_id)
	for index in range(soldiers.size()):
		var unit := soldiers[index]
		var squad_index: int = index / SQUAD_SIZE
		var platoon_index: int = squad_index / SQUADS_PER_PLATOON
		var squad_commander_index := squad_index * SQUAD_SIZE
		var platoon_commander_index := platoon_index * SQUAD_SIZE * SQUADS_PER_PLATOON
		var new_squad_id := squad_index + 1
		var new_commander_network_id := soldiers[squad_commander_index].network_id
		if unit.squad_id != new_squad_id or unit.squad_commander_network_id != new_commander_network_id:
			unit.squad_formation_offset = Vector2.ZERO
			unit.squad_follow_active = false
		unit.squad_id = squad_index + 1
		unit.platoon_id = platoon_index + 1
		unit.squad_commander_network_id = new_commander_network_id
		unit.platoon_commander_network_id = soldiers[platoon_commander_index].network_id
		if index % (SQUAD_SIZE * SQUADS_PER_PLATOON) == 0:
			unit.military_rank = "Командир взвода"
			unit.military_role = &"commander"
			unit.simulation_importance = 2
		elif index % SQUAD_SIZE == 0:
			unit.military_rank = "Командир отряда"
			unit.military_role = &"commander"
			unit.simulation_importance = 2
		else:
			unit.military_rank = "Солдат"
			unit.military_role = &"rifleman"
			unit.simulation_importance = maxi(unit.simulation_importance, 1)
		unit.refresh_military_visuals()


func _attempt_mobilization_change() -> bool:
	var mobilized := get_mobilized_count()
	var desired := mini(mobilization_target, mini(get_army_capacity(), get_population_count()))
	if mobilized < desired:
		var barracks := _find_barracks_for_soldier()
		var civilian := _find_civilian_for_mobilization()
		if not is_instance_valid(barracks) or not is_instance_valid(civilian):
			return false
		if civilian.mobilize(barracks):
			_equip_soldier(civilian)
			organize_army()
			return true
	elif mobilized > desired:
		var soldiers := _get_mobilized_units()
		if soldiers.is_empty():
			return false
		soldiers.sort_custom(func(a: Unit, b: Unit): return a.network_id > b.network_id)
		_return_soldier_equipment(soldiers[0])
		soldiers[0].demobilize()
		organize_army()
		return true
	return false


func _supply_soldiers_at_base():
	for unit in _get_mobilized_units():
		if is_instance_valid(unit.inside_building) and unit.inside_building.is_barracks():
			_equip_soldier(unit)


func _equip_soldier(unit: Unit):
	var armor_equipped := unit.has_armor
	var rifle_equipped := unit.has_rifle
	if not armor_equipped:
		armor_equipped = _take_equipment_from_storage(&"armor")
	if not rifle_equipped:
		rifle_equipped = _take_equipment_from_storage(&"rifles")
	unit.set_military_equipment(armor_equipped, rifle_equipped)


func _return_soldier_equipment(unit: Unit):
	var armor_equipped := unit.has_armor
	var rifle_equipped := unit.has_rifle
	if armor_equipped and _store_equipment(&"armor"):
		armor_equipped = false
	if rifle_equipped and _store_equipment(&"rifles"):
		rifle_equipped = false
	unit.set_military_equipment(armor_equipped, rifle_equipped)


func _take_equipment_from_storage(resource_type: StringName) -> bool:
	for warehouse in _get_equipment_warehouses():
		if warehouse.take_resource(resource_type, 1) == 1:
			return true
	return false


func _store_equipment(resource_type: StringName) -> bool:
	for warehouse in _get_equipment_warehouses():
		if warehouse.store_resource(resource_type, 1) == 1:
			return true
	return false


func _get_equipment_warehouses() -> Array[Building]:
	var warehouses: Array[Building] = []
	for building in get_tree().get_nodes_in_group("buildings"):
		if _is_in_same_world(building) and building is Building and building.faction_id == faction_id and building.is_warehouse() and building.is_completed():
			warehouses.append(building)
	warehouses.sort_custom(func(a: Building, b: Building): return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	return warehouses


func _get_issued_equipment_count(resource_type: StringName) -> int:
	var total := 0
	for unit in _get_mobilized_units():
		if (resource_type == &"armor" and unit.has_armor) or (resource_type == &"rifles" and unit.has_rifle):
			total += 1
	return total


func _get_mobilized_units() -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in get_tree().get_nodes_in_group("units"):
		if _is_in_same_world(unit) and unit is Unit and unit.faction_id == faction_id and unit.is_mobilized:
			result.append(unit)
	return result


func _find_civilian_for_mobilization() -> Unit:
	var fallback: Unit
	for unit in get_tree().get_nodes_in_group("units"):
		if not _is_in_same_world(unit) or unit is not Unit or unit.faction_id != faction_id or unit.is_mobilized or unit.health <= 0:
			continue
		if unit.task in [Unit.Task.IDLE, Unit.Task.REST]:
			return unit
		if not is_instance_valid(fallback):
			fallback = unit
	return fallback


func _find_barracks_for_soldier() -> Building:
	var nearest: Building
	var nearest_distance := INF
	for building in get_tree().get_nodes_in_group("buildings"):
		if not _is_in_same_world(building) or building is not Building or building.faction_id != faction_id or not building.is_barracks() or not building.is_completed():
			continue
		if building.occupants.size() >= building.max_occupants:
			continue
		var distance := global_position.distance_squared_to(building.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = building
	return nearest


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
