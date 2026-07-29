# Godot, taught through American Obesity

A course that uses the code already sitting in this repository as its textbook.
Every concept is introduced by pointing at a file you own, explaining why it is
written that way, and then asking you to change it.

This is not a generic tutorial. You will not build a Pong clone. You will learn
Godot by understanding the game on your hard drive, then extending it.

## Who this is for

Someone who can program but has never used Godot. If you know what a class, a
function and a callback are, you have enough. Where GDScript differs from what
you already know, the course says so explicitly rather than assuming.

## The lessons

| # | Lesson | What you walk away with |
|---|--------|------------------------|
| 01 | [Mental model](01-mental-model.md) | What a node, a scene and the tree actually are, and how this project boots |
| 02 | [GDScript](02-gdscript.md) | The language: typing, inference, lifecycle callbacks, the gotchas |
| 03 | [Nodes and scenes](03-nodes-and-scenes.md) | Reading `.tscn` files, instancing, node lifecycle, building UI in code vs. the editor |
| 04 | [The tree and autoloads](04-tree-and-autoloads.md) | Singletons, scene switching, `process_mode`, why `SceneManager` exists |
| 05 | [Signals](05-signals.md) | Godot's observer pattern, and the three different ways this repo uses it |
| 06 | [UI, Controls and containers](06-ui-and-containers.md) | Anchors, size flags, the container system — the hardest part of Godot |
| 07 | [Resources, textures and drawing](07-resources-and-drawing.md) | `Resource`, `Image`, `ImageTexture`, `StyleBox`, and how the placeholder art works |
| 08 | [Tweens and animation](08-tweens.md) | Procedural animation, chaining, parallel tracks, the lifetime traps |
| 09 | [Saving and loading](09-persistence.md) | `FileAccess`, `user://`, JSON, and designing a save format that survives updates |
| 10 | [The Rust layer](10-rust-gdextension.md) | GDExtension, godot-rust, and when native code is worth it |
| 11 | [Debugging and where to go next](11-debugging-and-next.md) | The debugger, profiler, remote tree, and a roadmap for this game |

Work through them in order. Lessons 06 and 10 are the meaty ones.

## How to use each lesson

Every lesson has the same shape:

1. **The idea** — the concept in plain terms, with the mental model that makes
   it click.
2. **In your code** — the exact file and function where it appears, quoted and
   annotated.
3. **The docs** — a link to the official page, because you should get used to
   reading them.
4. **Exercise** — a change to make to the real game.
5. **Solution** — a worked answer. Try the exercise first.

## Before you start

Make sure the game runs:

```powershell
cd C:\Users\Shadow\Documents\GitHub\AmericanObesity
cargo build --workspace
```

Then open `amerobe/project.godot` in Godot and press **F5**. You should get a
title screen, not a red "simulation engine not loaded" banner. If you get the
banner, the Rust extension did not build — see the root `README.md`.

Keep the **Output** panel (bottom dock) open the whole time you work. Godot
reports script errors there and nowhere else. Getting into the habit of
glancing at it will save you hours.

## A note on this codebase

The version of this project you started with was a prototype: UI half-defined in
scene files and half in code, a scene manager with broken dictionary keys, and a
Rust extension whose library path never resolved. It has since been rewritten so
that the simulation lives in Rust, the UI is built entirely in code, and the two
communicate over a deliberately narrow interface.

That rewrite makes it a better teaching example than most tutorial projects,
because you can see *why* each decision was made — and lesson 03 shows you the
prototype's approach alongside the current one so you can judge the tradeoff
yourself. There is no single correct answer; there is a correct answer for a
given situation, and the course tries to teach you to tell them apart.

## Official documentation

Bookmark these. The course links into them constantly.

- [Godot docs home](https://docs.godotengine.org/en/stable/)
- [Step by step tutorial](https://docs.godotengine.org/en/stable/getting_started/step_by_step/index.html)
- [GDScript reference](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html)
- [Class reference](https://docs.godotengine.org/en/stable/classes/index.html) — the single most useful page once you know your way around
- [GUI / Control docs](https://docs.godotengine.org/en/stable/tutorials/ui/index.html)
- [godot-rust book](https://godot-rust.github.io/book/)
