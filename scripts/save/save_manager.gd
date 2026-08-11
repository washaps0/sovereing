extends Node

const SAVE_DIRECTORY := "user://saves"
const WORLD_SCENE := "res://scenes/world.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const SAVE_VERSION := 9
const AUTOSAVE_NAME := "Автосохранение"
const AUTOSAVE_INTERVAL_SECONDS := 120.0

var current_seed := 12345
var pending_save_data: Dictionary = {}
var autosave_elapsed := 0.0
var last_autosave_error := ""


func _ready():
	_ensure_save_directory()


func _process(delta: float):
	var world := get_tree().current_scene
	if not is_instance_valid(world) or world.scene_file_path != WORLD_SCENE or not world.has_method("get_save_data"):
		autosave_elapsed = 0.0
		return
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager) and network_manager.is_lan_session() and not network_manager.is_host():
		autosave_elapsed = 0.0
		return
	autosave_elapsed += delta
	if autosave_elapsed < AUTOSAVE_INTERVAL_SECONDS:
		return
	autosave_elapsed = fmod(autosave_elapsed, AUTOSAVE_INTERVAL_SECONDS)
	last_autosave_error = save_game(AUTOSAVE_NAME, world)


func seed_from_text(value: String) -> int:
	var cleaned := value.strip_edges()
	if cleaned.is_empty():
		return int(Time.get_unix_time_from_system()) & 0x7fffffff
	if cleaned.is_valid_int():
		return absi(int(cleaned)) & 0x7fffffff
	return absi(cleaned.hash()) & 0x7fffffff


func start_new_game(seed_value: int, ai_count := 3):
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		network_manager.prepare_singleplayer(seed_value, ai_count)
	current_seed = seed_value
	pending_save_data.clear()
	autosave_elapsed = 0.0
	last_autosave_error = ""
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD_SCENE)


func request_load(save_path: String) -> String:
	var data := get_save_data_for_multiplayer(save_path)
	if data.is_empty():
		return "Не удалось прочитать сохранение."
	if not data.has("world") or not data.has("meta"):
		return "Файл сохранения повреждён."
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		network_manager.shutdown_network()
	current_seed = int(data.meta.get("seed", 12345))
	pending_save_data = data.world
	autosave_elapsed = 0.0
	last_autosave_error = ""
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD_SCENE)
	return ""


func get_save_data_for_multiplayer(save_path: String) -> Dictionary:
	var data := _read_save(save_path)
	if data.is_empty() or not data.has("world") or not data.has("meta"):
		return {}
	return data


func consume_pending_save() -> Dictionary:
	var result := pending_save_data.duplicate(true)
	pending_save_data.clear()
	return result


func save_game(save_name: String, world: Node) -> String:
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager) and network_manager.is_lan_session() and not network_manager.is_host():
		return "В LAN-сессии сохранение доступно только хосту."
	var cleaned_name := save_name.strip_edges()
	if cleaned_name.is_empty():
		return "Введите название сохранения."
	if not is_instance_valid(world) or not world.has_method("get_save_data"):
		return "Текущий мир нельзя сохранить."
	_ensure_save_directory()
	var data := {
		"meta": {
			"name": cleaned_name,
			"saved_at": Time.get_datetime_string_from_system(false, true),
			"seed": current_seed,
			"version": SAVE_VERSION,
		},
		"world": world.get_save_data(),
	}
	var save_path := _path_for_name(cleaned_name)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return "Не удалось создать файл сохранения."
	file.store_string(JSON.stringify(data, "\t"))
	return ""


func list_saves() -> Array[Dictionary]:
	_ensure_save_directory()
	var result: Array[Dictionary] = []
	var directory := DirAccess.open(SAVE_DIRECTORY)
	if directory == null:
		return result
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.get_extension() == "json":
			var path := SAVE_DIRECTORY.path_join(file_name)
			var data := _read_save(path)
			if data.has("meta"):
				var entry: Dictionary = data.meta.duplicate(true)
				entry["path"] = path
				result.append(entry)
		file_name = directory.get_next()
	directory.list_dir_end()
	result.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.get("saved_at", "")) > str(b.get("saved_at", "")))
	return result


func delete_save(save_path: String) -> bool:
	if not save_path.begins_with(SAVE_DIRECTORY + "/"):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path)) == OK


func return_to_main_menu():
	var network_manager := get_node_or_null("/root/NetworkManager")
	if is_instance_valid(network_manager):
		network_manager.shutdown_network()
	pending_save_data.clear()
	autosave_elapsed = 0.0
	last_autosave_error = ""
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _path_for_name(save_name: String) -> String:
	return SAVE_DIRECTORY.path_join(save_name.sha256_text().substr(0, 24) + ".json")


func _ensure_save_directory():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIRECTORY))


func _read_save(save_path: String) -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
