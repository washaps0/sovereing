class_name SovereignUITheme
extends RefCounted

const BACKGROUND := Color("101923")
const PANEL := Color("182634ee")
const PANEL_LIGHT := Color("203448f2")
const ACCENT := Color("43b5d9")
const ACCENT_BRIGHT := Color("69d4ef")
const TEXT := Color("e7f1f5")
const MUTED := Color("9eb2bd")
const DANGER := Color("d96464")


static func get_scale(viewport_size: Vector2) -> float:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return 1.0
	return clampf(minf(viewport_size.x / 1152.0, viewport_size.y / 648.0), 0.65, 1.0)


static func create_theme(ui_scale := 1.0) -> Theme:
	ui_scale = clampf(ui_scale, 0.65, 1.0)
	var label_font_size := maxi(roundi(13.0 * ui_scale), 9)
	var button_font_size := maxi(roundi(14.0 * ui_scale), 10)
	var padding := maxi(roundi(9.0 * ui_scale), 5)
	var radius := maxi(roundi(7.0 * ui_scale), 4)
	var result := Theme.new()
	result.default_font_size = label_font_size
	result.set_color("font_color", "Label", TEXT)
	result.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.5))
	result.set_constant("shadow_offset_x", "Label", 1)
	result.set_constant("shadow_offset_y", "Label", 1)
	result.set_color("font_color", "Button", TEXT)
	result.set_color("font_hover_color", "Button", Color.WHITE)
	result.set_color("font_pressed_color", "Button", Color.WHITE)
	result.set_color("font_disabled_color", "Button", MUTED.darkened(0.25))
	result.set_font_size("font_size", "Button", button_font_size)
	result.set_constant("outline_size", "Button", 0)

	result.set_stylebox("panel", "PanelContainer", _box(PANEL, ACCENT.darkened(0.45), 1, radius + 2, padding))
	result.set_stylebox("normal", "Button", _box(PANEL_LIGHT, Color("34536a"), 1, radius, padding - 1))
	result.set_stylebox("hover", "Button", _box(Color("294a60"), ACCENT, 1, radius, padding - 1))
	result.set_stylebox("pressed", "Button", _box(Color("176079"), ACCENT_BRIGHT, 1, radius, padding - 1))
	result.set_stylebox("focus", "Button", _box(Color.TRANSPARENT, ACCENT_BRIGHT, 1, radius, padding - 1))
	result.set_stylebox("disabled", "Button", _box(Color("17232d"), Color("263946"), 1, radius, padding - 1))

	result.set_color("font_color", "LineEdit", TEXT)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_color("caret_color", "LineEdit", ACCENT_BRIGHT)
	result.set_stylebox("normal", "LineEdit", _box(Color("101c27"), Color("355268"), 1, radius, padding - 1))
	result.set_stylebox("focus", "LineEdit", _box(Color("12222f"), ACCENT, 2, radius, padding - 1))

	result.set_color("font_color", "ItemList", TEXT)
	result.set_color("font_selected_color", "ItemList", Color.WHITE)
	result.set_stylebox("panel", "ItemList", _box(Color("0d1821"), Color("304a5c"), 1, 6, 6))
	result.set_stylebox("selected", "ItemList", _box(Color("1e6078"), ACCENT, 1, 5, 5))
	result.set_stylebox("selected_focus", "ItemList", _box(Color("236d87"), ACCENT_BRIGHT, 1, 5, 5))

	result.set_color("font_color", "TooltipLabel", TEXT)
	result.set_stylebox("panel", "TooltipPanel", _box(Color("0d1821f5"), ACCENT, 1, 5, 7))
	result.set_stylebox("slider", "HSlider", _box(Color("0e1820"), Color("314958"), 1, 4, 2))
	result.set_stylebox("grabber_area", "HSlider", _box(ACCENT.darkened(0.18), ACCENT, 0, 4, 2))
	result.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT_BRIGHT, ACCENT_BRIGHT, 0, 4, 2))
	return result


static func _box(background: Color, border: Color, border_width: int, radius: int, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style
