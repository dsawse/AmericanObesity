extends Control

## The between-tiers cutscene: a Pokémon-style flash-and-swap, then back to
## the kitchen. Click or press anything to skip.
##
## It reads the target tier from [code]SceneManager.pending_tier[/code] and
## calls [method SceneManager.finish_evolution] when it is done — which is the
## only way out of this scene.

const CYCLES := 5
const CYCLE_TIME := 0.34

var _finished := false
var _sprite: TextureRect
var _flash: ColorRect
var _caption: Label
var _tween: Tween


func _ready() -> void:
	_build_ui()

	if not SceneManager.engine_available:
		SceneManager.go_to_title()
		return

	_play()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Let clicks reach _unhandled_input so "click to skip" works anywhere.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.03, 0.05)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 20)
	center.add_child(stack)

	_sprite = TextureRect.new()
	_sprite.custom_minimum_size = Vector2(520, 520)
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.pivot_offset = Vector2(260, 260)
	_sprite.texture = PlaceholderArt.character(_previous_tier())
	stack.add_child(_sprite)

	_caption = UiTheme.make_label("What? You are evolving!", 40, UiTheme.GOLD)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_caption)

	var hint := UiTheme.make_label("(click to skip)", 16, UiTheme.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(hint)

	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)


func _target_tier() -> int:
	return maxi(SceneManager.pending_tier, 1)


func _previous_tier() -> int:
	return maxi(_target_tier() - 1, 1)


func _play() -> void:
	var before := PlaceholderArt.character(_previous_tier())
	var after := PlaceholderArt.character(_target_tier())

	_tween = create_tween()
	for i in CYCLES:
		var upcoming: Texture2D = after if i % 2 == 0 else before
		var stretch := 1.0 + 0.06 * float(i + 1)
		_tween.tween_property(_sprite, "scale", Vector2(stretch, stretch),
			CYCLE_TIME * 0.5).set_trans(Tween.TRANS_SINE)
		_tween.tween_callback(func() -> void: _sprite.texture = upcoming)
		_tween.tween_property(_sprite, "scale", Vector2.ONE, CYCLE_TIME * 0.5) \
			.set_trans(Tween.TRANS_SINE)

	# Whiteout, settle on the new form, then hand control back.
	_tween.tween_property(_flash, "color:a", 1.0, 0.28)
	_tween.tween_callback(_on_whiteout_peak.bind(after))
	_tween.tween_property(_flash, "color:a", 0.0, 0.45)
	_tween.tween_interval(0.9)
	_tween.tween_callback(_finish)


## Runs at the brightest point of the whiteout, when the swap is invisible.
func _on_whiteout_peak(final_texture: Texture2D) -> void:
	_sprite.texture = final_texture
	_caption.text = "Tier %d reached." % _target_tier()


func _unhandled_input(event: InputEvent) -> void:
	var skip := false
	if event is InputEventMouseButton and event.pressed:
		skip = true
	elif event is InputEventKey and event.pressed and not event.echo:
		skip = true
	if skip:
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	SceneManager.finish_evolution()
