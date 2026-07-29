# 08 — Tweens and animation

Godot gives you two animation systems:

- **`AnimationPlayer`** — a timeline node you author in the editor. Right for
  character animation, cutscenes, anything with many tracks.
- **`Tween`** — code-driven interpolation. Right for UI feedback: a button
  punch, a fade, a bar filling.

This project is all UI, so it is all tweens. There is not a single
`AnimationPlayer` — which is itself a lesson, because the prototype's
`evolution.gd` called `$AnimationPlayer.play("evolve")` on a node that did not
exist in `evolution.tscn`. It would have crashed the moment the scene loaded.

## The basics

```gdscript
var tween := create_tween()
tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.06)
tween.tween_property(self, "scale", Vector2.ONE, 0.12)
```

`create_tween()` is a method on `Node`. The tween is bound to that node — if the
node is freed, the tween dies with it. This binding is the most important thing
to understand about tweens, and we come back to it.

`tween_property(object, property_path, final_value, duration)` interpolates from
the current value to `final_value`.

**Steps run in sequence by default.** The card scales up over 0.06s, then back
down over 0.12s.

## Property paths

The path is a string and it can reach into sub-properties:

```gdscript
tween.tween_property(label, "modulate:a", 0.0, 0.75)     # just the alpha
tween.tween_property(label, "position:y", target, 0.75)  # just the y
tween.tween_property(_flash, "color:a", 1.0, 0.28)       # alpha of a ColorRect
```

`"modulate:a"` animates only the alpha channel and leaves RGB alone. Without the
`:a` you would have to supply a whole `Color` and would clobber the hue.

This is genuinely useful and easy to forget exists.

## Easing

```gdscript
tween.tween_property(self, "scale", Vector2.ONE, 0.12) \
	.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
```

`tween_property()` returns a `PropertyTweener`, so you chain configuration onto
it. (The `\` is a GDScript line continuation.)

- **`set_trans()`** — the curve shape. `TRANS_LINEAR`, `TRANS_SINE`,
  `TRANS_QUAD`, `TRANS_BACK` (overshoots then settles), `TRANS_ELASTIC`,
  `TRANS_BOUNCE`.
- **`set_ease()`** — which end the curve applies to. `EASE_IN`, `EASE_OUT`,
  `EASE_IN_OUT`.

`TRANS_BACK` + `EASE_OUT` on the card punch means it overshoots slightly past
its resting size and settles back. That tiny overshoot is what makes a click feel
physical rather than mechanical. Linear motion almost always looks wrong for UI.

## Sequencing helpers

The toast in `toast_layer.gd` is a four-step sequence:

```gdscript
var tween := card.create_tween()
tween.tween_property(card, "modulate:a", 1.0, 0.18)   # fade in
tween.tween_interval(LIFETIME)                         # wait 4.5s
tween.tween_property(card, "modulate:a", 0.0, 0.45)   # fade out
tween.tween_callback(card.queue_free)                  # delete
```

- `tween_interval(t)` — a pause.
- `tween_callback(callable)` — run a function at this point in the sequence.
- `tween_method(callable, from, to, duration)` — call a function repeatedly with
  an interpolated value, for animating something that is not a property.

`tween_callback` taking a `Callable` is why `card.queue_free` appears without
parentheses. With them it would run immediately and pass the result.

## Parallel tracks

The floating "+550" moves up *and* fades at the same time:

```gdscript
var tween := create_tween().set_parallel(true)
tween.tween_property(label, "position:y", label.position.y - 70.0, 0.75) \
	.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
tween.tween_property(label, "modulate:a", 0.0, 0.75)
tween.chain().tween_callback(label.queue_free)
```

`set_parallel(true)` makes every subsequent step start together. `chain()` ends
the parallel block — the callback waits for both to finish.

Without `chain()`, `queue_free()` would fire immediately alongside the other two
and the label would vanish before animating.

## The lifetime trap

This is the bug worth learning properly, because it bit this codebase during
development.

`create_tween()` binds to the node you call it on. If **that** node is freed, the
tween is cancelled cleanly. But if the tween animates a *different* node that
gets freed first, you get "Attempt to call function on a previously freed
instance".

The toast layer evicts old toasts when there are too many:

```gdscript
while get_child_count() >= MAX_VISIBLE:
	var oldest := get_child(0)
	remove_child(oldest)
	oldest.queue_free()
```

The original code created the tween on the layer:

```gdscript
var tween := create_tween()               # bound to ToastLayer
tween.tween_property(card, "modulate:a", 1.0, 0.18)   # animates the card
```

`ToastLayer` lives for the whole scene, so its tween keeps running — while
animating a card that eviction just freed. The fix is one word:

```gdscript
# Bind the tween to the card, not to the layer: an evicted card takes its
# tween down with it instead of leaving one animating a freed node.
var tween := card.create_tween()
```

**Rule: create the tween on the node whose lifetime matches the animation.**
Usually that is the node being animated.

## Killing a tween

The evolution cutscene is skippable, so it must stop mid-flight:

```gdscript
func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	SceneManager.finish_evolution()
```

Three things:

- **`_finished` latch.** `_finish()` can be reached from the tween's final
  callback *and* from an input event. Without the guard, a click on the last
  frame calls `finish_evolution()` twice.
- **`is_valid()`.** A finished tween is not `null` but is no longer usable.
- **`kill()`.** Stops it immediately. Properties keep whatever value they had —
  it does not snap to the end.

Related methods: `pause()`, `play()`, `stop()`, `set_loops(n)`,
`set_speed_scale(x)`. And a tween emits `finished` if you would rather await it:

```gdscript
await tween.finished
```

## Building a sequence in a loop

The evolution flicker alternates textures five times with growing intensity:

```gdscript
_tween = create_tween()
for i in CYCLES:
	var upcoming: Texture2D = after if i % 2 == 0 else before
	var stretch := 1.0 + 0.06 * float(i + 1)
	_tween.tween_property(_sprite, "scale", Vector2(stretch, stretch),
		CYCLE_TIME * 0.5).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(func() -> void: _sprite.texture = upcoming)
	_tween.tween_property(_sprite, "scale", Vector2.ONE, CYCLE_TIME * 0.5) \
		.set_trans(Tween.TRANS_SINE)
```

Fifteen steps from six lines. Two details:

`var upcoming` is declared **inside** the loop. Lambdas capture by value at
creation, so each callback gets its own copy. Declaring it outside would give all
five callbacks the final value.

`stretch` grows with `i`, so the pulses intensify — a small touch that makes the
sequence build rather than repeat.

Then the payoff:

```gdscript
_tween.tween_property(_flash, "color:a", 1.0, 0.28)
_tween.tween_callback(_on_whiteout_peak.bind(after))
_tween.tween_property(_flash, "color:a", 0.0, 0.45)
_tween.tween_interval(0.9)
_tween.tween_callback(_finish)
```

The texture swap happens at peak white, when the screen is fully covered, so the
change is invisible. That is the whole Pokémon evolution trick.

## Docs

- [Tween class](https://docs.godotengine.org/en/stable/classes/class_tween.html)
- [PropertyTweener](https://docs.godotengine.org/en/stable/classes/class_propertytweener.html)
- [Introduction to animation](https://docs.godotengine.org/en/stable/tutorials/animation/introduction.html)

## Exercise

1. When the calorie bank crosses a threshold that makes a previously
   unaffordable upgrade affordable, pulse that row's border once. It must not
   pulse repeatedly while it stays affordable.
2. `_float_text()` in `food_button.gd` calls `create_tween()` on `self`, but
   animates a `label` that is a child of `self`. Given the lifetime rule above,
   is that a bug?

## Solution

**1.** `UpgradeRow` already knows its affordability, so it can detect the
transition itself. Add a field:

```gdscript
var _was_affordable := false
```

At the end of `configure()`, after `affordable` has been set:

```gdscript
if affordable and not _was_affordable and not maxed and unlocked:
	_pulse_affordable()
_was_affordable = affordable
```

```gdscript
func _pulse_affordable() -> void:
	if not is_instance_valid(_panel):
		return
	var tween := _panel.create_tween()
	tween.tween_property(_panel, "self_modulate", Color(1.3, 1.25, 0.8), 0.12) \
		.set_trans(Tween.TRANS_SINE)
	tween.tween_property(_panel, "self_modulate", Color.WHITE, 0.28) \
		.set_trans(Tween.TRANS_SINE)
```

The edge detection is the whole exercise. `configure()` runs roughly seven times
a second from `_refresh_shop()`, so pulsing on `if affordable` alone would give
you a strobing shop. Comparing against the previous value fires once per
transition.

Note `_panel.create_tween()` rather than `create_tween()` — following the
lifetime rule, and matching `flash_bought()`.

**2.** No, it is safe, but for a reason worth being explicit about.

The tween is bound to `self` (the `FoodButton`) and animates `label`, a child.
The danger case is the animated node dying before the tween's owner. Here that
cannot happen from the outside: `label` is only freed by the tween's own final
callback, and nothing else touches it.

And if the `FoodButton` is freed mid-animation — which happens on every
`_rebuild_food_cards()` — the tween is bound to it and dies with it, while
`label` is freed as its child. Both go together.

So it works. That said, `label.create_tween()` would be strictly more robust and
would cost nothing, and it is what you should write by default. The version in
`toast_layer.gd` is the one where the distinction was load-bearing, because
there the animated node had an independent death sentence.

---

Next: [09 — Saving and loading](09-persistence.md)
