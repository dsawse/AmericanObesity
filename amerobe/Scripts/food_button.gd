class_name FoodButton
extends Control

## One clickable food item: icon, name, calorie value, cooldown bar and the
## little "+1.2K" that floats off when you land a bite.
##
## The button owns no game state — it asks [code]SceneManager[/code] for the
## cooldown every frame and reports clicks back through [signal eaten].

signal eaten(id: String, calories: float)

const CARD_SIZE := Vector2(210.0, 230.0)

var food_id := ""
var unlocked := false

var _cooldown_total := 1.0
var _accent := Color.WHITE

var _panel: PanelContainer
var _icon: TextureRect
var _name_label: Label
var _value_label: Label
var _cooldown_bar: ProgressBar
var _hit: Button


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	pivot_offset = CARD_SIZE * 0.5
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	_build()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(column)

	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(112, 112)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_icon)

	_name_label = UiTheme.make_label("", 20)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_name_label)

	_value_label = UiTheme.make_label("", 17, UiTheme.GOLD)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_value_label)

	_cooldown_bar = ProgressBar.new()
	_cooldown_bar.custom_minimum_size = Vector2(0, 8)
	_cooldown_bar.max_value = 1.0
	_cooldown_bar.value = 0.0
	_cooldown_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.style_progress(_cooldown_bar, UiTheme.GOOD)
	column.add_child(_cooldown_bar)

	# Transparent hit area on top of everything else.
	_hit = Button.new()
	_hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hit.flat = true
	_hit.focus_mode = Control.FOCUS_NONE
	_hit.pressed.connect(_on_pressed)
	add_child(_hit)


## Applies one entry from [code]SceneManager.foods()[/code].
func configure(data: Dictionary) -> void:
	if not is_node_ready():
		await ready

	food_id = String(data.get("id", ""))
	unlocked = bool(data.get("unlocked", false))
	_cooldown_total = maxf(float(data.get("cooldown", 1.0)), 0.01)
	_accent = Color.from_string(String(data.get("color", "#ffffff")), Color.WHITE)

	_icon.texture = PlaceholderArt.texture_for_food(food_id, _accent)
	_panel.add_theme_stylebox_override("panel",
		UiTheme.panel(UiTheme.BG_PANEL, 12, 3, _accent if unlocked else UiTheme.LOCKED))

	if unlocked:
		_name_label.text = String(data.get("name", ""))
		UiTheme.style_label(_name_label, 20, UiTheme.TEXT)
		_icon.modulate = Color.WHITE
		_hit.disabled = false
		_hit.tooltip_text = "%s — %s cal, %.2fs cooldown" % [
			String(data.get("name", "")),
			Num.fmt(float(data.get("calories", 0.0))),
			_cooldown_total,
		]
	else:
		_name_label.text = "???"
		UiTheme.style_label(_name_label, 20, UiTheme.TEXT_DIM)
		_icon.modulate = Color(0.18, 0.18, 0.20, 0.9)
		_hit.disabled = true
		_hit.tooltip_text = "Unlocks at tier %d" % int(data.get("unlock_tier", 1))

	refresh_value(float(data.get("calories", 0.0)))


## Called when the click multiplier changes so the card stays truthful.
func refresh_value(calories: float) -> void:
	if not is_instance_valid(_value_label):
		return
	if unlocked:
		_value_label.text = "+%s cal" % Num.fmt(calories)
		_value_label.modulate = Color.WHITE
	else:
		_value_label.text = "locked"
		_value_label.modulate = Color(1, 1, 1, 0.45)


func _process(_delta: float) -> void:
	if food_id.is_empty() or not unlocked or not is_instance_valid(_cooldown_bar):
		return
	var remaining := SceneManager.cooldown_remaining(food_id)
	_cooldown_bar.value = 1.0 - clampf(remaining / _cooldown_total, 0.0, 1.0)
	_panel.modulate = Color(0.72, 0.72, 0.72) if remaining > 0.0 else Color.WHITE


func _on_pressed() -> void:
	if not unlocked:
		return
	var gained := SceneManager.click_food(food_id)
	if gained <= 0.0:
		_nudge_rejected()
		return

	eaten.emit(food_id, gained)
	_punch()
	_float_text("+%s" % Num.fmt(gained))


func _punch() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.06)
	tween.tween_property(self, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _nudge_rejected() -> void:
	# Still cooling down. Flash the border rather than move the card, because
	# the card's position is owned by the parent container.
	if not is_instance_valid(_panel):
		return
	var tween := create_tween()
	# `self_modulate` tints only the panel's own stylebox, so it does not fight
	# the per-frame `modulate` dimming applied in _process().
	tween.tween_property(_panel, "self_modulate", Color(1.6, 0.6, 0.6), 0.05)
	tween.tween_property(_panel, "self_modulate", Color.WHITE, 0.15)


func _float_text(text: String) -> void:
	var label := UiTheme.make_label(text, 26, UiTheme.GOLD)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 10
	label.position = Vector2(size.x * 0.5 - 30.0, size.y * 0.28)
	add_child(label)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 70.0, 0.75) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.75)
	tween.chain().tween_callback(label.queue_free)
