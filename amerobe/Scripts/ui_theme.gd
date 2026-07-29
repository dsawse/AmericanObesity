class_name UiTheme
extends RefCounted

## Central place for the game's colours and StyleBox factories.
##
## Everything is built in code rather than as a .tres so the look can be tuned
## from one file and stays consistent across the procedurally-built screens.

const BG_DARK := Color(0.08, 0.07, 0.09, 0.94)
const BG_PANEL := Color(0.13, 0.12, 0.15, 0.94)
const BG_ROW := Color(0.17, 0.16, 0.19, 0.90)
const BG_ROW_HOVER := Color(0.23, 0.21, 0.25, 0.95)
const ACCENT := Color(0.91, 0.42, 0.19)
const ACCENT_DIM := Color(0.45, 0.24, 0.13)
const GOOD := Color(0.36, 0.78, 0.38)
const LOCKED := Color(0.42, 0.40, 0.44)
const TEXT := Color(0.96, 0.95, 0.93)
const TEXT_DIM := Color(0.68, 0.66, 0.70)
const GOLD := Color(0.98, 0.80, 0.31)


static func panel(bg: Color = BG_PANEL, radius: int = 10, border: int = 0,
		border_color: Color = ACCENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	if border > 0:
		style.border_width_left = border
		style.border_width_right = border
		style.border_width_top = border
		style.border_width_bottom = border
		style.border_color = border_color
	return style


static func flat(color: Color, radius: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


static func style_label(label: Label, size: int, color: Color = TEXT) -> Label:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", maxi(2, size / 10))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return label


static func make_label(text: String, size: int, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	return style_label(label, size, color)


static func style_progress(bar: ProgressBar, fill: Color,
		bg: Color = Color(0.18, 0.17, 0.20, 0.9)) -> ProgressBar:
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", flat(bg, 5))
	bar.add_theme_stylebox_override("fill", flat(fill, 5))
	return bar


static func style_button(button: Button, base: Color = ACCENT) -> Button:
	var normal := flat(base, 8)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = base.lightened(0.15)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = base.darkened(0.20)

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = LOCKED.darkened(0.3)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", TEXT_DIM)
	return button
