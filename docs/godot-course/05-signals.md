# 05 — Signals

Signals are Godot's observer pattern. A node announces that something happened;
zero or more listeners react. The emitter does not know or care who is listening.

This matters because it lets you point dependencies **upward**. A `FoodButton`
must not know what an `Arena` is — that would make it unusable anywhere else.
Instead it shouts "someone ate me" and lets whoever cares deal with it.

## Declaring and emitting

```gdscript
signal eaten(id: String, calories: float)
```

That is `food_button.gd`, line 9. Typed parameters are optional but you should
always include them — they document the contract and are checked.

Emitting:

```gdscript
eaten.emit(food_id, gained)
```

In Godot 4 a signal is a first-class object with an `emit()` method. (Godot 3
used `emit_signal("eaten", ...)`, which still works but is stringly-typed and
worse. If you find a tutorial using it, it is out of date.)

## Connecting

```gdscript
card.eaten.connect(_on_food_eaten)
```

`arena.gd`, in `_rebuild_food_cards()`. The handler signature must accept the
signal's arguments:

```gdscript
func _on_food_eaten(_id: String, _calories: float) -> void:
	_refresh_shop()
```

The leading underscores on `_id` and `_calories` are a convention meaning
"deliberately unused" — it silences the unused-argument warning. This handler
only needs to know that *something* was eaten so it can refresh affordability in
the shop.

## The three levels of signal use in this project

### 1. Built-in signals from built-in nodes

Every Godot node ships with signals. You are consuming several:

```gdscript
_hit.pressed.connect(_on_pressed)                              # Button
resized.connect(func() -> void: pivot_offset = size * 0.5)     # Control
_confirm.confirmed.connect(_start_fresh_run)                   # ConfirmationDialog
```

Look up any node in the [class reference](https://docs.godotengine.org/en/stable/classes/index.html)
and scroll to its **Signals** section to see what it offers.

The `resized` one is a nice small example of reacting to the engine rather than
polling it. A `Control`'s `size` is set by its container during layout, which can
happen at any time. Rather than checking the size every frame to keep
`pivot_offset` centred, the card is told when it changes.

### 2. Custom signals on your own nodes

`FoodButton.eaten` and `UpgradeRow.purchase_requested` exist so that the cards
and rows stay ignorant of the screen containing them.

```gdscript
# upgrade_row.gd
signal purchase_requested(id: String)

func _on_pressed() -> void:
	if not unlocked or maxed:
		return
	purchase_requested.emit(upgrade_id)
```

Notice the row does **not** buy anything. It cannot — it has no access to the
game state and no idea what the current buy quantity is. It reports intent.
`arena.gd` decides what that means:

```gdscript
func _on_purchase_requested(id: String) -> void:
	var bought := 0
	if _buy_count == 1:
		bought = 1 if SceneManager.buy_upgrade(id) else 0
	elif _buy_count == -1:
		bought = SceneManager.buy_upgrade_bulk(id, 1000)
	else:
		bought = SceneManager.buy_upgrade_bulk(id, _buy_count)
	...
```

This separation is why the ×1 / ×10 / MAX selector took no changes to
`UpgradeRow` at all. The row's job never changed.

### 3. Signals as a translation layer

The most interesting use. The Rust engine has no concept of Godot signals — it
returns a JSON array of events. `SceneManager` converts that into idiomatic
Godot:

```gdscript
signal tier_up(tier: int)
signal achievement_unlocked(id: String, title: String, description: String)
signal food_unlocked(id: String, food_name: String)
signal offline_earnings(seconds: float, calories: float)
```

```gdscript
func _dispatch(event: Dictionary) -> void:
	match String(event.get("kind", "")):
		"tier_up":
			pending_tier = int(event.get("tier", tier()))
			tier_up.emit(pending_tier)
			go_to_evolution()
		"achievement":
			achievement_unlocked.emit(
				String(event.get("id", "")),
				String(event.get("name", "")),
				String(event.get("description", "")))
		...
```

The UI never parses JSON. It connects to typed signals like any other Godot code:

```gdscript
SceneManager.achievement_unlocked.connect(_on_achievement)
SceneManager.food_unlocked.connect(_on_food_unlocked)
SceneManager.offline_earnings.connect(_on_offline_earnings)
SceneManager.tier_up.connect(_on_tier_up)
```

This is an **anti-corruption layer**: a boundary that translates a foreign
system's vocabulary into your own. The Rust side is free to change its event
format; only `_dispatch()` needs updating.

## Connecting in the editor vs. in code

The original `title_screen.tscn` had this line:

```
[connection signal="pressed" from="Button" to="." method="_on_button_pressed"]
```

That is an editor connection — made by clicking the Node dock, choosing a signal,
and picking a method. Godot writes it into the scene file.

**The problem:** nothing verifies that `_on_button_pressed` exists. Rename the
method and the connection silently points at nothing. The button does nothing and
there is no error until you notice the game is broken.

**Code connections fail loudly.** `_hit.pressed.connect(_on_pressed)` is a parse
error if `_on_pressed` does not exist.

Editor connections are convenient for prototyping and fine when a designer needs
to rewire without touching code. For anything you intend to maintain, connect in
code.

## `bind()` — passing extra context

The `pressed` signal has no arguments, but you often need to know *which* thing
was pressed:

```gdscript
for amount in [1, 10, -1]:
	var button := Button.new()
	...
	button.pressed.connect(_on_buy_amount_pressed.bind(amount))
```

`bind()` appends arguments. The handler receives them after any the signal
supplies:

```gdscript
func _on_buy_amount_pressed(amount: int) -> void:
	_buy_count = amount
	_update_buy_buttons()
```

One handler, three buttons. Without `bind()` you would write three identical
methods or capture in a lambda.

Order matters: signal arguments come first, bound arguments last. If `pressed`
carried an argument, the handler would be `func _on(sig_arg, amount)`.

## Lifetime

Connections hold a reference. If the listener is freed, the connection is
automatically dropped — Godot handles this correctly, so you rarely need
`disconnect()`.

Where you *do* need care is connecting the same signal twice. Calling
`connect()` again on an already-connected pair raises an error. If you might
reconnect, check first:

```gdscript
if not some_signal.is_connected(handler):
	some_signal.connect(handler)
```

This project avoids the situation entirely: connections are made once in
`_ready()` and the node is freed wholesale on scene change.

There is one flag worth knowing:

```gdscript
some_signal.connect(handler, CONNECT_ONE_SHOT)
```

Disconnects automatically after the first emission. Useful for "when this
finishes, do X once".

## Signals vs. direct calls

Not everything should be a signal. Compare:

```gdscript
# food_button.gd — a direct call
var gained := SceneManager.click_food(food_id)
if gained <= 0.0:
	_nudge_rejected()
	return
eaten.emit(food_id, gained)
```

The card calls `SceneManager` **directly** because it needs an answer right now —
did the click land, and for how many calories? A signal is fire-and-forget; it
cannot return a value.

Then it emits `eaten` because notifying the screen is fire-and-forget.

The rule: **direct call when you need a result or the dependency is legitimately
downward. Signal when you are notifying and do not care who listens.**

## Docs

- [Signals tutorial](https://docs.godotengine.org/en/stable/getting_started/step_by_step/signals.html)
- [Using signals](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#signals)
- [Object.connect flags](https://docs.godotengine.org/en/stable/classes/class_object.html#enum-object-connectflags)

## Exercise

1. Add a `first_purchase` signal that fires the very first time the player buys
   any upgrade in a session, and show a toast when it does. It must fire once,
   not once per upgrade type.
2. `arena.gd._on_tier_up()` pushes a toast saying "Evolving…", but you never see
   it. Why? Where would you put that message instead?

## Solution

**1.** In `scene_manager.gd`, add the signal and a latch:

```gdscript
signal first_purchase(id: String)

var _has_purchased := false
```

Then in `buy_upgrade()`:

```gdscript
func buy_upgrade(id: String) -> bool:
	if not engine_available:
		return false
	var ok: bool = game.buy_upgrade(id)
	if ok and not _has_purchased:
		_has_purchased = true
		first_purchase.emit(id)
	return ok
```

Note this must also be handled in `buy_upgrade_bulk()`, or buying with ×10
selected skips the signal. Cleanest is to route both through one place:

```gdscript
func buy_upgrade_bulk(id: String, count: int) -> int:
	if not engine_available:
		return 0
	var bought: int = game.buy_upgrade_bulk(id, count)
	if bought > 0 and not _has_purchased:
		_has_purchased = true
		first_purchase.emit(id)
	return bought
```

In `arena.gd._ready()`:

```gdscript
SceneManager.first_purchase.connect(_on_first_purchase)
```

```gdscript
func _on_first_purchase(_id: String) -> void:
	_toasts.push("Hired help", "Your empire runs itself now. A little.",
		UiTheme.GOOD)
```

The `_has_purchased` latch lives on `SceneManager`, not `arena.gd`, so it
survives scene changes — otherwise it would re-fire every time you re-entered
the kitchen. Because it is not persisted to the save file, it resets per session,
which matches "first time this session". Persisting it would need a field in the
Rust `SaveState`.

**2.** Because the scene changes immediately. Look at `_dispatch()`:

```gdscript
"tier_up":
	pending_tier = int(event.get("tier", tier()))
	tier_up.emit(pending_tier)       # arena pushes its toast here
	go_to_evolution()                # ...and the arena is freed moments later
```

The toast is created on a `ToastLayer` that belongs to `Arena`. The signal fires,
the toast is built with a 0.18-second fade-in, and then `change_scene_to_file()`
deletes the entire branch at the end of the frame. The toast never gets a chance
to render.

The right place for that message is the evolution scene itself, which already
does it — `evolution.gd` builds a `_caption` label reading "What? You are
evolving!" and swaps it to "Tier N reached." at the whiteout peak.

So `_on_tier_up()` is dead code. It is harmless, but if you wanted it to do
something useful you could have it save immediately, or trigger a sound that
lives on an autoload and therefore survives the transition.

---

Next: [06 — UI, Controls and containers](06-ui-and-containers.md)
