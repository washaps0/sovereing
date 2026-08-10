extends CanvasLayer

var overlay: Control
var main_box: VBoxContainer
var save_box: VBoxContainer
var save_name_input: LineEdit
var saves_list: ItemList
var message_label: Label
var saves: Array[Dictionary] = []
var save_menu_button: Button


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_interface()
	overlay.visible = false


func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if overlay.visible and save_box.visible:
			_show_pause_page()
		else:
			_toggle_pause()
		get_viewport().set_input_as_handled()


func _create_interface():
	overlay = Control.new()
	overlay.theme = SovereignUITheme.create_theme()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.025, 0.035, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430, 0)
	center.add_child(panel)
	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 10)
	panel.add_child(root_box)
	var title := Label.new()
	title.text = "ПАУЗА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", SovereignUITheme.ACCENT_BRIGHT)
	root_box.add_child(title)
	var network_label := Label.new()
	network_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	network_label.add_theme_color_override("font_color", SovereignUITheme.MUTED)
	if NetworkManager.is_lan_session():
		var slot := NetworkManager.get_faction_slot(NetworkManager.get_local_faction_id())
		network_label.text = "LAN • %s" % str(slot.get("nickname", NetworkManager.local_nickname))
	else:
		network_label.text = "Одиночная игра"
	root_box.add_child(network_label)

	main_box = VBoxContainer.new()
	root_box.add_child(main_box)
	_add_main_button("Продолжить", _toggle_pause)
	save_menu_button = _add_main_button("Сохранить игру", _show_save_page)
	if NetworkManager.is_lan_session() and not NetworkManager.is_host():
		save_menu_button.text = "Сохранение доступно хосту"
		save_menu_button.disabled = true
	_add_main_button("Выйти в главное меню", _return_to_menu)
	_add_main_button("Выйти из игры", _quit_game)

	save_box = VBoxContainer.new()
	save_box.visible = false
	root_box.add_child(save_box)
	var name_label := Label.new()
	name_label.text = "Название сохранения:"
	save_box.add_child(name_label)
	save_name_input = LineEdit.new()
	save_name_input.placeholder_text = "Например: Перед постройкой завода"
	save_name_input.text_submitted.connect(func(_value): _save_game())
	save_box.add_child(save_name_input)
	var list_label := Label.new()
	list_label.text = "Все сохранения (выберите для перезаписи):"
	save_box.add_child(list_label)
	saves_list = ItemList.new()
	saves_list.custom_minimum_size = Vector2(390, 180)
	saves_list.item_selected.connect(_on_save_selected)
	save_box.add_child(saves_list)
	var buttons := HBoxContainer.new()
	save_box.add_child(buttons)
	var save_button := Button.new()
	save_button.text = "Сохранить"
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(_save_game)
	buttons.add_child(save_button)
	var back_button := Button.new()
	back_button.text = "Назад"
	back_button.pressed.connect(_show_pause_page)
	buttons.add_child(back_button)

	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(message_label)


func _add_main_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	main_box.add_child(button)
	return button


func _toggle_pause():
	if overlay.visible:
		overlay.visible = false
		get_tree().paused = false
	else:
		overlay.visible = true
		_show_pause_page()
		# В LAN локальная пауза рассинхронизировала бы клиента с хостом.
		get_tree().paused = not NetworkManager.is_lan_session()


func _show_pause_page():
	main_box.visible = true
	save_box.visible = false
	message_label.text = ""


func _show_save_page():
	main_box.visible = false
	save_box.visible = true
	message_label.text = ""
	_refresh_saves()
	save_name_input.grab_focus()


func _refresh_saves():
	saves = SaveManager.list_saves()
	saves_list.clear()
	for save in saves:
		var label := "%s\n%s  •  сид %d" % [save.get("name", "Без названия"), save.get("saved_at", ""), int(save.get("seed", 0))]
		saves_list.add_item(label)


func _on_save_selected(index: int):
	if index >= 0 and index < saves.size():
		save_name_input.text = str(saves[index].get("name", ""))
		message_label.text = "Сохранение с таким названием будет перезаписано."


func _save_game():
	var error := SaveManager.save_game(save_name_input.text, get_parent())
	if not error.is_empty():
		message_label.text = error
		return
	message_label.text = "Игра сохранена: %s" % save_name_input.text.strip_edges()
	_refresh_saves()


func _return_to_menu():
	overlay.visible = false
	SaveManager.return_to_main_menu()


func _quit_game():
	NetworkManager.shutdown_network()
	get_tree().quit()
