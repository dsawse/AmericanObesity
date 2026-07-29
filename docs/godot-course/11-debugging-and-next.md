# 11 — Debugging and where to go next

Tools first, then a roadmap.

## The Output panel

Bottom dock, always open. Godot reports every script error here and nowhere
else. A silent failure in Godot almost always left a line in Output.

Your own messages:

```gdscript
print("value is ", x)                    # plain
push_warning("save file was unreadable")  # yellow, with a stack trace
push_error("no scene registered for 'x'") # red, with a stack trace
```

`push_warning` and `push_error` are better than `print` for anything a user
might hit — they carry the script and line number, and they show up in the
Debugger's error list where you can click through to the source.

This codebase uses them at every boundary: a missing extension, an unwritable
save, an unregistered scene.

## The debugger

**Breakpoints.** Click the gutter left of a line number, or write `breakpoint`
in code. When execution stops you get:

- **Stack Frames** — the call chain
- **Variables** — locals and members in the selected frame
- **Step Into / Over / Continue** — the usual controls

Set one in `arena.gd._on_purchase_requested()` and buy something. You can watch
`_buy_count`, the return from `SceneManager.buy_upgrade()`, and step into the
GDScript side of the call.

You cannot step into the Rust. Debugging across the GDExtension boundary needs a
native debugger attached to the Godot process — possible but rarely worth it.
Test Rust with `cargo test` instead; that is what `state.rs` is structured for.

## The Remote scene tree

While the game runs, the **Scene** dock has a **Remote** tab showing the *live*
tree, not the file. This is the most underused tool in Godot.

Because this project builds its entire UI in code, Remote is the only way to see
what the kitchen actually looks like structurally. Run the game, switch to
Remote, expand `Arena`, and you will see the `MarginContainer` → `HBoxContainer`
→ three `VBoxContainer`s you read about in lesson 06.

Click any node and the Inspector shows its live values. You can edit them while
running to test a layout tweak before committing it to code.

If something is invisible, this is where you find out whether it does not exist,
has zero size, or is behind something else.

## The profiler

**Debugger → Profiler**, press Start, play, then look at the frame breakdown.
It attributes time to individual functions.

If you ever want to check the claim in lesson 10 that per-frame JSON is cheap,
this is how. Look for `_refresh_hud` and see what fraction of the frame it takes.
Measure before optimising — the cost is almost never where you assume.

The **Monitors** tab graphs FPS, memory, draw calls and object counts over time.
A steadily climbing object count means you are leaking nodes: constructing
without parenting, or forgetting `queue_free()`.

## Errors you will actually hit

| Message | Cause | Fix |
|---|---|---|
| `Attempt to call function on a null instance` | A `$Path` or `get_node()` found nothing | Check the node name and that it exists at that time |
| `Attempt to call function on a previously freed instance` | Used a node after `queue_free()` | Guard with `is_instance_valid()` |
| `Invalid get index 'x' on base Dictionary` | Missing key with `dict.x` or `dict["x"]` | Use `.get(key, default)` |
| Clicks do nothing | A `Control` above is eating them | Check `mouse_filter` (lesson 06) |
| UI ignores your `size`/`position` | The parent is a `Container` | Use `custom_minimum_size` and size flags |
| `GDExtension dynamic library not found` | Wrong path or unbuilt DLL | Check `.gdextension` paths, rebuild, restart Godot |
| Rebuilt Rust, nothing changed | `reloadable = false` | Restart Godot |
| Signal fires but handler never runs | Editor connection pointing at a renamed method | Connect in code instead |

## Reading the class reference

Learn to navigate [the class reference](https://docs.godotengine.org/en/stable/classes/index.html)
and you stop needing tutorials. Every page has the same sections:

- **Properties** — what you can set
- **Methods** — what you can call
- **Signals** — what you can connect to
- **Theme Properties** — valid `add_theme_*_override` names for that node

That last one is the answer to "what strings can I pass to
`add_theme_constant_override`". It is per-node-type and you cannot guess it.

Inside the editor, press **F1** and search. It is the same content offline, and
faster than a browser.

## Where to take this game

Roughly in order of value-per-effort.

**Sound.** The biggest perceptual upgrade a clicker can get, and there is
currently none. Add an `AudioStreamPlayer` autoload so it survives scene changes,
and call it from `FoodButton._on_pressed()` and the achievement toast. Vary the
pitch slightly per click (`pitch_scale = randf_range(0.95, 1.05)`) or the
repetition becomes grating fast.

**Real art.** Five PNGs are missing and the placeholders cover them. Drop real
files into `art/` with the names in the root README and they take over
automatically — `PlaceholderArt._try_load()` finds them, no code changes.

**Number-formatting polish.** `Num.fmt()` stops at `Dc` (10³⁶). A dedicated
player will exceed that. Either extend the suffix table or switch to scientific
notation above a threshold.

**Prestige.** The standard idle-game third act: reset progress for a permanent
multiplier. Add `prestige_level` and `prestige_points` to `SaveState` — with
`#[serde(default)]`, per lesson 09 — a multiplier in `cps()` and
`click_multiplier()`, and a confirm dialog. Mostly a Rust change; the UI needs
one button.

**Statistics screen.** `food_clicks` is already tracked per food and already
crosses the boundary in `foods_json()`, and nothing displays it. A "most eaten"
table is nearly free. This is the lesson 03 exercise, extended.

**Settings.** Volume, window mode, and a save-file-location button. Settings go
in a separate `user://settings.cfg` via `ConfigFile`, not in the game save — you
do not want a corrupt run to reset someone's audio preferences.

**Keyboard shortcuts.** Number keys 1-9 to eat the corresponding food. Define
actions in **Project Settings → Input Map** and read them with
`Input.is_action_just_pressed()` rather than hard-coding keycodes, so they are
rebindable later.

## A suggested learning path from here

1. **Do the exercises** in lessons 03, 06 and 09 if you skipped them. Those three
   cover the concepts that transfer to every Godot project.
2. **Build the Stats screen** end to end. It touches containers, the snapshot,
   and live refresh — a full vertical slice with no new concepts.
3. **Add sound.** Forces you to learn autoloads properly and meet Godot's audio
   buses.
4. **Then build something 2D with physics.** This project taught you nodes,
   scenes, signals, UI and resources — but nothing about `CharacterBody2D`,
   collision layers, `TileMap`, or the physics step. The official
   [2D game tutorial](https://docs.godotengine.org/en/stable/getting_started/first_2d_game/index.html)
   is genuinely good and will take a couple of hours now that the fundamentals
   are in place.

## Docs

- [Debugger panel](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/debugger_panel.html)
- [Overview of debugging tools](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/overview_of_debugging_tools.html)
- [Class reference](https://docs.godotengine.org/en/stable/classes/index.html)
- [Your first 2D game](https://docs.godotengine.org/en/stable/getting_started/first_2d_game/index.html)

## Final exercise

No solution for this one.

Pick one item from "Where to take this game" and ship it properly: written,
tested by playing, committed with a message that explains why. Then open
`docs/godot-course/` and add a short lesson 12 documenting what you built and
what surprised you.

Writing the explanation is the part that converts "I got it working" into "I
understand it". You will find at least one thing you thought you knew and did
not — that is the point.

---

Back to the [course index](README.md).
