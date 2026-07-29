# 06 — UI, Controls and containers

This is the lesson that costs people the most time in Godot. The UI system is
powerful and it is not obvious. Read it twice.

## `Control` is the UI base class

Anything that participates in UI layout extends `Control`: `Label`, `Button`,
`PanelContainer`, `TextureRect`, `ProgressBar`. A `Control` has a rectangle —
`position` and `size` — plus a pile of properties that decide how that rectangle
is computed.

The critical rule, and the source of most confusion:

> **A `Control`'s position and size are set by whatever contains it.**
> If its parent is a `Container`, you do not control them at all.

Two different systems are at play, and you need to know which one you are in.

## System 1: anchors and offsets (free-floating)

When a `Control`'s parent is **not** a container, the child positions itself
using anchors and offsets.

**Anchors** are four values from 0 to 1 describing a point in the parent's
rectangle. **Offsets** are pixel adjustments from those anchor points.

Anchors of `(0, 0, 1, 1)` mean "left edge at 0%, top at 0%, right at 100%, bottom
at 100%" — i.e. fill the parent. With all offsets at 0, the child exactly covers
the parent, and it stays covering it when the window resizes.

Rather than setting four anchors and four offsets by hand, use a preset:

```gdscript
_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
```

That is `arena.gd._build_ui()`. The background image fills the screen at any
window size.

There is a subtly different method:

- `set_anchors_preset(preset)` — sets anchors only, leaves offsets
- `set_anchors_and_offsets_preset(preset)` — sets both

Use the second unless you have a reason not to. `food_button.gd` uses the first:

```gdscript
_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
```

That works because a freshly constructed `Control` already has all offsets at
zero, so setting anchors alone gets the same result. It is relying on a default,
which is slightly fragile — `set_anchors_and_offsets_preset` would be more
explicit.

Useful presets: `PRESET_FULL_RECT`, `PRESET_CENTER`, `PRESET_TOP_LEFT`,
`PRESET_BOTTOM_WIDE`, `PRESET_CENTER_TOP`.

For centring something at its natural size:

```gdscript
box.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
```

The second argument tells it to size to the content's minimum rather than
stretching.

### Manual anchors

Sometimes presets do not fit. The toast layer wants to be centred horizontally,
pinned to the top, 350px wide:

```gdscript
_toasts.anchor_left = 0.5
_toasts.anchor_right = 0.5
_toasts.anchor_top = 0.0
_toasts.anchor_bottom = 0.0
_toasts.offset_left = -175.0
_toasts.offset_right = 175.0
_toasts.offset_top = 22.0
_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
_toasts.grow_vertical = Control.GROW_DIRECTION_END
```

Both horizontal anchors at `0.5` collapse to the centre line; the offsets of
±175 expand 175px each way. `grow_horizontal = GROW_DIRECTION_BOTH` says that
when the content is bigger than the box, grow in both directions so it stays
centred. `grow_vertical = GROW_DIRECTION_END` grows downward.

## System 2: containers (managed)

A `Container` computes its children's position and size for you. **Any position
or size you set on a container's child is overwritten on the next layout pass.**
This is the single most common Godot UI frustration.

The containers this project uses:

| Container | Behaviour |
|---|---|
| `VBoxContainer` | Stacks children vertically |
| `HBoxContainer` | Stacks children horizontally |
| `GridContainer` | Grid with a fixed `columns` count |
| `PanelContainer` | Draws a styled background behind a single child |
| `MarginContainer` | Adds padding around its children |
| `CenterContainer` | Centres a child at its minimum size |
| `ScrollContainer` | Clips and scrolls |
| `TabContainer` | One child per tab, named by the child's node name |

The kitchen's layout, from `arena.gd`:

```
Arena (Control)
├── TextureRect                    <- background, PRESET_FULL_RECT
├── ColorRect                      <- darkening scrim, PRESET_FULL_RECT
├── MarginContainer                <- 28px padding, PRESET_FULL_RECT
│   └── HBoxContainer              <- three columns
│       ├── VBoxContainer          <- left: character + HUD  (min width 380)
│       ├── VBoxContainer          <- centre: headline + food grid (expands)
│       └── VBoxContainer          <- right: tabs + buttons (min width 470)
└── ToastLayer (VBoxContainer)     <- manual anchors, floats on top
```

Draw order is child order: later children draw on top. That is why the scrim
comes after the background, and why `ToastLayer` is added last.

### Size flags

Size flags tell a container how to distribute leftover space.

```gdscript
column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
```

The centre column takes all the horizontal space the two fixed-width columns
leave. Values:

- `SIZE_FILL` — occupy the space assigned (default)
- `SIZE_EXPAND` — claim a share of the leftover space
- `SIZE_EXPAND_FILL` — both, which is what you almost always want
- `SIZE_SHRINK_CENTER` — take minimum size, centre in the space assigned

`SIZE_SHRINK_CENTER` is how the food icon stays centred in its card:

```gdscript
_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
```

When several children expand, space is split according to `size_flags_stretch_ratio`
(default 1.0 each, so evenly).

### `custom_minimum_size`

Containers ask children for their minimum size and never go below it.

```gdscript
column.custom_minimum_size = Vector2(380, 0)     # at least 380 wide
_cooldown_bar.custom_minimum_size = Vector2(0, 8) # at least 8 tall
```

A zero component means "no minimum on this axis" — use the natural one. This is
the correct way to size things inside a container. Setting `size` directly does
nothing; it will be overwritten.

## Theme overrides

Godot's styling has two levels. A `Theme` resource can be assigned to a node and
cascades to its children. Or you override a single property on a single node:

```gdscript
label.add_theme_font_size_override("font_size", size)
label.add_theme_color_override("font_color", color)
label.add_theme_constant_override("outline_size", maxi(2, size / 10))
panel.add_theme_stylebox_override("panel", UiTheme.panel(...))
container.add_theme_constant_override("separation", 14)
```

Four kinds: `color`, `constant`, `font_size`/`font`, and `stylebox`.

Property names are per-node-type and you must look them up. The class reference
page for each node has a **Theme Properties** section listing every override it
accepts. `VBoxContainer` has `separation`; `MarginContainer` has `margin_left`,
`margin_right`, `margin_top`, `margin_bottom`; `PanelContainer` has `panel`.
Guessing does not work — a wrong name fails silently.

This project centralises the styling in `ui_theme.gd` so the values live in one
place:

```gdscript
static func make_label(text: String, size: int, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	return style_label(label, size, color)
```

Every label in the game goes through it. Change `UiTheme.TEXT` and the whole game
restyles.

For a larger project, build an actual `Theme` resource and assign it once at the
root — overrides are per-node and get verbose. For this size, the helper is
simpler and more greppable.

## StyleBoxes

A `StyleBox` describes how a rectangle is painted. `StyleBoxFlat` is the
programmable one:

```gdscript
static func panel(bg: Color = BG_PANEL, radius: int = 10, border: int = 0,
		border_color: Color = ACCENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = radius
	# ... three more corners
	style.content_margin_left = 14
	# ... three more margins
	if border > 0:
		style.border_width_left = border
		# ... three more widths
		style.border_color = border_color
	return style
```

`content_margin_*` is padding *inside* the box — it pushes the child inward and
increases the container's minimum size. This is how the panels get their
breathing room without a nested `MarginContainer`.

Buttons need a stylebox per state:

```gdscript
button.add_theme_stylebox_override("normal", normal)
button.add_theme_stylebox_override("hover", hover)
button.add_theme_stylebox_override("pressed", pressed)
button.add_theme_stylebox_override("disabled", disabled)
```

Miss one and that state falls back to the default theme, which will look wrong.

## `mouse_filter` — the invisible click-blocker

Every `Control` has a `mouse_filter` deciding what it does with mouse events:

- `MOUSE_FILTER_STOP` (default) — consume the event
- `MOUSE_FILTER_PASS` — handle it, then let it through
- `MOUSE_FILTER_IGNORE` — invisible to the mouse

**The default is `STOP`.** A full-screen `ColorRect` sitting over your UI will
eat every click, and it looks like nothing is wrong. This is why the scrim,
background, labels and icons all set:

```gdscript
scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
```

It also explains a line in `evolution.gd`:

```gdscript
mouse_filter = Control.MOUSE_FILTER_IGNORE
```

The evolution scene wants clicks to reach `_unhandled_input()` so "click to
skip" works anywhere on screen. `_unhandled_input()` only receives events that
no `Control` consumed. Leave the root at `STOP` and the whole feature silently
does nothing.

**If a click is not registering, check `mouse_filter` first.** It is the answer
most of the time.

## The transparent-button trick

Both `FoodButton` and `UpgradeRow` want a rich visual layout that is entirely
clickable. Making a `Button` with children is awkward. The solution:

```gdscript
_hit = Button.new()
_hit.set_anchors_preset(Control.PRESET_FULL_RECT)
_hit.flat = true
_hit.focus_mode = Control.FOCUS_NONE
_hit.pressed.connect(_on_pressed)
add_child(_hit)          # added LAST, so it is on top
```

`flat = true` removes all its drawing. It is an invisible rectangle that reports
clicks, laid over a display-only panel. Every visual child is
`MOUSE_FILTER_IGNORE`, so nothing steals the event.

`focus_mode = FOCUS_NONE` stops it grabbing keyboard focus and drawing a focus
ring. For a clicker where you hammer the same button, that is what you want.

This is a genuinely common Godot pattern. Remember it.

## `modulate` vs `self_modulate`

Two tint properties that look identical and are not:

- **`modulate`** — tints the node **and all its children**
- **`self_modulate`** — tints **only this node's own drawing**

They multiply, so you can use both independently. `food_button.gd` does exactly
that, and the comment in the code explains why:

```gdscript
func _process(_delta: float) -> void:
	...
	_panel.modulate = Color(0.72, 0.72, 0.72) if remaining > 0.0 else Color.WHITE
```

```gdscript
func _nudge_rejected() -> void:
	...
	# `self_modulate` tints only the panel's own stylebox, so it does not fight
	# the per-frame `modulate` dimming applied in _process().
	tween.tween_property(_panel, "self_modulate", Color(1.6, 0.6, 0.6), 0.05)
	tween.tween_property(_panel, "self_modulate", Color.WHITE, 0.15)
```

The dimming runs every frame on `modulate`. If the rejection flash also animated
`modulate`, `_process()` would overwrite it on the very next frame and you would
never see the flash. Putting the flash on `self_modulate` lets both coexist.

Values above 1.0 brighten — `Color(1.6, 0.6, 0.6)` is a red over-brighten.

## Docs

- [GUI overview](https://docs.godotengine.org/en/stable/tutorials/ui/index.html)
- [Size and anchors](https://docs.godotengine.org/en/stable/tutorials/ui/size_and_anchors.html)
- [Using containers](https://docs.godotengine.org/en/stable/tutorials/ui/gui_containers.html)
- [Control class reference](https://docs.godotengine.org/en/stable/classes/class_control.html)
- [StyleBoxFlat](https://docs.godotengine.org/en/stable/classes/class_styleboxflat.html)

## Exercise

1. The food grid is hard-coded to 3 columns. Make it adapt: 2 columns below
   1200px of window width, 3 columns up to 1700px, 4 above. It must react to
   live window resizing.
2. You add a `ColorRect` on top of the kitchen to tint everything warm. Suddenly
   no food card responds to clicks. What happened and what are two ways to fix it?

## Solution

**1.** `arena.gd` already stores `_food_grid`. Connect to the resize signal in
`_build_center_column()`, after creating the grid:

```gdscript
_food_grid = GridContainer.new()
_food_grid.columns = FOOD_COLUMNS
_food_grid.add_theme_constant_override("h_separation", 16)
_food_grid.add_theme_constant_override("v_separation", 16)
centering.add_child(_food_grid)

resized.connect(_update_grid_columns)
```

```gdscript
func _update_grid_columns() -> void:
	if not is_instance_valid(_food_grid):
		return
	var width := size.x
	var columns := 3
	if width < 1200.0:
		columns = 2
	elif width > 1700.0:
		columns = 4
	if _food_grid.columns != columns:
		_food_grid.columns = columns
```

Also call `_update_grid_columns()` once at the end of `_build_ui()`, because
`resized` does not fire for the initial layout.

Two details worth noting. The `if _food_grid.columns != columns` check avoids
forcing a re-layout on every resize event — `resized` fires continuously while
dragging a window edge. And `FOOD_COLUMNS` is now only the default; you could
delete the constant, but leaving it as the starting value is harmless.

**2.** The `ColorRect` has the default `mouse_filter = MOUSE_FILTER_STOP`, and it
was added after the UI so it draws on top. It is consuming every mouse event
before the cards see them.

Fix one — make it invisible to the mouse, which is right when it is pure
decoration:

```gdscript
tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
```

Fix two — put it underneath instead of on top, which is right if you want it to
tint the background but not the UI. Either add it earlier in `_build_ui()`, or
reorder afterwards:

```gdscript
move_child(tint, 1)     # just above the background, below the MarginContainer
```

Fix one is what the existing scrim does. Note that `visible = false` would also
stop the clicks, but it also stops the drawing, so it is not a fix — and
`modulate.a = 0` is worse still, because an invisible-but-present `Control` with
`MOUSE_FILTER_STOP` still eats clicks. That combination produces a bug that is
genuinely hard to find.

---

Next: [07 — Resources, textures and drawing](07-resources-and-drawing.md)
