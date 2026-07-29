extends Control

## The kitchen: HUD, food cards, upgrade shop, achievements and toasts.
##
## The whole screen is built in code so the scene file stays a single node.
## That keeps the layout reviewable in one place and avoids the drift that
## comes from half the UI living in a .tscn and half of it in _ready().

const SHOP_REFRESH_INTERVAL := 0.15
const FOOD_COLUMNS := 3

var _food_cards: Dictionary = {}
var _upgrade_rows: Dictionary = {}
var _achievement_rows: Dictionary = {}

var _buy_count := 1
var _shop_accum := 0.0
var _last_tier := -1
var _last_click_mult := -1.0

var _background: TextureRect
var _character: TextureRect
var _weight_label: Label
var _pound_bar: ProgressBar
var _pound_caption: Label
var _tier_label: Label
var _tier_bar: ProgressBar
var _tier_caption: Label
var _bank_label: Label
var _cps_label: Label
var _click_label: Label
var _stats_label: Label
var _headline: Label
var _food_grid: GridContainer
var _upgrade_column: VBoxContainer
var _achievement_column: VBoxContainer
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
	# _refresh_hud() notices the tier is new and builds the food cards, sets the
	# headline and picks the artwork, so there is exactly one code path for it.
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

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	margin.add_child(columns)

	columns.add_child(_build_left_column())
	columns.add_child(_build_center_column())
	columns.add_child(_build_right_column())

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


func _build_left_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(380, 0)
	column.add_theme_constant_override("separation", 14)

	_character = TextureRect.new()
	_character.custom_minimum_size = Vector2(0, 360)
	_character.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_character.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_character.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_character.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_character)

	var hud := PanelContainer.new()
	hud.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.BG_DARK, 12))
	column.add_child(hud)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	hud.add_child(stack)

	_weight_label = UiTheme.make_label("--", 38, UiTheme.TEXT)
	stack.add_child(_weight_label)

	_pound_bar = ProgressBar.new()
	_pound_bar.custom_minimum_size = Vector2(0, 16)
	_pound_bar.max_value = 1.0
	UiTheme.style_progress(_pound_bar, UiTheme.ACCENT)
	stack.add_child(_pound_bar)

	_pound_caption = UiTheme.make_label("", 14, UiTheme.TEXT_DIM)
	stack.add_child(_pound_caption)

	stack.add_child(_separator())

	_tier_label = UiTheme.make_label("", 20, UiTheme.GOLD)
	stack.add_child(_tier_label)

	_tier_bar = ProgressBar.new()
	_tier_bar.custom_minimum_size = Vector2(0, 12)
	_tier_bar.max_value = 1.0
	UiTheme.style_progress(_tier_bar, UiTheme.GOLD)
	stack.add_child(_tier_bar)

	_tier_caption = UiTheme.make_label("", 14, UiTheme.TEXT_DIM)
	stack.add_child(_tier_caption)

	stack.add_child(_separator())

	_bank_label = UiTheme.make_label("", 26, UiTheme.GOLD)
	stack.add_child(_bank_label)

	_cps_label = UiTheme.make_label("", 18, UiTheme.GOOD)
	stack.add_child(_cps_label)

	_click_label = UiTheme.make_label("", 18, UiTheme.TEXT_DIM)
	stack.add_child(_click_label)

	_stats_label = UiTheme.make_label("", 14, UiTheme.TEXT_DIM)
	stack.add_child(_stats_label)

	return column


func _build_center_column() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)

	_headline = UiTheme.make_label("", 30, UiTheme.TEXT)
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
	_food_grid.columns = FOOD_COLUMNS
	_food_grid.add_theme_constant_override("h_separation", 16)
	_food_grid.add_theme_constant_override("v_separation", 16)
	centering.add_child(_food_grid)

	return column


func _build_right_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(470, 0)
	column.add_theme_constant_override("separation", 10)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.BG_DARK, 10))
	column.add_child(tabs)

	_upgrade_column = _scrolling_list(tabs, "Upgrades")
	_achievement_column = _scrolling_list(tabs, "Achievements")

	# Buy-quantity selector.
	var buy_row := HBoxContainer.new()
	buy_row.add_theme_constant_override("separation", 8)
	column.add_child(buy_row)

	var buy_label := UiTheme.make_label("Buy", 17, UiTheme.TEXT_DIM)
	buy_row.add_child(buy_label)

	for amount in [1, 10, -1]:
		var button := Button.new()
		button.text = "MAX" if amount == -1 else "x%d" % amount
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_meta("amount", amount)
		UiTheme.style_button(button, UiTheme.ACCENT_DIM)
		button.pressed.connect(_on_buy_amount_pressed.bind(amount))
		buy_row.add_child(button)
		_buy_buttons.append(button)

	# Footer actions.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.focus_mode = Control.FOCUS_NONE
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(save_button, UiTheme.ACCENT_DIM)
	save_button.pressed.connect(_on_save_pressed)
	actions.add_child(save_button)

	var menu_button := Button.new()
	menu_button.text = "Main Menu"
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(menu_button, UiTheme.ACCENT_DIM)
	menu_button.pressed.connect(_on_menu_pressed)
	actions.add_child(menu_button)

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


func _rebuild_upgrade_rows() -> void:
	for child in _upgrade_column.get_children():
		_upgrade_column.remove_child(child)
		child.queue_free()
	_upgrade_rows.clear()

	for entry in SceneManager.upgrades():
		var data: Dictionary = entry
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

	for entry in SceneManager.achievements():
		var data: Dictionary = entry
		var card := PanelContainer.new()
		_achievement_column.add_child(card)

		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 1)
		card.add_child(stack)

		var title := UiTheme.make_label(String(data.get("name", "")), 18)
		stack.add_child(title)

		var body := UiTheme.make_label(String(data.get("description", "")), 14,
			UiTheme.TEXT_DIM)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stack.add_child(body)

		_achievement_rows[String(data.get("id", ""))] = card
		_style_achievement(card, bool(data.get("unlocked", false)))


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
	var max_tier := int(snap.get("max_tier", 3))
	var per_pound := maxf(float(snap.get("calories_per_pound", 3500.0)), 1.0)
	var into_pound := float(snap.get("calories_into_pound", 0.0))
	var weight := float(snap.get("weight_lbs", 0.0))
	var next_tier_weight := float(snap.get("next_tier_weight", -1.0))

	_weight_label.text = Num.weight(weight)
	_pound_bar.value = clampf(into_pound / per_pound, 0.0, 1.0)
	_pound_caption.text = "%s / %s cal to the next pound" % [
		Num.fmt(into_pound), Num.fmt(per_pound)]

	_bank_label.text = "%s cal banked" % Num.fmt(float(snap.get("calorie_bank", 0.0)))
	_cps_label.text = "%s cal/sec idle" % Num.fmt(float(snap.get("cps", 0.0)))
	_click_label.text = "x%.2f per click" % float(snap.get("click_multiplier", 1.0))
	_stats_label.text = "%s clicks  ·  %s lifetime cal  ·  %d/%d achievements" % [
		Num.fmt(float(snap.get("total_clicks", 0))),
		Num.fmt(float(snap.get("lifetime_calories", 0.0))),
		int(snap.get("achievements_unlocked", 0)),
		int(snap.get("achievements_total", 0)),
	]

	_tier_label.text = "Tier %d of %d" % [tier, max_tier]
	if next_tier_weight > 0.0:
		var start := _tier_start_weight(tier)
		var span := maxf(next_tier_weight - start, 0.001)
		_tier_bar.value = clampf((weight - start) / span, 0.0, 1.0)
		_tier_caption.text = "%.1f lbs to go until the next evolution" % \
			maxf(next_tier_weight - weight, 0.0)
		_tier_bar.visible = true
	else:
		_tier_bar.value = 1.0
		_tier_bar.visible = false
		_tier_caption.text = "Final form reached."

	if tier != _last_tier:
		_last_tier = tier
		_character.texture = PlaceholderArt.character(tier)
		_background.texture = PlaceholderArt.backdrop(tier)
		_headline.text = _kitchen_name(tier)
		_rebuild_food_cards()

	var click_mult := float(snap.get("click_multiplier", 1.0))
	if not is_equal_approx(click_mult, _last_click_mult):
		_last_click_mult = click_mult
		_refresh_food_values()


## Weight at which the current tier began, used for the evolution progress bar.
func _tier_start_weight(tier: int) -> float:
	# Thresholds mirror the Rust `TIER_THRESHOLDS` table.
	match tier:
		2:
			return 175.0
		3:
			return 250.0
	return 150.0


func _kitchen_name(tier: int) -> String:
	match tier:
		2:
			return "The Supersize Era"
		3:
			return "State Fair Territory"
	return "Your Average Kitchen"


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
	UiTheme.style_button(back, UiTheme.ACCENT_DIM)
	back.pressed.connect(SceneManager.go_to_title)
	stack.add_child(back)
