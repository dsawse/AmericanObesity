# 03 — Nodes and scenes

Lesson 01 defined the terms. This one gets practical: reading scene files,
creating nodes, and the genuine tradeoff between building UI in the editor and
building it in code.

## Reading a `.tscn` file

Scene files are plain text, and being able to read them is a real skill — it
makes git diffs meaningful and merge conflicts survivable.

`amerobe/Scenes/title_screen.tscn`:

```
[gd_scene load_steps=2 format=3 uid="uid://bhfiqvlcq54pc"]

[ext_resource type="Script" path="res://Scripts/title_screen.gd" id="1_0hyng"]

[node name="TitleScreen" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_0hyng")
```

Section by section:

- **`[gd_scene ...]`** — the header. `load_steps` is how many resources must load
  (roughly: external resources + sub-resources + 1). `uid://` is a stable
  identifier; other files reference this scene by UID so renaming the file does
  not break links.
- **`[ext_resource ...]`** — something loaded from another file. Here, the
  script. Each gets a local `id` used below.
- **`[node ...]`** — a node. `name` is what you see in the tree; `type` is the
  built-in class. Properties follow as `key = value`.
- **`ExtResource("1_0hyng")`** — a reference back to the declared external
  resource.

Child nodes carry a `parent` field:

```
[node name="StartScreen" type="Sprite2D" parent="."]
```

`parent="."` means the root. `parent="UIBackground/VBoxContainer"` means nested
two deep. That is how the flat file encodes a tree.

Connections appear at the bottom:

```
[connection signal="pressed" from="Button" to="." method="_on_button_pressed"]
```

This is a signal wired up in the editor rather than in code — lesson 05 covers
what that means.

## Two ways to build UI

Here is the honest tradeoff, because this project deliberately switched sides.

### The editor approach

You drag nodes into the tree, set properties in the Inspector, and the `.tscn`
records it. The script then finds nodes by path:

```gdscript
@onready var weight_label: Label = $UIBackground/VBoxContainer/WeightLabel
```

**Good:** you see the layout while you build it. Designers can edit it without
touching code. Godot's anchor and container tooling is genuinely nice to use
visually.

**Bad:** node paths are stringly-typed. Rename `WeightLabel` in the editor and
that line still compiles — it fails at runtime with a null reference. The
prototype's `arena.gd` had three such paths plus a `get_node_or_null()` lookup
for a path that had never existed:

```gdscript
var ui_background = get_node_or_null("/root/MainScene/UIBackground")
```

There is no node called `MainScene` in this project. That call returned `null`
every single run, and the entire `setup_ui()` function it guarded did nothing.
Nobody noticed, because a silent `null` looks exactly like working code.

### The code approach

You create every node in `_ready()` and hold direct references:

```gdscript
_weight_label = UiTheme.make_label("--", 38, UiTheme.TEXT)
stack.add_child(_weight_label)
```

**Good:** `_weight_label` is a typed field. Rename it and the parser catches
every use. The whole layout is one readable function. It diffs cleanly in git.
Repetitive structures — nine food cards, eleven shop rows — come from a loop
instead of nine hand-placed nodes that drift out of sync.

**Bad:** you cannot see it until you run it. Fine-tuning spacing means
edit-run-look cycles. For art-directed, one-off screens this is genuinely worse.

### Which to use

Data-driven and repetitive UI belongs in code. Bespoke, art-directed layout
belongs in the editor. This game is a clicker whose entire UI is "render this
list of items" — so it is code, and the scene files are one node each.

A real project usually mixes both: hand-built scenes for the shell, code for the
lists inside it. There is no purity prize.

## Creating nodes in code

The pattern, from `arena.gd._build_left_column()`:

```gdscript
var hud := PanelContainer.new()                    # 1. construct
hud.add_theme_stylebox_override("panel", ...)      # 2. configure
column.add_child(hud)                              # 3. parent
```

Order matters more than it looks:

- A node not added to the tree is **not** freed automatically. Construct and then
  fail to parent it and you have leaked memory.
- `_ready()` fires during `add_child()`, synchronously. After that line returns,
  the child is fully initialised. This is what makes `card.configure(data)`
  immediately after `add_child(card)` safe.
- Setting size and position before the node is in a container is pointless —
  containers overwrite both on the next layout pass. Lesson 06 covers this.

## Instancing a scene

This project does not do it — it constructs nodes directly — but you will need
it constantly in other work, so here it is:

```gdscript
const BULLET := preload("res://Scenes/bullet.tscn")

func fire() -> void:
	var bullet := BULLET.instantiate()
	bullet.position = muzzle.global_position
	add_child(bullet)
```

`preload()` loads at parse time and is a constant; `load()` loads at runtime.
`instantiate()` builds a fresh copy of the tree. Use it for anything you spawn
repeatedly — bullets, enemies, particles.

If the food cards ever grow complex enough to want visual editing, `FoodButton`
would become `food_button.tscn` and `_rebuild_food_cards()` would call
`FOOD_CARD.instantiate()` instead of `FoodButton.new()`. Everything else stays.

## Node lifecycle

```
new()  →  add_child()  →  _enter_tree()  →  _ready()  →  _process() ...
                                                             ↓
                              queue_free()  →  _exit_tree()  →  freed
```

- `_enter_tree()` fires top-down (parent first), `_ready()` bottom-up (children
  first). When you need a parent to exist, use `_ready()`.
- `queue_free()` defers deletion to the end of the frame. `free()` is immediate
  and will crash you if the node is mid-signal. **Always prefer `queue_free()`.**
- A freed node's variable is not `null`. Guard with `is_instance_valid()`.

`arena.gd._rebuild_food_cards()` shows the careful version:

```gdscript
for child in _food_grid.get_children():
	_food_grid.remove_child(child)
	child.queue_free()
_food_cards.clear()
```

`get_children()` returns a *copy* of the child list, so mutating during
iteration is safe. `remove_child()` detaches immediately so the container
re-lays-out this frame; `queue_free()` handles the actual deletion. Clearing the
dictionary matters too — otherwise it holds references to freed nodes.

## Docs

- [Creating instances](https://docs.godotengine.org/en/stable/getting_started/step_by_step/instancing.html)
- [Node class reference](https://docs.godotengine.org/en/stable/classes/class_node.html)
- [Scene file formats](https://docs.godotengine.org/en/stable/contributing/development/file_formats/tscn.html)

## Exercise

1. Add a **Stats** tab to the right-hand panel of the kitchen, alongside
   *Upgrades* and *Achievements*. It should show total clicks, lifetime calories,
   calories per second, and the click multiplier, each on its own line, updating
   live.
2. Explain why `_rebuild_food_cards()` calls `_food_cards.clear()`. What
   specifically breaks if you delete that line?

## Solution

**1.** Three changes to `arena.gd`.

Add a field near the other column references:

```gdscript
var _stats_column: VBoxContainer
var _stats_lines: Array[Label] = []
```

In `_build_right_column()`, after the two existing lists:

```gdscript
_upgrade_column = _scrolling_list(tabs, "Upgrades")
_achievement_column = _scrolling_list(tabs, "Achievements")
_stats_column = _scrolling_list(tabs, "Stats")

for i in 4:
	var line := UiTheme.make_label("", 18)
	_stats_column.add_child(line)
	_stats_lines.append(line)
```

Then at the end of `_refresh_hud()`, where `snap` is already in scope:

```gdscript
if _stats_lines.size() == 4:
	_stats_lines[0].text = "Total clicks: %s" % Num.fmt(float(snap.get("total_clicks", 0)))
	_stats_lines[1].text = "Lifetime calories: %s" % Num.fmt(float(snap.get("lifetime_calories", 0.0)))
	_stats_lines[2].text = "Calories/sec: %s" % Num.fmt(float(snap.get("cps", 0.0)))
	_stats_lines[3].text = "Click multiplier: x%.2f" % float(snap.get("click_multiplier", 1.0))
```

Note what you did *not* have to do: no scene file was touched, and no new data
had to cross the Rust boundary — every field was already in `snapshot_json()`.
That is the payoff of a wide snapshot and a code-built UI.

**2.** `_food_cards` maps food id to the `FoodButton` node. After the loop, every
one of those nodes has been queued for deletion, so the dictionary holds nine
dangling references.

Concretely, `_refresh_food_values()` does:

```gdscript
var card: FoodButton = _food_cards[id]
card.refresh_value(...)
```

Without the `clear()`, the rebuild inserts fresh entries over the same keys — so
in this specific code you would *probably* get away with it, because every id is
overwritten. But the moment a food is removed from `defs.rs`, its stale key
survives, `refresh_value()` is called on a freed node, and you get
"Attempt to call function on a previously freed instance."

The general rule: when you free nodes, clear every container that referenced
them, in the same breath. Relying on "the keys all get overwritten anyway" is a
bug waiting for a content change.

---

Next: [04 — The tree and autoloads](04-tree-and-autoloads.md)
