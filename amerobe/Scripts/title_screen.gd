extends Control

## Title screen. Built in code for the same reason as the kitchen: one place
## to read, no hidden node paths.

var _continue_button: Button
var _confirm: ConfirmationDialog


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture = PlaceholderArt.title_art()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.02, 0.02, 0.03, 0.55)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 14)
	center.add_child(stack)

	var title := UiTheme.make_label("AMERICAN OBESITY", 76, UiTheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)

	var tagline := UiTheme.make_label(
		"A clicker about appetite, automation and 3,500 calories a pound.",
		22, UiTheme.TEXT_DIM)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(tagline)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 26)
	stack.add_child(spacer)

	if not SceneManager.engine_available:
		var warning := UiTheme.make_label(SceneManager.engine_error, 17,
			Color(0.95, 0.6, 0.6))
		warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warning.custom_minimum_size = Vector2(760, 0)
		stack.add_child(warning)

	_continue_button = _menu_button(stack, "Continue", _on_continue_pressed)
	_continue_button.visible = SceneManager.engine_available and SceneManager.has_save()

	_menu_button(stack, "New Game", _on_new_game_pressed)
	_menu_button(stack, "Quit", _on_quit_pressed, UiTheme.ACCENT_DIM)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Start over?"
	_confirm.dialog_text = "This deletes your saved progress. There is no undo."
	_confirm.confirmed.connect(_start_fresh_run)
	add_child(_confirm)


func _menu_button(parent: Node, text: String, handler: Callable,
		color: Color = UiTheme.ACCENT) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 58)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 24)
	UiTheme.style_button(button, color)
	button.pressed.connect(handler)
	parent.add_child(button)
	return button


func _on_continue_pressed() -> void:
	SceneManager.go_to_main()


func _on_new_game_pressed() -> void:
	if SceneManager.has_save():
		_confirm.popup_centered()
	else:
		_start_fresh_run()


func _start_fresh_run() -> void:
	if SceneManager.engine_available:
		SceneManager.game.reset()
		SceneManager.game.mark_seen(Time.get_unix_time_from_system())
		SceneManager.save_game()
		SceneManager.startup_events = []
		SceneManager.pending_tier = 1
	SceneManager.go_to_main()


func _on_quit_pressed() -> void:
	SceneManager.save_game()
	get_tree().quit()
