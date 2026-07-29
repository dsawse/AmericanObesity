# 04 — The tree and autoloads

`SceneManager` is the spine of this project. Understanding it teaches you
singletons, scene transitions, and the frame loop in one go.

## Registering an autoload

In `amerobe/project.godot`:

```
[autoload]

SceneManager="*res://Scripts/scene_manager.gd"
```

The leading `*` means "make this a singleton accessible by name". Godot creates
the node at startup, parents it to `root`, and exposes it globally — any script
can write `SceneManager.save_game()` with no import and no lookup.

In the editor this is **Project → Project Settings → Autoload**. You can
autoload a script (Godot wraps it in a `Node`) or a whole scene.

Autoloads are added **before** the main scene, in the order listed. If you add a
second autoload that depends on `SceneManager`, put it below.

## Why this project needs one

Everything in the current scene dies on a scene change. The game state must not.

```gdscript
var game: RefCounted = null          # the Rust ClickerGame object
var engine_available := false
var pending_tier := 1
var startup_events: Array = []
```

Those live on `SceneManager` because they must outlive `Arena`. Put them on
`Arena` and walking to the title screen resets your run.

The prototype had exactly this bug in embryo: `arena.gd` owned
`var weight_lbs: float = 150.0` as a node field, while `scene_manager.gd` owned a
*separate* `var current_weight: float = 150.0`. Two sources of truth that were
never synchronised — the arena never told the scene manager anything, so the
evolution threshold could never fire. One authority, on a node that persists,
avoids the entire class of problem.

## Guarding against the missing extension

```gdscript
func _create_game() -> void:
	if not ClassDB.class_exists("ClickerGame"):
		engine_available = false
		engine_error = ENGINE_MISSING_HINT
		push_error(engine_error)
		return

	var instance: Object = ClassDB.instantiate("ClickerGame")
```

This is worth studying. `ClickerGame` comes from the Rust GDExtension. If the
DLL is not built, that class does not exist.

Writing `ClickerGame.new()` directly would be a **parse error** — GDScript
resolves global class names when it compiles the script, so the whole file would
fail to load and you would get a cascade of unrelated errors.

`ClassDB.class_exists()` and `ClassDB.instantiate()` look the class up by string
at runtime instead. Nothing is resolved at parse time, so the script always
loads, and you can report the real problem. That is why you saw a clear "engine
not loaded" banner instead of a wall of red.

The pattern generalises: **when code must tolerate something being absent, look
it up by name at runtime rather than referencing it symbolically.**

## The frame loop

```gdscript
func _process(delta: float) -> void:
	if not engine_available:
		return

	game.tick(delta)
	for event in _pop_events():
		_dispatch(event)

	_autosave_accum += delta
	if _autosave_accum >= AUTOSAVE_INTERVAL:
		_autosave_accum = 0.0
		save_game()
```

Four jobs per frame: advance the simulation, drain the event queue, count down
to the next autosave, save when due.

The accumulator pattern is worth internalising. You want something every 20
seconds, but `_process` runs ~60 times a second at an irregular cadence. Adding
`delta` and comparing against a threshold is frame-rate independent — it fires at
20 seconds of *wall clock* whether the game is running at 30fps or 144fps.

A `Timer` node would also work and is more idiomatic when the interval is fixed
and you want it to survive pausing differently. For a simple accumulator inside a
loop you are already running, this is fine and has less machinery.

### `process_mode`

```gdscript
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
```

If the tree is ever paused (`get_tree().paused = true`), most nodes stop
processing. `PROCESS_MODE_ALWAYS` opts out, so the simulation and autosave keep
running through a pause menu. The other useful values are
`PROCESS_MODE_PAUSABLE` (the default) and `PROCESS_MODE_WHEN_PAUSED`, which is
how you make a pause menu that only runs while paused.

## Changing scenes safely

```gdscript
func _change_scene(key: String) -> void:
	if _changing_scene:
		return
	var path: String = String(SCENES.get(key, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("SceneManager: no scene registered for '%s' (%s)" % [key, path])
		return

	_changing_scene = true
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("SceneManager: failed to open %s (error %d)" % [path, err])
	await get_tree().process_frame
	await get_tree().process_frame
	_changing_scene = false
```

Four defences, each earned:

1. **`_changing_scene` guard.** `_dispatch()` can fire a tier-up mid-frame, and
   tier-ups trigger transitions. Two tier-ups in one frame — entirely possible
   when offline earnings land — would otherwise queue two scene changes.
2. **`.get(key, "")`.** No crash on an unknown key. See lesson 02.
3. **`ResourceLoader.exists()`.** Catches a typo'd or deleted scene path with a
   clear message rather than an engine-level failure.
4. **Two awaited frames.** `change_scene_to_file()` is deferred — it swaps at the
   end of the current frame, not immediately. Waiting two frames before releasing
   the guard makes sure the swap has completed.

`change_scene_to_file()` being deferred is important and non-obvious. The old
scene is still alive for the rest of the frame. Code after that call still runs,
against the old tree.

## Buffering events that arrive too early

A subtle ordering problem, solved cleanly:

```gdscript
func _ready() -> void:
	...
	load_game()
	game.apply_offline(_now())
	startup_events = _pop_events()
```

`SceneManager._ready()` runs *before* the first scene exists. Offline earnings
are granted right there, producing events — but nothing is listening yet.
Emitting signals into the void would silently lose them.

So they are parked in `startup_events`, and the first screen to come up drains
them:

```gdscript
# arena.gd
for event in SceneManager.consume_startup_events():
	_replay_startup_event(event)
```

```gdscript
# scene_manager.gd
func consume_startup_events() -> Array:
	var events := startup_events
	startup_events = []
	return events
```

Whenever you have a producer that can run before its consumers exist, you need
a buffer like this. The alternative — deferring the work until someone asks —
would mean offline earnings are not credited until you open the kitchen, which
changes the behaviour.

## Docs

- [Singletons (autoload)](https://docs.godotengine.org/en/stable/tutorials/scripting/singletons_autoload.html)
- [Change scenes manually](https://docs.godotengine.org/en/stable/tutorials/scripting/change_scenes_manually.html)
- [Pausing games](https://docs.godotengine.org/en/stable/tutorials/scripting/pausing_games.html)

## Exercise

1. Add a pause feature: **Escape** toggles `get_tree().paused`, and a centred
   "PAUSED" label appears. The simulation must keep running while paused (this
   is an idle game — pausing should not cost the player progress).
2. `SceneManager._notification()` saves on `NOTIFICATION_WM_CLOSE_REQUEST` and
   `NOTIFICATION_EXIT_TREE`. Why is `NOTIFICATION_PREDELETE` a bad choice here?

## Solution

**1.** In `arena.gd`, add a field and build the overlay in `_build_ui()`:

```gdscript
var _pause_overlay: Control
```

```gdscript
_pause_overlay = ColorRect.new()
_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
_pause_overlay.color = Color(0, 0, 0, 0.6)
_pause_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
_pause_overlay.visible = false
_pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
add_child(_pause_overlay)

var paused_label := UiTheme.make_label("PAUSED", 64, UiTheme.GOLD)
paused_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER,
	Control.PRESET_MODE_MINSIZE)
_pause_overlay.add_child(paused_label)
```

Then:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		var tree := get_tree()
		tree.paused = not tree.paused
		_pause_overlay.visible = tree.paused
		get_viewport().set_input_as_handled()
```

Two details do the work. The overlay needs
`process_mode = PROCESS_MODE_ALWAYS`, or once paused it stops processing and
cannot be dismissed. And the simulation keeps running for free — `SceneManager`
already sets `PROCESS_MODE_ALWAYS` on itself, so `game.tick()` is unaffected by
the pause. The HUD stops refreshing (`arena.gd` is pausable), so the numbers
freeze on screen while the real state advances underneath; they snap to the true
value on unpause. For an idle game that is the right behaviour.

**2.** `NOTIFICATION_PREDELETE` fires when the object is being destroyed, at
which point its members may already be in an unusable state. `save_game()` calls
`game.save_json(_now())` — if the Rust `ClickerGame` reference has already been
released, that is a call on a dead object.

`NOTIFICATION_EXIT_TREE` fires earlier, while everything is still valid, and
`NOTIFICATION_WM_CLOSE_REQUEST` fires earlier still — when the user clicks the X,
before any teardown. Together they cover clean shutdown with the object graph
fully intact.

The general lesson: do cleanup work at the *earliest* point where you know it is
needed, not the latest. By the time something is being deleted, it is too late
to use it.

---

Next: [05 — Signals](05-signals.md)
