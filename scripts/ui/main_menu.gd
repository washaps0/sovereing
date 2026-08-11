extends Control

var panel: PanelContainer
var game_title: Label
var game_subtitle: Label
var page_scroll: ScrollContainer
var page_stack: VBoxContainer
var pages: Array[Control] = []
var main_page: VBoxContainer
var new_game_page: VBoxContainer
var load_page: VBoxContainer
var multiplayer_page: VBoxContainer
var host_setup_page: VBoxContainer
var join_setup_page: VBoxContainer
var lobby_page: VBoxContainer
var seed_input: LineEdit
var singleplayer_ai_count: SpinBox
var saves_list: ItemList
var load_button: Button
var delete_button: Button
var message_label: Label
var nickname_input: LineEdit
var host_seed_input: LineEdit
var host_ai_count: SpinBox
var host_save_picker: OptionButton
var host_saves: Array[Dictionary] = []
var host_port_input: SpinBox
var join_address_input: LineEdit
var join_port_input: SpinBox
var discovered_lobbies_list: ItemList
var discovered_lobbies_status: Label
var join_discovered_button: Button
var discovered_lobbies: Array = []
var lobby_settings_label: Label
var lobby_address_label: Label
var lobby_players_list: ItemList
var ready_button: Button
var faction_choice_box: VBoxContainer
var faction_choice_picker: OptionButton
var updating_faction_choice := false
var saves: Array[Dictionary] = []
var current_ui_scale := -1.0


func _ready():
	current_ui_scale = SovereignUITheme.get_scale(get_viewport().get_visible_rect().size)
	theme = SovereignUITheme.create_theme(current_ui_scale)
	_create_interface()
	NetworkManager.lobby_state_changed.connect(_on_lobby_state_changed)
	NetworkManager.connection_state_changed.connect(_on_connection_state_changed)
	NetworkManager.network_error.connect(_on_network_error)
	NetworkManager.discovered_lobbies_changed.connect(_on_discovered_lobbies_changed)
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()
	_refresh_saves()
	_on_discovered_lobbies_changed(NetworkManager.get_discovered_lobbies())
	var notice := NetworkManager.consume_menu_notice()
	if not notice.is_empty():
		message_label.text = notice
	if NetworkManager.lobby_active:
		_show_page(lobby_page, false)
		_on_lobby_state_changed(NetworkManager.get_lobby_players(), NetworkManager.lobby_settings)


func _create_interface():
	var background := ColorRect.new()
	background.color = Color(0.035, 0.055, 0.075, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(center)
	panel = PanelContainer.new()
	center.add_child(panel)
	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 10)
	panel.add_child(root_box)

	game_title = Label.new()
	game_title.text = "SOVEREIGN"
	game_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_title.add_theme_font_size_override("font_size", 32)
	game_title.add_theme_color_override("font_color", SovereignUITheme.ACCENT_BRIGHT)
	root_box.add_child(game_title)
	game_subtitle = Label.new()
	game_subtitle.text = "Поселение • Государство • Война"
	game_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_subtitle.add_theme_color_override("font_color", SovereignUITheme.MUTED)
	root_box.add_child(game_subtitle)

	page_scroll = ScrollContainer.new()
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	page_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.add_child(page_scroll)
	page_stack = VBoxContainer.new()
	page_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_scroll.add_child(page_stack)

	_create_main_page()
	_create_new_game_page()
	_create_load_page()
	_create_multiplayer_page()
	_create_host_setup_page()
	_create_join_setup_page()
	_create_lobby_page()

	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_color_override("font_color", SovereignUITheme.MUTED)
	root_box.add_child(message_label)
	_show_page(main_page)


func _create_main_page():
	main_page = _new_page()
	_add_button(main_page, "Новая игра", _show_new_game_page)
	_add_button(main_page, "Загрузить игру", _show_load_game)
	_add_button(main_page, "Мультиплеер по LAN", _show_multiplayer_page)
	_add_button(main_page, "Выйти", func(): get_tree().quit())


func _create_new_game_page():
	new_game_page = _new_page()
	_add_page_title(new_game_page, "Новая игра")
	var seed_label := Label.new()
	seed_label.text = "Сид мира (число или любое слово):"
	new_game_page.add_child(seed_label)
	seed_input = LineEdit.new()
	seed_input.placeholder_text = "Пусто — случайный сид"
	seed_input.text_submitted.connect(func(_value): _start_new_game())
	new_game_page.add_child(seed_input)
	var ai_label := Label.new()
	ai_label.text = "Количество ИИ:"
	new_game_page.add_child(ai_label)
	singleplayer_ai_count = SpinBox.new()
	singleplayer_ai_count.min_value = 0
	singleplayer_ai_count.max_value = NetworkManager.MAX_FACTIONS - 1
	singleplayer_ai_count.step = 1
	singleplayer_ai_count.value = 3
	new_game_page.add_child(singleplayer_ai_count)
	_add_button(new_game_page, "Начать новую игру", _start_new_game)
	_add_button(new_game_page, "Назад", func(): _show_page(main_page))


func _create_load_page():
	load_page = _new_page()
	_add_page_title(load_page, "Загрузить игру")
	var saves_title := Label.new()
	saves_title.text = "Сохранения:"
	load_page.add_child(saves_title)
	saves_list = ItemList.new()
	saves_list.custom_minimum_size = Vector2(0, 130)
	saves_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saves_list.item_selected.connect(_on_save_selected)
	saves_list.item_activated.connect(func(_index): _load_selected_save())
	load_page.add_child(saves_list)
	load_button = _add_button(load_page, "Загрузить", _load_selected_save)
	load_button.disabled = true
	delete_button = _add_button(load_page, "Удалить", _delete_selected_save)
	delete_button.disabled = true
	_add_button(load_page, "Назад", func(): _show_page(main_page))


func _create_multiplayer_page():
	multiplayer_page = _new_page()
	_add_page_title(multiplayer_page, "Мультиплеер по локальной сети")
	var nickname_label := Label.new()
	nickname_label.text = "Ваш никнейм:"
	multiplayer_page.add_child(nickname_label)
	nickname_input = LineEdit.new()
	nickname_input.max_length = 24
	nickname_input.text = NetworkManager.local_nickname
	nickname_input.placeholder_text = "Игрок"
	multiplayer_page.add_child(nickname_input)
	var hint := Label.new()
	hint.text = "Активные лобби в локальной сети находятся автоматически. Ручной ввод адреса тоже доступен."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", SovereignUITheme.MUTED)
	multiplayer_page.add_child(hint)
	_add_button(multiplayer_page, "Создать игру", _show_host_setup)
	var discovered_title := Label.new()
	discovered_title.text = "Найденные лобби:"
	multiplayer_page.add_child(discovered_title)
	discovered_lobbies_list = ItemList.new()
	discovered_lobbies_list.custom_minimum_size = Vector2(0, 130)
	discovered_lobbies_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	discovered_lobbies_list.item_selected.connect(_on_discovered_lobby_selected)
	discovered_lobbies_list.item_activated.connect(func(_index): _join_discovered_lobby())
	multiplayer_page.add_child(discovered_lobbies_list)
	discovered_lobbies_status = Label.new()
	discovered_lobbies_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	discovered_lobbies_status.add_theme_color_override("font_color", SovereignUITheme.MUTED)
	multiplayer_page.add_child(discovered_lobbies_status)
	join_discovered_button = _add_button(multiplayer_page, "Подключиться к выбранному", _join_discovered_lobby)
	join_discovered_button.disabled = true
	_add_button(multiplayer_page, "Обновить список", _refresh_discovered_lobbies)
	_add_button(multiplayer_page, "Ввести адрес вручную", _show_join_setup)
	_add_button(multiplayer_page, "Назад", func(): _show_page(main_page))


func _create_host_setup_page():
	host_setup_page = _new_page()
	_add_page_title(host_setup_page, "Настройки хоста")
	var world_label := Label.new()
	world_label.text = "Мир:"
	host_setup_page.add_child(world_label)
	host_save_picker = OptionButton.new()
	host_save_picker.fit_to_longest_item = false
	host_save_picker.item_selected.connect(_on_host_world_selected)
	host_setup_page.add_child(host_save_picker)
	var seed_label := Label.new()
	seed_label.text = "Сид мира:"
	host_setup_page.add_child(seed_label)
	host_seed_input = LineEdit.new()
	host_seed_input.placeholder_text = "Пусто — случайный сид"
	host_setup_page.add_child(host_seed_input)
	var ai_label := Label.new()
	ai_label.text = "Количество ИИ (лишние не займут место игрока):"
	ai_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host_setup_page.add_child(ai_label)
	host_ai_count = SpinBox.new()
	host_ai_count.min_value = 0
	host_ai_count.max_value = NetworkManager.MAX_FACTIONS - 1
	host_ai_count.step = 1
	host_ai_count.value = 3
	host_setup_page.add_child(host_ai_count)
	var port_label := Label.new()
	port_label.text = "UDP-порт:"
	host_setup_page.add_child(port_label)
	host_port_input = _create_port_input()
	host_setup_page.add_child(host_port_input)
	_add_button(host_setup_page, "Создать лобби", _create_lobby)
	_add_button(host_setup_page, "Назад", func(): _show_page(multiplayer_page))


func _create_join_setup_page():
	join_setup_page = _new_page()
	_add_page_title(join_setup_page, "Подключение к игре")
	var address_label := Label.new()
	address_label.text = "IP-адрес или имя компьютера хоста:"
	join_setup_page.add_child(address_label)
	join_address_input = LineEdit.new()
	join_address_input.text = "127.0.0.1"
	join_address_input.placeholder_text = "Например: 192.168.1.25"
	join_address_input.text_submitted.connect(func(_value): _join_lobby())
	join_setup_page.add_child(join_address_input)
	var port_label := Label.new()
	port_label.text = "UDP-порт:"
	join_setup_page.add_child(port_label)
	join_port_input = _create_port_input()
	join_setup_page.add_child(join_port_input)
	_add_button(join_setup_page, "Подключиться", _join_lobby)
	_add_button(join_setup_page, "Назад", func(): _show_page(multiplayer_page))


func _create_lobby_page():
	lobby_page = _new_page()
	_add_page_title(lobby_page, "Лобби")
	lobby_settings_label = Label.new()
	lobby_settings_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_page.add_child(lobby_settings_label)
	lobby_address_label = Label.new()
	lobby_address_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_address_label.add_theme_color_override("font_color", SovereignUITheme.MUTED)
	lobby_page.add_child(lobby_address_label)
	lobby_players_list = ItemList.new()
	lobby_players_list.custom_minimum_size = Vector2(0, 120)
	lobby_players_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_players_list.select_mode = ItemList.SELECT_SINGLE
	lobby_page.add_child(lobby_players_list)
	faction_choice_box = VBoxContainer.new()
	faction_choice_box.visible = false
	lobby_page.add_child(faction_choice_box)
	var faction_choice_label := Label.new()
	faction_choice_label.text = "Все государства заняты. Выберите ИИ, которого вы замените:"
	faction_choice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	faction_choice_box.add_child(faction_choice_label)
	faction_choice_picker = OptionButton.new()
	faction_choice_picker.fit_to_longest_item = false
	faction_choice_picker.item_selected.connect(_on_faction_choice_selected)
	faction_choice_box.add_child(faction_choice_picker)
	var ready_hint := Label.new()
	ready_hint.text = "Игра запустится, когда все подключённые игроки нажмут «Готов». Хосту лучше нажимать последним."
	ready_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ready_hint.add_theme_color_override("font_color", SovereignUITheme.MUTED)
	lobby_page.add_child(ready_hint)
	ready_button = _add_button(lobby_page, "Готов", _unused_callback)
	ready_button.toggle_mode = true
	ready_button.toggled.connect(_on_ready_toggled)
	_add_button(lobby_page, "Покинуть лобби", _leave_lobby)


func _new_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.visible = false
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8)
	page_stack.add_child(page)
	pages.append(page)
	return page


func _add_page_title(page: VBoxContainer, value: String):
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", SovereignUITheme.ACCENT_BRIGHT)
	page.add_child(label)


func _add_button(page: VBoxContainer, value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.pressed.connect(callback)
	page.add_child(button)
	return button


func _unused_callback():
	pass


func _create_port_input() -> SpinBox:
	var input := SpinBox.new()
	input.min_value = 1024
	input.max_value = 65535
	input.step = 1
	input.value = NetworkManager.DEFAULT_PORT
	input.update_on_text_changed = true
	return input


func _show_page(page: Control, clear_message := true):
	for item in pages:
		item.visible = item == page
	if clear_message:
		message_label.text = ""
	page_scroll.scroll_vertical = 0


func _show_load_game():
	_show_page(load_page)
	_refresh_saves()


func _show_new_game_page():
	_show_page(new_game_page)
	seed_input.grab_focus()


func _show_multiplayer_page():
	_show_page(multiplayer_page)
	NetworkManager.refresh_lan_lobbies()
	nickname_input.grab_focus()


func _show_host_setup():
	NetworkManager.set_local_nickname(nickname_input.text)
	nickname_input.text = NetworkManager.local_nickname
	_refresh_host_worlds()
	_show_page(host_setup_page)
	host_save_picker.grab_focus()


func _show_join_setup():
	NetworkManager.set_local_nickname(nickname_input.text)
	nickname_input.text = NetworkManager.local_nickname
	_show_page(join_setup_page)
	join_address_input.grab_focus()


func _refresh_discovered_lobbies():
	join_discovered_button.disabled = true
	discovered_lobbies_status.text = "Поиск лобби в локальной сети…"
	NetworkManager.refresh_lan_lobbies()


func _on_discovered_lobbies_changed(lobbies: Array):
	discovered_lobbies = lobbies
	if discovered_lobbies_list == null:
		return
	var selected_key := ""
	var selected_items := discovered_lobbies_list.get_selected_items()
	if not selected_items.is_empty():
		var previous_metadata = discovered_lobbies_list.get_item_metadata(selected_items[0])
		if previous_metadata is Dictionary:
			selected_key = str(previous_metadata.get("key", ""))
	discovered_lobbies_list.clear()
	var restored_selection := -1
	for lobby in discovered_lobbies:
		if lobby is not Dictionary:
			continue
		var loaded_game := bool(lobby.get("loaded_game", false))
		var world_text := "сохранение «%s»" % str(lobby.get("save_name", "Без названия")) if loaded_game else "новый мир • сид %d" % int(lobby.get("seed", 0))
		var label := "%s • %d/%d • %s\n%s:%d" % [
			str(lobby.get("host_name", "Хост")),
			int(lobby.get("players", 1)),
			int(lobby.get("max_players", NetworkManager.MAX_FACTIONS)),
			world_text,
			str(lobby.get("address", "")),
			int(lobby.get("port", NetworkManager.DEFAULT_PORT)),
		]
		var index := discovered_lobbies_list.add_item(label)
		discovered_lobbies_list.set_item_metadata(index, lobby.duplicate(true))
		if str(lobby.get("key", "")) == selected_key:
			restored_selection = index
	if discovered_lobbies.is_empty():
		discovered_lobbies_status.text = "Активные лобби пока не найдены. Поиск продолжается автоматически."
	else:
		discovered_lobbies_status.text = "Найдено лобби: %d" % discovered_lobbies.size()
	if restored_selection >= 0:
		discovered_lobbies_list.select(restored_selection)
		_on_discovered_lobby_selected(restored_selection)
	else:
		join_discovered_button.disabled = true


func _on_discovered_lobby_selected(index: int):
	if index < 0 or index >= discovered_lobbies_list.item_count:
		join_discovered_button.disabled = true
		return
	var lobby = discovered_lobbies_list.get_item_metadata(index)
	if lobby is not Dictionary:
		join_discovered_button.disabled = true
		return
	var is_full := int(lobby.get("players", 0)) >= int(lobby.get("max_players", NetworkManager.MAX_FACTIONS))
	join_discovered_button.disabled = is_full
	discovered_lobbies_status.text = "Лобби заполнено." if is_full else "Можно подключиться к этому лобби."


func _join_discovered_lobby():
	var selected := discovered_lobbies_list.get_selected_items()
	if selected.is_empty():
		return
	var lobby = discovered_lobbies_list.get_item_metadata(selected[0])
	if lobby is not Dictionary or int(lobby.get("players", 0)) >= int(lobby.get("max_players", NetworkManager.MAX_FACTIONS)):
		return
	NetworkManager.set_local_nickname(nickname_input.text)
	nickname_input.text = NetworkManager.local_nickname
	join_address_input.text = str(lobby.get("address", ""))
	join_port_input.value = int(lobby.get("port", NetworkManager.DEFAULT_PORT))
	_join_lobby()


func _start_new_game():
	var seed_value := SaveManager.seed_from_text(seed_input.text)
	SaveManager.start_new_game(seed_value, int(singleplayer_ai_count.value))


func _create_lobby():
	var seed_value := SaveManager.seed_from_text(host_seed_input.text)
	var saved_game := {}
	if host_save_picker.selected > 0 and host_save_picker.selected - 1 < host_saves.size():
		saved_game = SaveManager.get_save_data_for_multiplayer(str(host_saves[host_save_picker.selected - 1].path))
		if saved_game.is_empty():
			message_label.text = "Не удалось прочитать выбранное сохранение."
			return
		seed_value = int(saved_game.meta.get("seed", seed_value))
	var error := NetworkManager.host_lobby(NetworkManager.local_nickname, seed_value, int(host_ai_count.value), int(host_port_input.value), saved_game)
	if not error.is_empty():
		message_label.text = error
		return
	_show_page(lobby_page, false)
	_refresh_lobby()


func _refresh_host_worlds():
	host_saves = SaveManager.list_saves()
	host_save_picker.clear()
	host_save_picker.add_item("Новый мир")
	for save in host_saves:
		host_save_picker.add_item("Загрузить: %s" % str(save.get("name", "Без названия")))
	host_save_picker.select(0)
	_on_host_world_selected(0)


func _on_host_world_selected(index: int):
	var loading_save := index > 0
	host_seed_input.editable = not loading_save
	host_ai_count.editable = not loading_save


func _join_lobby():
	var error := NetworkManager.join_lobby(NetworkManager.local_nickname, join_address_input.text, int(join_port_input.value))
	if not error.is_empty():
		message_label.text = error
		return
	_show_page(lobby_page, false)
	ready_button.disabled = true
	lobby_players_list.clear()
	lobby_players_list.add_item("Подключение…")


func _leave_lobby():
	NetworkManager.shutdown_network()
	ready_button.set_pressed_no_signal(false)
	_show_page(multiplayer_page)


func _on_ready_toggled(value: bool):
	NetworkManager.set_ready(value)
	ready_button.text = "Готов: ДА" if value else "Готов"


func _on_lobby_state_changed(_players: Array, _settings: Dictionary):
	if not lobby_page.visible:
		return
	_refresh_lobby()


func _refresh_lobby():
	lobby_players_list.clear()
	var players := NetworkManager.get_lobby_players()
	var loaded_game := bool(NetworkManager.lobby_settings.get("loaded_game", false))
	for player in players:
		var ready_text := "ГОТОВ" if bool(player.get("ready", false)) else "НЕ ГОТОВ"
		var host_text := " • ХОСТ" if int(player.get("peer_id", 0)) == 1 else ""
		var faction_text := ""
		if loaded_game:
			faction_text = " • государство %d" % (int(player.get("selected_faction_id", -1)) + 1) if int(player.get("selected_faction_id", -1)) >= 0 else " • выбор государства"
		lobby_players_list.add_item("%s  [%s]%s%s" % [player.get("nickname", "Игрок"), ready_text, host_text, faction_text])
	if loaded_game:
		lobby_settings_label.text = "Сохранение: %s  •  Игроки: %d/%d" % [str(NetworkManager.lobby_settings.get("save_name", "Без названия")), players.size(), NetworkManager.MAX_FACTIONS]
	else:
		var requested_ai := int(NetworkManager.lobby_settings.get("requested_ai_count", 0))
		var actual_ai := mini(requested_ai, maxi(NetworkManager.MAX_FACTIONS - players.size(), 0))
		lobby_settings_label.text = "Сид: %d  •  Игроки: %d/%d  •  ИИ: %d из %d" % [int(NetworkManager.lobby_settings.get("seed", 0)), players.size(), NetworkManager.MAX_FACTIONS, actual_ai, requested_ai]
	_refresh_faction_choice()
	if NetworkManager.is_host():
		var addresses := NetworkManager.get_local_addresses()
		lobby_address_label.text = "Адрес для подключения: %s  •  порт %d" % [", ".join(addresses) if not addresses.is_empty() else "локальный IP не найден", int(NetworkManager.lobby_settings.get("port", NetworkManager.DEFAULT_PORT))]
	else:
		lobby_address_label.text = "Подключено к LAN-лобби хоста."
	var local_ready := NetworkManager.is_local_ready()
	ready_button.set_pressed_no_signal(local_ready)
	ready_button.text = "Готов: ДА" if local_ready else "Готов"
	var local_player := NetworkManager.get_local_lobby_player()
	ready_button.disabled = NetworkManager.connection_pending or players.is_empty() or NetworkManager.match_starting or bool(local_player.get("requires_faction_choice", false))


func _refresh_faction_choice():
	var local_player := NetworkManager.get_local_lobby_player()
	var needs_choice := bool(local_player.get("requires_faction_choice", false))
	faction_choice_box.visible = needs_choice
	if not needs_choice:
		return
	updating_faction_choice = true
	faction_choice_picker.clear()
	var choices := NetworkManager.get_available_loaded_faction_choices()
	for choice in choices:
		var faction_id := int(choice.get("faction_id", -1))
		faction_choice_picker.add_item("Государство %d — %s" % [faction_id + 1, str(choice.get("nickname", "ИИ"))])
		faction_choice_picker.set_item_metadata(faction_choice_picker.item_count - 1, faction_id)
	var selected_faction := int(local_player.get("selected_faction_id", -1))
	for index in range(faction_choice_picker.item_count):
		if int(faction_choice_picker.get_item_metadata(index)) == selected_faction:
			faction_choice_picker.select(index)
			break
	updating_faction_choice = false


func _on_faction_choice_selected(index: int):
	if updating_faction_choice or index < 0 or index >= faction_choice_picker.item_count:
		return
	NetworkManager.choose_loaded_faction(int(faction_choice_picker.get_item_metadata(index)))


func _on_connection_state_changed(value: String):
	message_label.text = value
	if lobby_page.visible:
		_refresh_lobby()


func _on_network_error(value: String):
	message_label.text = value
	if lobby_page.visible:
		_show_page(join_setup_page, false)


func _refresh_saves():
	if saves_list == null:
		return
	saves = SaveManager.list_saves()
	saves_list.clear()
	for save in saves:
		var label := "%s\n%s  •  сид %d" % [save.get("name", "Без названия"), save.get("saved_at", ""), int(save.get("seed", 0))]
		saves_list.add_item(label)
	load_button.disabled = true
	delete_button.disabled = true
	if saves.is_empty() and load_page.visible:
		message_label.text = "Сохранений пока нет."


func _on_save_selected(_index: int):
	load_button.disabled = false
	delete_button.disabled = false
	message_label.text = ""


func _load_selected_save():
	var selected := saves_list.get_selected_items()
	if selected.is_empty():
		message_label.text = "Выберите сохранение."
		return
	var error := SaveManager.request_load(str(saves[selected[0]].path))
	if not error.is_empty():
		message_label.text = error


func _delete_selected_save():
	var selected := saves_list.get_selected_items()
	if selected.is_empty():
		return
	if SaveManager.delete_save(str(saves[selected[0]].path)):
		message_label.text = "Сохранение удалено."
	else:
		message_label.text = "Не удалось удалить сохранение."
	_refresh_saves()


func _update_layout():
	if panel == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var ui_scale := SovereignUITheme.get_scale(viewport_size)
	if not is_equal_approx(current_ui_scale, ui_scale):
		current_ui_scale = ui_scale
		theme = SovereignUITheme.create_theme(ui_scale)
	var width := minf(500.0 * ui_scale, maxf(viewport_size.x - 16.0, 1.0))
	panel.custom_minimum_size.x = width
	page_stack.custom_minimum_size.x = maxf(width - 18.0 * ui_scale, 1.0)
	page_scroll.custom_minimum_size.y = minf(maxf(viewport_size.y - 135.0 * ui_scale, 32.0), 400.0 * ui_scale)
	game_title.add_theme_font_size_override("font_size", maxi(roundi(30.0 * ui_scale), 18))
	game_subtitle.visible = viewport_size.y >= 300.0
