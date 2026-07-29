# 01 — The mental model

Before any syntax, you need three concepts. Almost every Godot confusion traces
back to one of them being fuzzy.

## Nodes

A **node** is an object that does one thing. `Label` draws text. `Button`
detects clicks. `Timer` counts down. `AudioStreamPlayer` plays sound. There are
several hundred built-in node types.

Nodes are arranged in a **tree**: every node has one parent and any number of
children. That is the whole structure. A button inside a panel inside a screen
is just three nodes in a parent-child chain.

Godot's design bet is *composition over inheritance at the object level*. Instead
of a monolithic `Player` class that renders and collides and plays sound, you
build a small tree: a `CharacterBody2D` with a `Sprite2D` child, a
`CollisionShape2D` child, and an `AudioStreamPlayer2D` child. Each child brings
one capability.

Your `FoodButton` is exactly this. Open `amerobe/Scripts/food_button.gd` and
look at `_build()`. One food card is a small tree:

```
FoodButton (Control)          <- the card itself, holds the logic
├── PanelContainer            <- draws the bordered background
│   └── VBoxContainer         <- stacks its children vertically
│       ├── TextureRect       <- the food icon
│       ├── Label             <- the name
│       ├── Label             <- "+550 cal"
│       └── ProgressBar       <- the cooldown bar
└── Button                    <- invisible, sits on top, catches clicks
```

No single node knows how to be a food card. The card is the arrangement.

## Scenes

A **scene** is a saved tree of nodes. That is genuinely all it is — the word is
misleading if you are coming from Unity, where a scene is a whole level.

In Godot a scene can be a whole level, or a single button, or a bullet. Any
tree you might want to reuse gets saved as a `.tscn` file and becomes a scene.
Scenes can be **instanced** inside other scenes, which is Godot's answer to
prefabs.

This project has three scene files, and they are deliberately tiny. Here is
`amerobe/Scenes/main.tscn` in its entirety:

```
[gd_scene load_steps=2 format=3 uid="uid://dnnpf1431v2yf"]

[ext_resource type="Script" path="res://Scripts/arena.gd" id="1_dhnnb"]

[node name="Arena" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_dhnnb")
```

One node. A `Control` that fills the screen, with `arena.gd` attached. Every
other node in the kitchen — all forty-odd of them — is created at runtime by
that script. Lesson 03 covers when that is the right call and when it is not.

## The scene tree

At runtime there is exactly one live tree, owned by the `SceneTree` object. It
looks roughly like this while you are playing:

```
root (Window)
├── SceneManager          <- autoload, always present
└── Arena                 <- the "current scene", swapped when you change scenes
    ├── TextureRect
    ├── ColorRect
    ├── MarginContainer
    │   └── ...
    └── ToastLayer
```

Two things to notice, because they explain most of this codebase's architecture:

**The current scene is replaced wholesale.** When `SceneManager` calls
`change_scene_to_file()`, the entire `Arena` branch is deleted and a new branch
is built from the new scene file. Anything stored in a node on that branch is
gone.

**Autoloads survive.** `SceneManager` is registered as an autoload in
`project.godot`:

```
[autoload]

SceneManager="*res://Scripts/scene_manager.gd"
```

It is added as a child of `root` before the first scene loads, and it is never
removed. That is precisely why the game state lives there and not in `arena.gd`.
If your calorie count lived on the `Arena` node, walking to the title screen
would delete your save. Lesson 04 goes deeper.

## How this project boots

Trace it once and a lot falls into place.

1. Godot reads `amerobe/project.godot`. Two lines matter:
   `run/main_scene="res://Scenes/title_screen.tscn"` and the autoload entry.
2. Godot loads `amerobe/engine.gdextension`, which points at
   `../target/debug/engine.dll`. This registers the Rust `ClickerGame` class
   with the engine. If the DLL is missing, the class simply does not exist —
   which is the failure you hit earlier.
3. `SceneManager` is instanced and added under `root`. Its `_ready()` runs:
   it checks `ClassDB.class_exists("ClickerGame")`, instances one, loads
   `user://progress.save`, and grants offline earnings.
4. `title_screen.tscn` is loaded as the current scene. `title_screen.gd`'s
   `_ready()` builds the menu in code.
5. Every frame after that, `SceneManager._process()` ticks the Rust simulation
   and the current scene's `_process()` redraws the HUD.

Steps 3 and 5 are the load-bearing ones. The simulation advances regardless of
which screen you are looking at, because it lives on a node that never gets
deleted.

## `res://` and `user://`

Two virtual filesystem roots, and mixing them up is a classic beginner bug.

- **`res://`** is your project folder — `amerobe/`. It is **read-only in an
  exported game**. Never try to write here at runtime.
- **`user://`** is a per-user writable directory outside the project. On Windows
  it lands in `%APPDATA%\Godot\app_userdata\amerobe\`.

Your save file is at `user://progress.save`, declared in `scene_manager.gd`:

```gdscript
const SAVE_PATH := "user://progress.save"
```

That is correct and deliberate. If it were `res://progress.save` it would work
in the editor and silently fail for every player of an exported build.

## Docs

- [Nodes and scenes](https://docs.godotengine.org/en/stable/getting_started/step_by_step/nodes_and_scenes.html)
- [Scene tree](https://docs.godotengine.org/en/stable/tutorials/scripting/scene_tree.html)
- [File paths in Godot projects](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html)

## Exercise

Without running the game, answer these from the source:

1. If you click **Main Menu** in the kitchen and then **Continue**, does your
   calorie count survive? Which line of which file proves it?
2. `arena.gd` has a `_process()` that calls `_refresh_hud()` every frame. When
   you are on the title screen, is the simulation still advancing? Why?
3. Where would you put a background music player so it keeps playing across
   scene changes, and why does putting it in `arena.tscn` fail?

## Solution

**1.** Yes. The count lives in the Rust `ClickerGame` object held by
`SceneManager.game` (`scene_manager.gd`, the `var game: RefCounted = null`
declaration). `SceneManager` is an autoload, so the scene change deletes the
`Arena` branch but not `SceneManager`. As a belt-and-braces measure,
`_on_menu_pressed()` in `arena.gd` also calls `SceneManager.save_game()` first.

**2.** Yes. `SceneManager._process()` calls `game.tick(delta)` and it runs on
every frame regardless of the current scene, because `SceneManager` is a node in
the tree with processing enabled. `arena.gd._process()` stops running when
`Arena` is freed, but that only stops the *display* updating, not the
simulation. This is why you can idle on the title screen and come back richer.

**3.** As an autoload, or as a child of an autoload. Registering it in
`project.godot` under `[autoload]` puts it under `root`, outside the current
scene branch, so `change_scene_to_file()` never touches it. Putting it in
`arena.tscn` fails because that whole branch is freed the moment you leave the
kitchen — the player would be deleted mid-note.

---

Next: [02 — GDScript](02-gdscript.md)
