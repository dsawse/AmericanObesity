class_name PremiumShop
extends Control

## Overlay listing the premium catalogue and driving a Lightning purchase.
##
## Never instantiated in an app-store build — arena.gd only creates it when
## [method LightningClient.is_available] returns true.

signal closed()

var _list: VBoxContainer
var _status_panel: PanelContainer
var _status_title: Label
var _status_body: Label
var _invoice_box: TextEdit
var _wallet_button: Button
var _copy_button: Button
var _cancel_button: Button

var _pending_item := ""
var _pending_bolt11 := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_refresh()

	var lightning := SceneManager.lightning
	if lightning != null:
		lightning.invoice_ready.connect(_on_invoice_ready)
		lightning.payment_settled.connect(_on_payment_settled)
		lightning.payment_failed.connect(_on_payment_failed)


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0, 0, 0, 0.72)
	add_child(scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(560, 0)
	frame.add_theme_stylebox_override("panel",
		UiTheme.panel(UiTheme.BG_DARK, 14, 3, UiTheme.GOLD))
	centre.add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	frame.add_child(column)

	var title := UiTheme.make_label("Support the Kitchen", 30, UiTheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var blurb := UiTheme.make_label(
		"Paid over Lightning. No account, no card, no data collected.",
		15, UiTheme.TEXT_DIM)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(blurb)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	# --- Payment status ----------------------------------------------------
	_status_panel = PanelContainer.new()
	_status_panel.visible = false
	_status_panel.add_theme_stylebox_override("panel",
		UiTheme.panel(UiTheme.BG_ROW, 10, 2, UiTheme.ACCENT))
	column.add_child(_status_panel)

	var status_column := VBoxContainer.new()
	status_column.add_theme_constant_override("separation", 6)
	_status_panel.add_child(status_column)

	_status_title = UiTheme.make_label("", 20, UiTheme.ACCENT)
	status_column.add_child(_status_title)

	_status_body = UiTheme.make_label("", 15, UiTheme.TEXT)
	_status_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_column.add_child(_status_body)

	# A TextEdit rather than a Label so the invoice can be selected by hand on
	# desktop, where a wallet may not be registered for the lightning: scheme.
	_invoice_box = TextEdit.new()
	_invoice_box.custom_minimum_size = Vector2(0, 74)
	_invoice_box.editable = false
	_invoice_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_invoice_box.add_theme_font_size_override("font_size", 12)
	status_column.add_child(_invoice_box)

	var pay_row := HBoxContainer.new()
	pay_row.add_theme_constant_override("separation", 8)
	status_column.add_child(pay_row)

	_wallet_button = _make_button(pay_row, "Open in wallet", UiTheme.ACCENT)
	_wallet_button.pressed.connect(_on_wallet_pressed)

	_copy_button = _make_button(pay_row, "Copy invoice", UiTheme.ACCENT_DIM)
	_copy_button.pressed.connect(_on_copy_pressed)

	_cancel_button = _make_button(pay_row, "Cancel", UiTheme.ACCENT_DIM)
	_cancel_button.pressed.connect(_on_cancel_pressed)

	# --- Footer ------------------------------------------------------------
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(0, 48)
	UiTheme.style_button(close, UiTheme.ACCENT_DIM)
	close.pressed.connect(_on_close_pressed)
	column.add_child(close)


func _make_button(parent: Node, text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 44)
	UiTheme.style_button(button, color)
	parent.add_child(button)
	return button


# ---------------------------------------------------------------------------
# Catalogue
# ---------------------------------------------------------------------------

func _refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	var configured := SceneManager.lightning != null \
		and SceneManager.lightning.is_configured()

	if not configured:
		var warning := UiTheme.make_label(
			"No Lightning backend is configured for this build. "
			+ "See docs/LIGHTNING.md to point it at your node.",
			15, Color(0.95, 0.7, 0.5))
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(warning)

	for entry in SceneManager.premium():
		var data: Dictionary = entry
		_list.add_child(_build_row(data, configured))


func _build_row(data: Dictionary, configured: bool) -> Control:
	var owned := bool(data.get("owned", false))
	var id := String(data.get("id", ""))
	var sats := int(data.get("sats", 0))

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UiTheme.panel(UiTheme.BG_ROW, 8, 2,
			UiTheme.GOOD if owned else UiTheme.LOCKED))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 1)
	row.add_child(text)

	text.add_child(UiTheme.make_label(String(data.get("name", "")), 18))
	var body := UiTheme.make_label(String(data.get("description", "")), 14,
		UiTheme.TEXT_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(body)

	if owned:
		var owned_label := UiTheme.make_label("OWNED", 16, UiTheme.GOOD)
		owned_label.custom_minimum_size = Vector2(120, 0)
		owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(owned_label)
	else:
		var buy := Button.new()
		buy.text = "%d sats" % sats
		buy.focus_mode = Control.FOCUS_NONE
		buy.custom_minimum_size = Vector2(120, 44)
		buy.disabled = not configured or not _pending_item.is_empty()
		UiTheme.style_button(buy, UiTheme.ACCENT)
		buy.pressed.connect(_on_buy_pressed.bind(id, sats,
			String(data.get("name", ""))))
		row.add_child(buy)

	return card


# ---------------------------------------------------------------------------
# Purchase flow
# ---------------------------------------------------------------------------

func _on_buy_pressed(id: String, sats: int, item_name: String) -> void:
	if SceneManager.lightning == null:
		return
	_pending_item = id
	_pending_bolt11 = ""
	_show_status("Requesting invoice...", "Contacting the payment server.", false)
	_refresh()
	SceneManager.lightning.request_invoice(id, sats,
		"American Obesity - %s" % item_name)


func _on_invoice_ready(item_id: String, bolt11: String, sats: int) -> void:
	if item_id != _pending_item:
		return
	_pending_bolt11 = bolt11
	_invoice_box.text = bolt11
	var amount := "%d sats" % sats if sats > 0 else "the amount shown"
	_show_status("Waiting for payment",
		"Pay %s with any Lightning wallet. The item unlocks automatically."
			% amount, true)


func _on_payment_settled(item_id: String) -> void:
	if item_id != _pending_item:
		return
	var granted := SceneManager.grant_entitlement(item_id)
	SceneManager.save_game()

	_pending_item = ""
	_pending_bolt11 = ""
	_show_status("Paid. Thank you.",
		"The item is yours." if granted else "You already owned that one.",
		false)
	_refresh()


func _on_payment_failed(item_id: String, reason: String) -> void:
	if item_id != _pending_item and not _pending_item.is_empty():
		return
	_pending_item = ""
	_pending_bolt11 = ""
	_show_status("Payment not completed", reason, false)
	_refresh()


func _show_status(title: String, body: String, show_invoice: bool) -> void:
	_status_panel.visible = true
	_status_title.text = title
	_status_body.text = body
	_invoice_box.visible = show_invoice
	_wallet_button.visible = show_invoice
	_copy_button.visible = show_invoice
	_cancel_button.visible = show_invoice


func _on_wallet_pressed() -> void:
	LightningClient.open_in_wallet(_pending_bolt11)


func _on_copy_pressed() -> void:
	LightningClient.copy_to_clipboard(_pending_bolt11)
	_status_body.text = "Invoice copied to the clipboard."


func _on_cancel_pressed() -> void:
	if SceneManager.lightning != null:
		SceneManager.lightning.cancel()
	_pending_item = ""
	_pending_bolt11 = ""
	_status_panel.visible = false
	_refresh()


func _on_close_pressed() -> void:
	_on_cancel_pressed()
	closed.emit()
	queue_free()
