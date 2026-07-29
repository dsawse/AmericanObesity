class_name UpgradeRow
extends Control

## One row in the upgrade shop. Clicking anywhere on the row buys it.

signal purchase_requested(id: String)

const ROW_HEIGHT := 84.0

var upgrade_id := ""
var affordable := false
var unlocked := false
var maxed := false

var _panel: PanelContainer
var _name_label: Label
var _effect_label: Label
var _owned_label: Label
var _cost_label: Label
var _hit: Button


func _ready() -> void:
	custom_minimum_size = Vector2(0, ROW_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_panel.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 1)
	row.add_child(left)

	_name_label = UiTheme.make_label("", 19)
	left.add_child(_name_label)

	_effect_label = UiTheme.make_label("", 14, UiTheme.TEXT_DIM)
	_effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_effect_label)

	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.custom_minimum_size = Vector2(130, 0)
	right.add_theme_constant_override("separation", 1)
	row.add_child(right)

	_cost_label = UiTheme.make_label("", 19, UiTheme.GOLD)
	_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_cost_label)

	_owned_label = UiTheme.make_label("", 15, UiTheme.TEXT_DIM)
	_owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_owned_label)

	_hit = Button.new()
	_hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hit.flat = true
	_hit.focus_mode = Control.FOCUS_NONE
	_hit.pressed.connect(_on_pressed)
	add_child(_hit)


## Applies one entry from [code]SceneManager.upgrades()[/code].
func configure(data: Dictionary) -> void:
	if not is_node_ready():
		await ready

	upgrade_id = String(data.get("id", ""))
	unlocked = bool(data.get("unlocked", false))
	maxed = bool(data.get("maxed", false))
	affordable = bool(data.get("affordable", false))

	var owned := int(data.get("owned", 0))
	var cost := float(data.get("cost", -1.0))

	_name_label.text = String(data.get("name", ""))
	_effect_label.text = "%s · %s" % [
		String(data.get("effect", "")),
		String(data.get("description", "")),
	]

	var max_level := int(data.get("max_level", 0))
	if owned <= 0:
		_owned_label.text = "not owned"
	elif max_level > 0:
		_owned_label.text = "owned %d/%d" % [owned, max_level]
	else:
		_owned_label.text = "owned %d" % owned

	var border_color := UiTheme.LOCKED
	if not unlocked:
		_cost_label.text = "Tier %d" % int(data.get("unlock_tier", 1))
		_cost_label.modulate = Color(1, 1, 1, 0.45)
		_hit.disabled = true
		_panel.modulate = Color(0.55, 0.55, 0.58)
	elif maxed:
		_cost_label.text = "MAX"
		_cost_label.modulate = Color.WHITE
		_hit.disabled = true
		_panel.modulate = Color.WHITE
		border_color = UiTheme.GOOD
	else:
		_cost_label.text = "%s cal" % Num.fmt(cost)
		_cost_label.modulate = Color.WHITE if affordable else Color(1, 1, 1, 0.40)
		_hit.disabled = false
		_panel.modulate = Color.WHITE
		border_color = UiTheme.ACCENT if affordable else UiTheme.LOCKED

	_panel.add_theme_stylebox_override("panel",
		UiTheme.panel(UiTheme.BG_ROW, 8, 2, border_color))
	_hit.tooltip_text = "%s\n%s" % [
		String(data.get("name", "")),
		String(data.get("description", "")),
	]


func _on_pressed() -> void:
	if not unlocked or maxed:
		return
	purchase_requested.emit(upgrade_id)


## Small confirmation flourish fired by the shop after a successful buy.
func flash_bought() -> void:
	if not is_instance_valid(_panel):
		return
	var tween := create_tween()
	tween.tween_property(_panel, "self_modulate", Color(0.7, 1.6, 0.8), 0.06)
	tween.tween_property(_panel, "self_modulate", Color.WHITE, 0.20)
