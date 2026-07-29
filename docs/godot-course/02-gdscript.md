# 02 — GDScript

GDScript is Python-shaped but is not Python. Indentation defines blocks, but the
type system, the object model and the standard library are Godot's own.

This lesson is a tour of the features this codebase actually uses, in the order
you will meet them.

## A script is a class

Every `.gd` file defines one class. The first line declares what it extends:

```gdscript
extends Control
```

That is `amerobe/Scripts/arena.gd`. The file *is* the class; there is no
`class Arena:` line. When you attach this script to a node, the node gains
everything in the file.

To make the class referrable by name from other files, add `class_name`:

```gdscript
class_name FoodButton
extends Control
```

Now `FoodButton.new()` works anywhere in the project without an import, which is
how `arena.gd` builds its cards. Godot registers `class_name` scripts globally.

Six of your scripts use `class_name` (`FoodButton`, `UpgradeRow`, `ToastLayer`,
`Num`, `UiTheme`, `PlaceholderArt`) and four do not (`arena.gd`,
`title_screen.gd`, `evolution.gd`, `scene_manager.gd`). The rule of thumb: name
it if something else needs to construct or reference it; leave it anonymous if it
is attached to exactly one scene.

## Static typing

GDScript is optionally typed. This codebase types everything, and you should
too — it catches errors at parse time instead of three hours into a play session.

```gdscript
var _buy_count := 1                    # inferred as int
var _shop_accum := 0.0                 # inferred as float
var _food_cards: Dictionary = {}       # explicit
var _buy_buttons: Array[Button] = []   # typed array
var _toasts: ToastLayer                # explicit, starts null
```

`:=` means "infer the type from the value and lock it in". After
`var x := 1`, assigning `x = "hello"` is an error. This is different from Python,
where the same syntax does not exist at all.

Functions declare argument and return types:

```gdscript
func click_food(id: String) -> float:
```

`-> void` means returns nothing. Omitting the return type entirely makes it
`Variant`, which disables checking — avoid it.

### Variant

`Variant` is the any-type. Anything read out of a `Dictionary`, `Array` or JSON
is a `Variant` until you narrow it. This is why `arena.gd` is full of explicit
conversions:

```gdscript
var tier := int(snap.get("tier", 1))
var weight := float(snap.get("weight_lbs", 0.0))
_name_label.text = String(data.get("name", ""))
```

Those `int()`, `float()` and `String()` calls are not decoration. `snap` came
from `JSON.parse_string()`, so every value in it is a `Variant`. Converting at
the boundary means the rest of the function works with known types.

## Lifecycle callbacks

Godot calls these on your node automatically. The four that matter here:

| Callback | When | Used in this project for |
|---|---|---|
| `_ready()` | Once, when the node and all its children have entered the tree | Building UI, connecting signals |
| `_process(delta)` | Every rendered frame | Ticking the sim, refreshing the HUD |
| `_physics_process(delta)` | Fixed rate (60/s by default) | Not used here — no physics |
| `_notification(what)` | On engine events | Saving on window close |

`delta` is seconds since the last frame — a float around `0.016` at 60fps. Always
multiply time-based changes by it, or your game runs at different speeds on
different machines. The Rust side does exactly this:

```rust
let gained = self.cps() * delta;
```

`_ready()` runs **bottom-up**: children are ready before their parent. That
guarantee is why `arena.gd` can safely call `card.configure(data)` immediately
after `_food_grid.add_child(card)` — adding to the tree triggers the child's
`_ready()` synchronously, so its `_panel` and `_icon` fields already exist.

### `_notification`

Lower-level than the named callbacks. `scene_manager.gd` uses it to catch the
window closing:

```gdscript
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		save_game()
```

There is no `_on_quit()` callback, so this is how you get one. The full list of
notification constants is in the `Object` and `Node` class reference pages.

## Dictionaries and arrays

```gdscript
const SCENES := {
	"title": "res://Scenes/title_screen.tscn",
	"main": "res://Scenes/main.tscn",
	"evolution": "res://Scenes/evolution.tscn",
}
```

Access with `SCENES["title"]` or `SCENES.title`. **Both work, and the second one
is a trap.** The dot form is a runtime lookup that crashes if the key is absent,
and it looks like a field access, so typos read as valid code.

This is not hypothetical — it is the exact bug the original version of this file
shipped with:

```gdscript
# The original, broken:
const SCENES = {
	"title": "res://scenes/title_screen.tscn",   # key is "title"
	...
}
get_tree().change_scene_to_file(SCENES.title_screen)   # but this asks for "title_screen"
```

Three of the four transitions referenced keys that did not exist, so every scene
change past the title screen crashed. The current code uses the safe form:

```gdscript
var path: String = String(SCENES.get(key, ""))
if path.is_empty() or not ResourceLoader.exists(path):
	push_error("SceneManager: no scene registered for '%s' (%s)" % [key, path])
	return
```

`.get(key, default)` never crashes. Prefer it whenever the key might be missing.

## String formatting

`%` works like C's printf:

```gdscript
"%s / %s cal to the next pound" % [Num.fmt(into_pound), Num.fmt(per_pound)]
"Tier %d of %d" % [tier, max_tier]
"x%.2f per click" % float(snap.get("click_multiplier", 1.0))
```

A single argument can go bare (`"%ds" % secs`); multiple arguments need an array.
Mismatched counts are a runtime error, not a parse error, so count carefully.

## Lambdas and Callables

A `Callable` is a reference to a function, optionally bound to an object. You
make one just by naming a method without calling it:

```gdscript
_hit.pressed.connect(_on_pressed)
```

`_on_pressed` (no parentheses) is a `Callable`. With parentheses it would call
the function immediately and pass the *result*, which is a common typo.

`bind()` pre-supplies trailing arguments:

```gdscript
button.pressed.connect(_on_buy_amount_pressed.bind(amount))
```

The `pressed` signal carries no arguments, but the handler needs to know which
button was clicked. `bind(amount)` produces a `Callable` that, when invoked with
zero arguments, calls `_on_buy_amount_pressed(amount)`. This is how you avoid
writing three near-identical handlers.

Inline lambdas use `func`:

```gdscript
resized.connect(func() -> void: pivot_offset = size * 0.5)
```

Multi-line lambdas exist but are fiddly about where the closing paren goes.
`evolution.gd` originally used one and it was refactored into a named method
plus `bind()` for exactly that reason:

```gdscript
_tween.tween_callback(_on_whiteout_peak.bind(after))
```

Prefer named methods for anything longer than one line.

## `await`

`await` suspends the function until a signal fires. It turns the function into a
coroutine.

```gdscript
await get_tree().process_frame
```

That line in `scene_manager.gd._change_scene()` waits exactly one frame. It is
used to hold the `_changing_scene` guard until the scene swap has actually
happened, so a burst of events cannot trigger two transitions.

`food_button.gd` uses the other common form — waiting on a node to be ready:

```gdscript
func configure(data: Dictionary) -> void:
	if not is_node_ready():
		await ready
```

The guard matters. `await` on a signal that has *already* fired waits forever,
so you must check `is_node_ready()` first rather than awaiting unconditionally.

## Static functions and static variables

`Num` and `UiTheme` are pure utility classes — they are never instanced. All
their methods are `static`:

```gdscript
class_name Num
extends RefCounted

static func fmt(value: float) -> String:
```

Called as `Num.fmt(1234.0)`. No object needed.

`PlaceholderArt` goes one step further with a static variable:

```gdscript
static var _cache: Dictionary = {}
```

One dictionary shared across the whole program, which is what makes the texture
cache work — generating a 384×384 character sprite pixel by pixel in GDScript is
slow, so it happens once and every later request hits the cache.

## The gotchas worth memorising

**Integer division truncates.** `Num.duration()` relies on this:

```gdscript
var hours := total / 3600      # both ints -> int division
```

If `total` were a float you would get `2.7` hours instead of `2`. Be deliberate.

**`@onready` runs at `_ready` time, not at declaration.**

```gdscript
@onready var weight_label: Label = $UIBackground/VBoxContainer/WeightLabel
```

Without `@onready`, that `$` lookup runs during construction, before children
exist, and returns `null`. The prototype version of `arena.gd` used this pattern
heavily; the rewrite dropped it entirely because it builds its own nodes and
holds direct references.

**`$Path` is shorthand for `get_node("Path")`** and it crashes if the node is
missing. `get_node_or_null()` returns `null` instead. The prototype used
`get_node_or_null()` defensively in several places — a sign that the node paths
were not trustworthy, which is itself a design smell.

**`freed` objects are not `null`.** After `queue_free()`, a variable still holds
a reference to a dead object. Test with `is_instance_valid(x)`, which is why
`food_button.gd` guards its per-frame work:

```gdscript
if food_id.is_empty() or not unlocked or not is_instance_valid(_cooldown_bar):
	return
```

## Docs

- [GDScript basics](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html)
- [Static typing in GDScript](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html)
- [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)

## Exercise

1. `Num.fmt(0.0)` — what does it return, and why does it take the `int(n)` branch
   rather than the `%.1f` branch?
2. Write a static function `Num.percent(value: float, total: float) -> String`
   that returns `"42%"`, handling `total == 0` without dividing by zero.
3. In `arena.gd._update_buy_buttons()`, why is the amount stored with
   `set_meta()` instead of a plain array index?

## Solution

**1.** `"0"`. Walk it: `is_finite(0.0)` is true, `sign_text` is `""` because
`0.0 < 0.0` is false, `n = 0.0`. The `n < 1000.0` branch is taken. Inside it,
`n < 10.0` is true but `n != floorf(n)` is false — `0.0` equals its own floor —
so the decimal branch is skipped and it returns `"%d" % 0`, which is `"0"`. The
`floorf` check exists to show decimals only for genuinely fractional small
numbers like `2.5`.

**2.**

```gdscript
static func percent(value: float, total: float) -> String:
	if is_zero_approx(total):
		return "0%"
	return "%d%%" % int(round(value / total * 100.0))
```

Two things to note: `is_zero_approx()` rather than `total == 0.0`, because float
equality is unreliable; and `%%` to emit a literal percent sign, since `%` alone
starts a format specifier.

**3.** Because the handler and the refresh loop need to agree on which button
means what, without depending on position. `set_meta("amount", amount)` attaches
the value to the button object itself, so `_update_buy_buttons()` can read it
back with `button.get_meta("amount", 1)` and compare against `_buy_count`.

An array index would work here since the buttons are built in a known order, but
it couples two loops through a magic number: reorder the `for amount in [1, 10, -1]`
list and the highlight logic silently breaks. Metadata keeps the association on
the object, where it cannot drift.

---

Next: [03 — Nodes and scenes](03-nodes-and-scenes.md)
