extends Control

## The kitchen: HUD, food cards, upgrade shop, achievements and toasts.
##
## The screen is built in code, and the same panels are re-parented into a
## different container arrangement depending on whether we are on a wide
## display or a phone in portrait. Building the panels once and swapping only
## their layout means there is no duplicated widget code between the two modes.

const SHOP_REFRESH_INTERVAL := 0.15

enum Layout { UNSET, LANDSCAPE, PORTRAIT }

## Below this viewport width we treat the device as a phone regardless of
## orientation, because three columns stop being readable.
const NARROW_WIDTH := 900.0

var _food_cards: Dictionary = {}
var _upgrade_rows: Dictionary = {}
var _achievement_rows: Dictionary = {}

var _buy_count := 1
var _shop_accum := 0.0
var _last_tier := -1
var _last_click_mult := -1.0
var _layout_mode: Layout = Layout.UNSET

# Persistent panels. These survive layout changes; only their parents change.
var _hud: PanelContainer
var _character: TextureRect
var _food_panel: Control
var _tabs: TabContainer
var _footer: Control

# Containers rebuilt on every layout change.
var _margin: MarginContainer
var _layout_root: Control

var _background: TextureRect
var _weight_label: Label
var _class_label: Label
var _pound_bar: ProgressBar
var _pound_caption: Label
var _tier_label: Label
var _tier_bar: ProgressBar
var _tier_caption: Label
var _bank_label: Label
var _cps_label: Label
var _click_label: Label
var _headline: Label
var _food_grid: GridContainer
var _upgrade_column: VBoxContainer
var _achievement_column: VBoxContainer
var _stats_column: VBoxContainer
var _stats_lines: Array[Label] = []
var _buy_buttons: Array[Button] = []
var _toasts: ToastLayer


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_ui()

	if not SceneManager.engine_available:
		_show_engine_missing()
		return

	SceneManager.achievement_unlocked.connect(_on_achievement)
	SceneManager.food_unlocked.connect(_on_food_unlocked)
	SceneManager.offline_earnings.connect(_on_offline_earnings)
	SceneManager.tier_up.connect(_on_tier_up)

	_rebuild_upgrade_rows()
	_rebuild_achievement_rows()
	_refresh_hud()
	_refresh_shop()

	for event in SceneManager.consume_startup_events():
		_replay_startup_event(event)


func _process(delta: float) -> void:
	if not SceneManager.engine_available:
		return

	_refresh_hud()

	_shop_accum += delta
	if _shop_accum >= SHOP_REFRESH_INTERVAL:
		_shop_accum = 0.0
		_refresh_shop()


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_background = TextureRect.new()
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.texture = PlaceholderArt.backdrop(maxi(SceneManager.tier(), 1))
	add_child(_background)

	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.03, 0.02, 0.04, 0.45)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)

	# Build the panels once. _apply_layout() decides where they live.
	_hud = _build_hud()
	_character = _build_character()
	_food_panel = _build_food_panel()
	_tabs = _build_tabs()
	_footer = _build_footer()

	_toasts = ToastLayer.new()
	_toasts.anchor_left = 0.5
	_toasts.anchor_right = 0.5
	_toasts.anchor_top = 0.0
	_toasts.anchor_bottom = 0.0
	_toasts.offset_left = -175.0
	_toasts.offset_right = 175.0
	_toasts.offset_top = 22.0
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.grow_vertical = Control.GROW_DIRECTION_END
	add_child(_toasts)

	_apply_layout()
	resized.connect(_apply_layout)


## True when the current viewport should use the stacked phone layout.
func _is_portrait() -> bool:
	var vp := get_viewport_rect().size
	return vp.y > vp.x or vp.x < NARROW_WIDTH


func _apply_layout() -> void:
	var mode := Layout.PORTRAIT if _is_portrait() else Layout.LANDSCAPE
	if mode == _layout_mode and is_instance_valid(_layout_root):
		# Orientation is unchanged, but the grid still adapts to width.
		_update_grid_columns()
		return
	_layout_mode = mode

	# Detach the panels so the container swap below cannot free them.
	for piece: Control in [_hud, _character, _food_panel, _tabs, _footer]:
		if is_instance_valid(piece) and piece.get_parent() != null:
			piece.get_parent().remove_child(piece)

	if is_instance_valid(_layout_root):
		_margin.remove_child(_layout_root)
		_layout_root.queue_free()

	var pad := 12 if mode == Layout.PORTRAIT else 28
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_margin.add_theme_constant_override(side, pad)

	_layout_root = _build_portrait() if mode == Layout.PORTRAIT else _build_landscape()
	_margin.add_child(_layout_root)

	_update_grid_columns()
	_resize_food_cards()


func _build_landscape() -> Control:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	left.add_theme_constant_override("separation", 14)
	_character.custom_minimum_size = Vector2(0, 360)
	_character.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_character)
	left.add_child(_hud)
	columns.add_child(left)

	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 14)
	centre.add_child(_food_panel)
	columns.add_child(centre)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(470, 0)
	right.add_theme_constant_override("separation", 10)
	right.add_child(_tabs)
	right.add_child(_footer)
	columns.add_child(right)

	return columns


func _build_portrait() -> Control:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)

	# A short character strip keeps the progression visible without eating the
	# screen; the HUD sits directly under it.
	_character.custom_minimum_size = Vector2(0, 150)
	_character.size_flags_vertical = Control.SIZE_FILL
	stack.add_child(_character)
	stack.add_child(_hud)

	# Food on top, the Shop / Achievements / Stats tabs below. Splitting the
	# remaining height rather than nesting tab bars keeps both reachable
	# without a second level of navigation.
	_food_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_food_panel.size_flags_stretch_ratio = 1.15
	stack.add_child(_food_panel)

	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_stretch_ratio = 1.0
	stack.add_child(_tabs)

	stack.add_child(_footer)
	return stack


func _build_hud() -> PanelContainer:
	var hud := PanelContainer.new()
	hud.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.BG_DARK, 12))

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	hud.add_child(stack)

	_weight_label = UiTheme.make_label("--", 36, UiTheme.TEXT)
	stack.add_child(_weight_label)

	_class_label = UiTheme.make_label("", 17, UiTheme.GOLD)
	stack.add_child(_class_label)

	_pound_bar = ProgressBar.new()
	_pound_bar.custom_minimum_size = Vector2(0, 16)
	_pound_bar.max_value = 1.0
	UiTheme.style_progress(_pound_bar, UiTheme.ACCENT)
	stack.add_child(_pound_bar)

	_pound_caption = UiTheme.make_label("", 14, UiTheme.TEXT_DIM)
	stack.add_child(_pound_caption)

	stack.add_child(_separator())

	_tier_label = UiTheme.make_label("", 19, UiTheme.GOLD)
	stack.add_child(_tier_label)

	_tier_bar = ProgressBar.new()
	_tier_bar.custom_minimum_size = Vector2(0, 12)
	_tier_bar.max_value = 1.0
	UiTheme.style_progress(_tier_bar, UiTheme.GOLD)
	stack.add_child(_tier_bar)

	_tier_caption = UiTheme.make_label("", 14, UiTheme.TEXT_DIM)
	stack.add_child(_tier_caption)

	stack.add_child(_separator())

	_bank_label = UiTheme.make_label("", 25, UiTheme.GOLD)
	stack.add_child(_bank_label)

	_cps_label = UiTheme.make_label("", 17, UiTheme.GOOD)
	stack.add_child(_cps_label)

	_click_label = UiTheme.make_label("", 17, UiTheme.TEXT_DIM)
	stack.add_child(_click_label)

	return hud


func _build_character() -> TextureRect:
	var character := TextureRect.new()
	character.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	character.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	character.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return character


func _build_food_panel() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)

	_headline = UiTheme.make_label("", 28, UiTheme.TEXT)
	_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_headline)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var centering := CenterContainer.new()
	centering.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(centering)

	_food_grid = GridContainer.new()
	_food_grid.columns = 3
	_food_grid.add_theme_constant_override("h_separation", 14)
	_food_grid.add_theme_constant_override("v_separation", 14)
	centering.add_child(_food_grid)

	return column


func _build_tabs() -> TabContainer:
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.BG_DARK, 10))

	_upgrade_column = _scrolling_list(tabs, "Shop")
	_achievement_column = _scrolling_list(tabs, "Achievements")
	_stats_column = _scrolling_list(tabs, "Stats")

	for i in 8:
		var line := UiTheme.make_label("", 17)
		_stats_column.add_child(line)
		_stats_lines.append(line)

	return tabs


func _build_footer() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)

	var buy_row := HBoxContainer.new()
	buy_row.add_theme_constant_override("separation", 8)
	column.add_child(buy_row)

	buy_row.add_child(UiTheme.make_label("Buy", 17, UiTheme.TEXT_DIM))

	for amount in [1, 10, -1]:
		var button := Button.new()
		button.text = "MAX" if amount == -1 else "x%d" % amount
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 48)
		button.set_meta("amount", amount)
		UiTheme.style_button(button, UiTheme.ACCENT_DIM)
		button.pressed.connect(_on_buy_amount_pressed.bind(amount))
		buy_row.add_child(button)
		_buy_buttons.append(button)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.focus_mode = Control.FOCUS_NONE
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.custom_minimum_size = Vector2(0, 48)
	UiTheme.style_button(save_button, UiTheme.ACCENT_DIM)
	save_button.pressed.connect(_on_save_pressed)
	actions.add_child(save_button)

	var menu_button := Button.new()
	menu_button.text = "Menu"
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_button.custom_minimum_size = Vector2(0, 48)
	UiTheme.style_button(menu_button, UiTheme.ACCENT_DIM)
	menu_button.pressed.connect(_on_menu_pressed)
	actions.add_child(menu_button)

	# Only present where Lightning payments are permitted. In an app-store
	# build LightningClient.is_available() is false and this button, the shop
	# overlay and the networking code are all absent.
	if LightningClient.is_available():
		var support_button := Button.new()
		support_button.text = "Support"
		support_button.focus_mode = Control.FOCUS_NONE
		support_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		support_button.custom_minimum_size = Vector2(0, 48)
		UiTheme.style_button(support_button, UiTheme.GOLD.darkened(0.35))
		support_button.pressed.connect(_on_support_pressed)
		actions.add_child(support_button)

	_update_buy_buttons()
	return column


func _scrolling_list(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	return list


func _separator() -> Control:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.10)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _section_header(text: String) -> Control:
	var label := UiTheme.make_label(text.to_upper(), 15, UiTheme.ACCENT)
	label.add_theme_constant_override("outline_size", 0)
	return label


# ---------------------------------------------------------------------------
# Responsive sizing
# ---------------------------------------------------------------------------

func _update_grid_columns() -> void:
	if not is_instance_valid(_food_grid):
		return
	var width := get_viewport_rect().size.x
	var columns := 3
	if _layout_mode == Layout.PORTRAIT:
		columns = 2 if width >= 560.0 else 1
	elif width > 1700.0:
		columns = 4
	elif width < 1200.0:
		columns = 2
	if _food_grid.columns != columns:
		_food_grid.columns = columns


## Phones need bigger targets and fewer of them; desktops can afford detail.
func _card_size() -> Vector2:
	if _layout_mode == Layout.PORTRAIT:
		var width := get_viewport_rect().size.x
		var columns := maxi(_food_grid.columns if is_instance_valid(_food_grid) else 2, 1)
		var each := clampf((width - 60.0) / float(columns), 150.0, 320.0)
		return Vector2(each, each * 1.05)
	return FoodButton.CARD_SIZE


func _resize_food_cards() -> void:
	var target := _card_size()
	for id: String in _food_cards.keys():
		var card: FoodButton = _food_cards[id]
		if is_instance_valid(card):
			card.custom_minimum_size = target


# ---------------------------------------------------------------------------
# Population
# ---------------------------------------------------------------------------

func _rebuild_food_cards() -> void:
	for child in _food_grid.get_children():
		_food_grid.remove_child(child)
		child.queue_free()
	_food_cards.clear()

	for entry in SceneManager.foods():
		var data: Dictionary = entry
		var card := FoodButton.new()
		_food_grid.add_child(card)
		card.eaten.connect(_on_food_eaten)
		card.configure(data)
		_food_cards[String(data.get("id", ""))] = card

	_resize_food_cards()


func _rebuild_upgrade_rows() -> void:
	for child in _upgrade_column.get_children():
		_upgrade_column.remove_child(child)
		child.queue_free()
	_upgrade_rows.clear()

	var entries := SceneManager.upgrades()
	entries.sort_custom(_compare_by_category)

	var current_category := ""
	for entry in entries:
		var data: Dictionary = entry
		var category := String(data.get("category", ""))
		if category != current_category:
			current_category = category
			_upgrade_column.add_child(_section_header(category))

		var row := UpgradeRow.new()
		_upgrade_column.add_child(row)
		row.purchase_requested.connect(_on_purchase_requested)
		row.configure(data)
		_upgrade_rows[String(data.get("id", ""))] = row


func _rebuild_achievement_rows() -> void:
	for child in _achievement_column.get_children():
		_achievement_column.remove_child(child)
		child.queue_free()
	_achievement_rows.clear()

	var entries := SceneManager.achievements()
	entries.sort_custom(_compare_by_category)

	var current_category := ""
	for entry in entries:
		var data: Dictionary = entry
		var category := String(data.get("category", ""))
		if category != current_category:
			current_category = category
			_achievement_column.add_child(_section_header(category))

		var card := PanelContainer.new()
		_achievement_column.add_child(card)

		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 1)
		card.add_child(stack)

		stack.add_child(UiTheme.make_label(String(data.get("name", "")), 18))

		var body := UiTheme.make_label(String(data.get("description", "")), 14,
			UiTheme.TEXT_DIM)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stack.add_child(body)

		_achievement_rows[String(data.get("id", ""))] = card
		_style_achievement(card, bool(data.get("unlocked", false)))


## Sorts by the Rust-supplied category order, then keeps the declaration order
## within a category (which is already cheapest-first).
func _compare_by_category(a: Variant, b: Variant) -> bool:
	var da: Dictionary = a
	var db: Dictionary = b
	return int(da.get("category_order", 0)) < int(db.get("category_order", 0))


func _style_achievement(card: PanelContainer, unlocked: bool) -> void:
	if unlocked:
		card.add_theme_stylebox_override("panel",
			UiTheme.panel(UiTheme.BG_ROW, 8, 2, UiTheme.GOLD))
		card.modulate = Color.WHITE
	else:
		card.add_theme_stylebox_override("panel",
			UiTheme.panel(UiTheme.BG_ROW, 8, 2, UiTheme.LOCKED))
		card.modulate = Color(0.62, 0.62, 0.64)


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func _refresh_hud() -> void:
	var snap := SceneManager.snapshot()
	if snap.is_empty():
		return

	var tier := int(snap.get("tier", 1))
	var max_tier := int(snap.get("max_tier", 5))
	var per_pound := maxf(float(snap.get("calories_per_pound", 3500.0)), 1.0)
	var into_pound := float(snap.get("calories_into_pound", 0.0))
	var weight := float(snap.get("weight_lbs", 0.0))
	var next_tier_weight := float(snap.get("next_tier_weight", -1.0))

	_weight_label.text = Num.weight(weight)
	_class_label.text = "%s  ·  %s form" % [
		String(snap.get("weight_class", "")),
		String(snap.get("character_state", "")),
	]
	_pound_bar.value = clampf(into_pound / per_pound, 0.0, 1.0)
	_pound_caption.text = "%s / %s cal to the next pound" % [
		Num.fmt(into_pound), Num.fmt(per_pound)]

	_bank_label.text = "%s cal banked" % Num.fmt(float(snap.get("calorie_bank", 0.0)))
	_cps_label.text = "%s/sec  ·  %s/hr" % [
		Num.fmt(float(snap.get("cps", 0.0))),
		Num.fmt(float(snap.get("cph", 0.0))),
	]
	_click_label.text = "x%s per click" % Num.fmt(float(snap.get("click_multiplier", 1.0)))

	_tier_label.text = "Tier %d of %d" % [tier, max_tier]
	if next_tier_weight > 0.0:
		var start := float(snap.get("tier_start_weight", 150.0))
		var span := maxf(next_tier_weight - start, 0.001)
		_tier_bar.value = clampf((weight - start) / span, 0.0, 1.0)
		_tier_caption.text = "%s lbs to the next evolution" % \
			Num.fmt(maxf(next_tier_weight - weight, 0.0))
		_tier_bar.visible = true
	else:
		_tier_bar.value = 1.0
		_tier_bar.visible = false
		_tier_caption.text = "Final form reached."

	_refresh_stats(snap)

	if tier != _last_tier:
		_last_tier = tier
		_character.texture = PlaceholderArt.character(tier)
		_background.texture = PlaceholderArt.backdrop(tier)
		_headline.text = String(snap.get("tier_name", "Kitchen"))
		_rebuild_food_cards()
		_rebuild_upgrade_rows()

	var click_mult := float(snap.get("click_multiplier", 1.0))
	if not is_equal_approx(click_mult, _last_click_mult):
		_last_click_mult = click_mult
		_refresh_food_values()


func _refresh_stats(snap: Dictionary) -> void:
	if _stats_lines.size() < 8:
		return
	_stats_lines[0].text = "Weight: %s" % Num.weight(float(snap.get("weight_lbs", 0.0)))
	_stats_lines[1].text = "Weight class: %s" % String(snap.get("weight_class", ""))
	_stats_lines[2].text = "Lifetime calories: %s" % Num.fmt(float(snap.get("lifetime_calories", 0.0)))
	_stats_lines[3].text = "Total clicks: %s" % Num.fmt(float(snap.get("total_clicks", 0)))
	_stats_lines[4].text = "Per click: x%s" % Num.fmt(float(snap.get("click_multiplier", 1.0)))
	_stats_lines[5].text = "Per minute: %s cal" % Num.fmt(float(snap.get("cpm", 0.0)))
	_stats_lines[6].text = "Automation owned: %d levels" % int(snap.get("automation_levels", 0))
	_stats_lines[7].text = "Achievements: %d / %d" % [
		int(snap.get("achievements_unlocked", 0)),
		int(snap.get("achievements_total", 0)),
	]


func _refresh_food_values() -> void:
	for entry in SceneManager.foods():
		var data: Dictionary = entry
		var id := String(data.get("id", ""))
		if _food_cards.has(id):
			var card: FoodButton = _food_cards[id]
			card.refresh_value(float(data.get("calories", 0.0)))


func _refresh_shop() -> void:
	for entry in SceneManager.upgrades():
		var data: Dictionary = entry
		var id := String(data.get("id", ""))
		if _upgrade_rows.has(id):
			var row: UpgradeRow = _upgrade_rows[id]
			row.configure(data)


func _refresh_achievements() -> void:
	for entry in SceneManager.achievements():
		var data: Dictionary = entry
		var id := String(data.get("id", ""))
		if _achievement_rows.has(id):
			_style_achievement(_achievement_rows[id], bool(data.get("unlocked", false)))


func _update_buy_buttons() -> void:
	for button in _buy_buttons:
		var amount := int(button.get_meta("amount", 1))
		button.modulate = Color.WHITE if amount == _buy_count \
			else Color(0.75, 0.75, 0.78)


# ---------------------------------------------------------------------------
# Input handlers
# ---------------------------------------------------------------------------

func _on_food_eaten(_id: String, _calories: float) -> void:
	_refresh_shop()


func _on_purchase_requested(id: String) -> void:
	var bought := 0
	if _buy_count == 1:
		bought = 1 if SceneManager.buy_upgrade(id) else 0
	elif _buy_count == -1:
		bought = SceneManager.buy_upgrade_bulk(id, 1000)
	else:
		bought = SceneManager.buy_upgrade_bulk(id, _buy_count)

	if bought > 0 and _upgrade_rows.has(id):
		var row: UpgradeRow = _upgrade_rows[id]
		row.flash_bought()
	_refresh_shop()
	_refresh_hud()


func _on_buy_amount_pressed(amount: int) -> void:
	_buy_count = amount
	_update_buy_buttons()


func _on_save_pressed() -> void:
	if SceneManager.save_game():
		_toasts.push("Saved", "Progress written to disk.", UiTheme.GOOD)
	else:
		_toasts.push("Save failed", "Check the output log for details.",
			Color(0.9, 0.4, 0.4))


func _on_menu_pressed() -> void:
	SceneManager.save_game()
	SceneManager.go_to_title()


func _on_support_pressed() -> void:
	if not LightningClient.is_available():
		return
	var shop := PremiumShop.new()
	# Added to the scene root so it covers the toast layer too.
	add_child(shop)
	shop.closed.connect(_on_premium_closed)


func _on_premium_closed() -> void:
	# Entitlements change the click and idle multipliers, so force the HUD and
	# the food cards to re-read them rather than waiting for a drift check.
	_last_click_mult = -1.0
	_refresh_hud()


# ---------------------------------------------------------------------------
# SceneManager signals
# ---------------------------------------------------------------------------

func _on_achievement(_id: String, title: String, description: String) -> void:
	_toasts.push("Achievement: %s" % title, description, UiTheme.GOLD)
	_refresh_achievements()


func _on_food_unlocked(_id: String, food_name: String) -> void:
	_toasts.push("New on the menu", "%s is now available." % food_name,
		UiTheme.ACCENT)
	_rebuild_food_cards()


func _on_offline_earnings(seconds: float, calories: float) -> void:
	_toasts.push("While you were out",
		"%s of snacking earned %s calories." % [
			Num.duration(seconds), Num.fmt(calories)],
		UiTheme.GOOD)


func _on_tier_up(tier: int) -> void:
	_toasts.push("Evolving", "Reaching tier %d..." % tier, UiTheme.GOLD)


func _replay_startup_event(event: Dictionary) -> void:
	match String(event.get("kind", "")):
		"achievement":
			_on_achievement(String(event.get("id", "")),
				String(event.get("name", "")),
				String(event.get("description", "")))
		"food_unlocked":
			_on_food_unlocked(String(event.get("id", "")),
				String(event.get("name", "")))
		"offline_earnings":
			_on_offline_earnings(float(event.get("seconds", 0.0)),
				float(event.get("calories", 0.0)))
		"tier_up":
			SceneManager.pending_tier = int(event.get("tier", 1))
			SceneManager.go_to_evolution()


# ---------------------------------------------------------------------------
# Degraded mode
# ---------------------------------------------------------------------------

func _show_engine_missing() -> void:
	var box := PanelContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	box.add_theme_stylebox_override("panel",
		UiTheme.panel(UiTheme.BG_DARK, 12, 3, Color(0.9, 0.4, 0.4)))
	add_child(box)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	box.add_child(stack)

	stack.add_child(UiTheme.make_label("Simulation engine not loaded", 30,
		Color(0.95, 0.6, 0.6)))
	var hint := UiTheme.make_label(SceneManager.engine_error, 17, UiTheme.TEXT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(620, 0)
	stack.add_child(hint)

	var back := Button.new()
	back.text = "Back to title"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(0, 48)
	UiTheme.style_button(back, UiTheme.ACCENT_DIM)
	back.pressed.connect(SceneManager.go_to_title)
	stack.add_child(back)
