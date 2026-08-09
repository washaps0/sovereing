extends Control

var new_game_box: VBoxContainer
var load_box: VBoxContainer
var seed_input: LineEdit
var saves_list: ItemList
var load_button: Button
var delete_button: Button
var message_label: Label
var saves: Array[Dictionary] = []


func _ready():
	theme = SovereignUITheme.create_theme()
	_create_interface()
	_refresh_saves()


func _create_interface():
	var background := ColorRect.new()
	background.color = Color(0.035, 0.055, 0.075, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "SOVEREIGN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", SovereignUITheme.ACCENT_BRIGHT)
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Поселение • Государство • Война"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", SovereignUITheme.MUTED)
	box.add_child(subtitle)

	var new_button := Button.new()
	new_button.text = "Новая игра"
	new_button.pressed.connect(_show_new_game)
	box.add_child(new_button)
	var show_load_button := Button.new()
	show_load_button.text = "Загрузить игру"
	show_load_button.pressed.connect(_show_load_game)
	box.add_child(show_load_button)
	var quit_button := Button.new()
	quit_button.text = "Выйти"
	quit_button.pressed.connect(func(): get_tree().quit())
	box.add_child(quit_button)

	new_game_box = VBoxContainer.new()
	new_game_box.visible = false
	box.add_child(new_game_box)
	var seed_label := Label.new()
	seed_label.text = "Сид мира (число или любое слово):"
	new_game_box.add_child(seed_label)
	seed_input = LineEdit.new()
	seed_input.placeholder_text = "Пусто — случайный сид"
	seed_input.text_submitted.connect(func(_value): _start_new_game())
	new_game_box.add_child(seed_input)
	var start_button := Button.new()
	start_button.text = "Начать новую игру"
	start_button.pressed.connect(_start_new_game)
	new_game_box.add_child(start_button)

	load_box = VBoxContainer.new()
	load_box.visible = false
	box.add_child(load_box)
	var saves_title := Label.new()
	saves_title.text = "Сохранения:"
	load_box.add_child(saves_title)
	saves_list = ItemList.new()
	saves_list.custom_minimum_size = Vector2(420, 190)
	saves_list.item_selected.connect(_on_save_selected)
	saves_list.item_activated.connect(func(_index): _load_selected_save())
	load_box.add_child(saves_list)
	var save_buttons := HBoxContainer.new()
	load_box.add_child(save_buttons)
	load_button = Button.new()
	load_button.text = "Загрузить"
	load_button.disabled = true
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_button.pressed.connect(_load_selected_save)
	save_buttons.add_child(load_button)
	delete_button = Button.new()
	delete_button.text = "Удалить"
	delete_button.disabled = true
	delete_button.pressed.connect(_delete_selected_save)
	save_buttons.add_child(delete_button)

	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(message_label)


func _show_new_game():
	new_game_box.visible = true
	load_box.visible = false
	message_label.text = ""
	seed_input.grab_focus()


func _show_load_game():
	new_game_box.visible = false
	load_box.visible = true
	message_label.text = ""
	_refresh_saves()


func _start_new_game():
	var seed_value := SaveManager.seed_from_text(seed_input.text)
	SaveManager.start_new_game(seed_value)


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
	if saves.is_empty() and load_box.visible:
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
