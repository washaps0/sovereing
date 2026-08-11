class_name WorldAudioPool
extends Node2D

@export_range(8, 64, 1) var pool_size := 32

var _players: Array[AudioStreamPlayer2D] = []
var _last_used_msec: Array[int] = []


func _ready():
	add_to_group("world_audio_pool")
	for index in range(pool_size):
		var player := AudioStreamPlayer2D.new()
		player.name = "SpatialSound%d" % index
		player.attenuation = 2.0
		add_child(player)
		_players.append(player)
		_last_used_msec.append(0)


func play_spatial(stream: AudioStream, world_position: Vector2, max_distance: float, volume_db: float, pitch_scale: float):
	if stream == null or _players.is_empty():
		return
	var camera := get_viewport().get_camera_2d()
	if is_instance_valid(camera) and camera.global_position.distance_squared_to(world_position) > max_distance * max_distance * 1.44:
		return
	var selected_index := -1
	var oldest_time := Time.get_ticks_msec()
	for index in range(_players.size()):
		if not _players[index].playing:
			selected_index = index
			break
		if _last_used_msec[index] <= oldest_time:
			oldest_time = _last_used_msec[index]
			selected_index = index
	if selected_index < 0:
		return
	var player := _players[selected_index]
	player.stop()
	player.stream = stream
	player.global_position = world_position
	player.max_distance = max_distance
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	_last_used_msec[selected_index] = Time.get_ticks_msec()
	player.play()
