class_name WorldIndex
extends Node

# Реестр избавляет каждого юнита от создания временных массивов через
# SceneTree.get_nodes_in_group(). Записи обновляются при входе/выходе узлов.
var _units: Array[Unit] = []
var _buildings: Array[Building] = []
var _units_by_faction := {}
var _buildings_by_faction := {}
var _buildings_by_kind := {}
var _reservation_counts := {}
var _carried_to_building := {}
var _reservation_cache_msec := -1000
const RESERVATION_CACHE_INTERVAL_MSEC := 150


func _ready():
	add_to_group("world_index")


func register_unit(unit: Unit):
	if not is_instance_valid(unit) or unit in _units:
		return
	_units.append(unit)
	_get_or_create_array(_units_by_faction, unit.faction_id).append(unit)


func unregister_unit(unit: Unit):
	_units.erase(unit)
	if _units_by_faction.has(unit.faction_id):
		_units_by_faction[unit.faction_id].erase(unit)


func refresh_unit_faction(unit: Unit, previous_faction_id: int):
	if previous_faction_id == unit.faction_id:
		return
	if _units_by_faction.has(previous_faction_id):
		_units_by_faction[previous_faction_id].erase(unit)
	if unit in _units:
		_get_or_create_array(_units_by_faction, unit.faction_id).append(unit)


func register_building(building: Building):
	if not is_instance_valid(building) or building in _buildings:
		return
	_buildings.append(building)
	_get_or_create_array(_buildings_by_faction, building.faction_id).append(building)
	_get_or_create_array(_buildings_by_kind, building.building_kind).append(building)


func unregister_building(building: Building):
	_buildings.erase(building)
	if _buildings_by_faction.has(building.faction_id):
		_buildings_by_faction[building.faction_id].erase(building)
	if _buildings_by_kind.has(building.building_kind):
		_buildings_by_kind[building.building_kind].erase(building)


func get_units(faction_id := -1) -> Array[Unit]:
	var source: Array = _units if faction_id < 0 else _units_by_faction.get(faction_id, [])
	var result: Array[Unit] = []
	for unit in source:
		if is_instance_valid(unit) and not unit.is_queued_for_deletion():
			result.append(unit)
	return result


func get_buildings(faction_id := -1, building_kind := "") -> Array[Building]:
	var source: Array
	if not building_kind.is_empty():
		source = _buildings_by_kind.get(building_kind, [])
	elif faction_id >= 0:
		source = _buildings_by_faction.get(faction_id, [])
	else:
		source = _buildings
	var result: Array[Building] = []
	for building in source:
		if not is_instance_valid(building) or building.is_queued_for_deletion():
			continue
		if faction_id >= 0 and building.faction_id != faction_id:
			continue
		result.append(building)
	return result


func get_reserved_entry_count(building: Building, excluded_unit: Unit = null) -> int:
	if not is_instance_valid(building):
		return 0
	_rebuild_reservation_cache_if_needed()
	var reserved := int(_reservation_counts.get(building.get_instance_id(), 0))
	if is_instance_valid(excluded_unit) and excluded_unit.task == Unit.Task.ENTER_BUILDING and excluded_unit.target_building == building and not is_instance_valid(excluded_unit.inside_building):
		reserved = maxi(reserved - 1, 0)
	return reserved


func get_carried_to_building(building: Building, resource_type: StringName, excluded_unit: Unit = null) -> int:
	if not is_instance_valid(building):
		return 0
	_rebuild_reservation_cache_if_needed()
	var resource_offset := 1 if resource_type == &"stone" else 0
	var key := Vector2i(int(building.get_instance_id()), resource_offset)
	var carried := int(_carried_to_building.get(key, 0))
	if is_instance_valid(excluded_unit) and excluded_unit.target_building == building:
		carried -= excluded_unit.carried_stone if resource_type == &"stone" else excluded_unit.carried_wood
	return maxi(carried, 0)


func _rebuild_reservation_cache_if_needed():
	var now_msec := Time.get_ticks_msec()
	if now_msec - _reservation_cache_msec < RESERVATION_CACHE_INTERVAL_MSEC:
		return
	_reservation_cache_msec = now_msec
	_reservation_counts.clear()
	_carried_to_building.clear()
	for unit in _units:
		if not is_instance_valid(unit) or not is_instance_valid(unit.target_building):
			continue
		var building_id := int(unit.target_building.get_instance_id())
		if unit.task == Unit.Task.ENTER_BUILDING and not is_instance_valid(unit.inside_building):
			_reservation_counts[building_id] = int(_reservation_counts.get(building_id, 0)) + 1
		var wood_key := Vector2i(building_id, 0)
		var stone_key := Vector2i(building_id, 1)
		_carried_to_building[wood_key] = int(_carried_to_building.get(wood_key, 0)) + unit.carried_wood
		_carried_to_building[stone_key] = int(_carried_to_building.get(stone_key, 0)) + unit.carried_stone


func find_unit(network_id: int, faction_id: int) -> Unit:
	for unit in _units_by_faction.get(faction_id, []):
		if is_instance_valid(unit) and not unit.is_queued_for_deletion() and unit.network_id == network_id:
			return unit
	return null


func find_building(network_id: int, faction_id: int) -> Building:
	for building in _buildings_by_faction.get(faction_id, []):
		if is_instance_valid(building) and not building.is_queued_for_deletion() and building.network_id == network_id:
			return building
	return null


func _get_or_create_array(index: Dictionary, key: Variant) -> Array:
	if not index.has(key):
		index[key] = []
	return index[key]
