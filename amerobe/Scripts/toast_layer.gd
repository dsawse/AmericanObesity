class_name ToastLayer
extends VBoxContainer

## Stack of transient notifications — achievements, new unlocks, idle earnings.

const MAX_VISIBLE := 5
const LIFETIME := 4.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 8)


func push(title: String, body: String, accent: Color = UiTheme.GOLD) -> void:
	while get_child_count() >= MAX_VISIBLE:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()

	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size = Vector2(340, 0)
	card.add_theme_stylebox_override("panel",
		UiTheme.panel(UiTheme.BG_DARK, 10, 3, accent))
	add_child(card)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)

	var title_label := UiTheme.make_label(title, 20, accent)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title_label)

	if not body.is_empty():
		var body_label := UiTheme.make_label(body, 15, UiTheme.TEXT)
		body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_label.custom_minimum_size = Vector2(310, 0)
		body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(body_label)

	card.modulate = Color(1, 1, 1, 0)
	# Bind the tween to the card, not to the layer: an evicted card takes its
	# tween down with it instead of leaving one animating a freed node.
	var tween := card.create_tween()
	tween.tween_property(card, "modulate:a", 1.0, 0.18)
	tween.tween_interval(LIFETIME)
	tween.tween_property(card, "modulate:a", 0.0, 0.45)
	tween.tween_callback(card.queue_free)
