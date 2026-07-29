# 07 — Resources, textures and drawing

`Scripts/placeholder_art.gd` exists because five PNGs referenced by this project
were never committed to git. Rather than ship a broken build, it draws stand-ins
at runtime. That makes it an unusually good tour of Godot's resource system.

## Nodes vs. Resources

Godot has two object families and the distinction matters.

- A **Node** lives in the scene tree. It has a position in a hierarchy, receives
  callbacks, and is unique.
- A **Resource** is data. It lives in a file or in memory, has no position, and
  can be **shared by many nodes at once**.

`Texture2D`, `Image`, `StyleBoxFlat`, `Theme`, `AudioStream`, `PackedScene`,
`Font` are all resources. So is a `.tscn` file when loaded — a `PackedScene` is a
resource describing a tree of nodes.

The sharing part has real consequences. When you write:

```gdscript
_icon.texture = PlaceholderArt.texture_for_food(food_id, _accent)
```

and the cache returns the same `ImageTexture` to three different cards, all three
point at one object in memory. Modify it and all three change. Godot's
`duplicate()` exists for when you need a private copy.

`ui_theme.gd` is quietly careful about this:

```gdscript
var hover := normal.duplicate() as StyleBoxFlat
hover.bg_color = base.lightened(0.15)
```

Without `duplicate()`, setting `hover.bg_color` would mutate the shared `normal`
stylebox and every state would look the same.

## Loading resources

Three ways, and the differences matter:

```gdscript
const BULLET := preload("res://Scenes/bullet.tscn")   # parse time, constant
var tex := load("res://art/burger.png")               # runtime
if ResourceLoader.exists(path):                       # runtime, checked
	var res := ResourceLoader.load(path)
```

`preload()` happens when the script is compiled, so the path must be a literal
and the file must exist. `load()` happens when the line runs and accepts a
variable.

`placeholder_art.gd` needs the checked form, because the whole point is that the
file might be absent:

```gdscript
static func _try_load(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		return null
	var res := ResourceLoader.load(path)
	return res as Texture2D
```

Three defences: empty path, missing resource, and `as Texture2D`, which yields
`null` rather than crashing if the file turned out to be something else. The
callers then fall back:

```gdscript
var tex := _try_load("res://art/%s.png" % id)
if tex == null:
	tex = _draw_food(id, color, size)
```

Drop a real `burger.png` into `art/` and it is used automatically. Delete it and
the placeholder returns. No code changes either way.

## `.import` files

Godot does not use your PNG directly. On first sight of `art/burger.png` it
generates `art/burger.png.import` and writes a converted file into `.godot/`.
The `.import` file records the settings and a UID.

Consequences you need to know:

- **Commit `.import` files.** They are part of the project.
- **Never commit `.godot/`.** It is a cache. Your `.gitignore` has `.godot/` for
  this reason.
- **An `.import` without its source is broken.** That is the exact state this
  repo is in for five files: `.gitignore` contained `/art/*.png`, so the PNGs
  were never committed while their `.import` stubs were. Godot logs an error for
  each on startup.

`cleanup-stale-files.ps1` removes those five orphans.

## Drawing an image from scratch

The core loop of `placeholder_art.gd`:

```gdscript
static func _blank(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img
```

```gdscript
static func _tex(img: Image) -> Texture2D:
	return ImageTexture.create_from_image(img)
```

The distinction to hold onto:

- **`Image`** is CPU-side pixel data. You can read and write individual pixels.
  It cannot be displayed.
- **`ImageTexture`** is GPU-side. It can be assigned to `TextureRect.texture`.
  You cannot poke pixels in it.

So the workflow is always: build an `Image`, then convert once. Converting is not
free — do it at the end, not per pixel.

`Image.create(width, height, use_mipmaps, format)`. `FORMAT_RGBA8` is eight bits
per channel with alpha, which is what you want for UI art.

### Alpha blending by hand

`Image.set_pixel()` overwrites — it does not blend. Drawing a translucent shape
over an existing one needs the maths done manually:

```gdscript
static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if c.a >= 0.999:
		img.set_pixel(x, y, c)
		return
	var under := img.get_pixel(x, y)
	var a := c.a + under.a * (1.0 - c.a)
	if a <= 0.0:
		img.set_pixel(x, y, Color(0, 0, 0, 0))
		return
	img.set_pixel(x, y, Color(
		(c.r * c.a + under.r * under.a * (1.0 - c.a)) / a,
		...
		a))
```

That is standard source-over compositing on premultiplied values, divided back
out. Three things to notice as general technique:

1. **Bounds checking first.** `set_pixel()` out of range is an error. Every
   drawing helper funnels through `_px()`, so the check is written once.
2. **A fast path for the opaque case.** Most pixels are fully opaque, and
   `c.a >= 0.999` skips a `get_pixel()` and eight multiplications.
3. **The `a <= 0.0` guard.** Dividing by the composited alpha blows up when both
   layers are fully transparent.

### Shape primitives

Everything else builds on `_px()`. The ellipse is the neat one:

```gdscript
static func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	for iy in range(int(floorf(cy - ry)), int(ceilf(cy + ry)) + 1):
		for ix in range(int(floorf(cx - rx)), int(ceilf(cx + rx)) + 1):
			var dx := (float(ix) + 0.5 - cx) / rx
			var dy := (float(iy) + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_px(img, ix, iy, c)
```

Normalising by `rx` and `ry` turns the ellipse test into the unit-circle test
`dx² + dy² ≤ 1`. The `+ 0.5` samples pixel centres rather than corners, which
avoids a half-pixel bias. And the loop only covers the bounding box, not the
whole image.

The character sprite is then just layered ellipses, with the proportions
interpolated by tier:

```gdscript
var t := clampf(float(tier - 1) / 2.0, 0.0, 1.0)
var body_rx := lerpf(s * 0.16, s * 0.38, t)
var body_ry := lerpf(s * 0.24, s * 0.30, t)
```

`t` goes 0 → 0.5 → 1 across the three tiers, and every dimension lerps along it.
One code path, three sprites. Add a fourth tier and the maths still works.

## Caching

Drawing a 384×384 sprite means ~147,000 GDScript function calls. That is tens of
milliseconds — fine once, unacceptable per frame.

```gdscript
static var _cache: Dictionary = {}

static func texture_for_food(id: String, color: Color, size: int = 128) -> Texture2D:
	var key := "food:%s:%d" % [id, size]
	if _cache.has(key):
		return _cache[key]
	...
	_cache[key] = tex
	return tex
```

A `static var` is one shared slot for the whole program, so the cache persists
across scene changes — the evolution scene and the kitchen both request tier
sprites and only the first pays.

The key includes every parameter that changes the output. `"food:burger:128"`
and `"food:burger:64"` are different entries. Getting this wrong — keying on
`id` alone — would return a 128px texture when 64px was asked for.

## Colour

```gdscript
Color(0.91, 0.42, 0.19)          # RGB floats 0-1, alpha defaults to 1
Color(0, 0, 0, 0.85)             # RGBA
Color.WHITE                      # named constant
Color.from_string("#e8b83a", Color.WHITE)   # hex, with a fallback
color.darkened(0.35)             # toward black
color.lightened(0.30)            # toward white
a.lerp(b, t)                     # blend
```

Channels are **floats from 0 to 1**, not bytes. `Color(255, 0, 0)` is not red —
it is an out-of-range value that will over-brighten.

`Color.from_string()` is how the food colours travel from Rust. `defs.rs` stores
them as strings:

```rust
color: "#e8b83a",
```

and `food_button.gd` parses them:

```gdscript
_accent = Color.from_string(String(data.get("color", "#ffffff")), Color.WHITE)
```

The second argument is the fallback for an unparseable string, so a typo in
`defs.rs` produces a white card rather than a crash.

## Displaying a texture

```gdscript
_icon = TextureRect.new()
_icon.custom_minimum_size = Vector2(112, 112)
_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
```

`expand_mode` decides whether the texture's own size drives the node's minimum
size. `EXPAND_IGNORE_SIZE` says "do not let the texture dictate my size" — the
node is sized by the container and the image conforms.

`stretch_mode` decides how the image fills that rectangle:

- `STRETCH_KEEP_ASPECT_CENTERED` — fit inside, preserve aspect, centre. Used for
  icons and characters.
- `STRETCH_KEEP_ASPECT_COVERED` — fill entirely, preserve aspect, crop the
  overflow. Used for backgrounds, so a 320×180 placeholder covers a 1920×1080
  screen with no letterboxing.
- `STRETCH_SCALE` — distort to fit. Rarely what you want.

## Docs

- [Resources](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html)
- [Import process](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/import_process.html)
- [Image class](https://docs.godotengine.org/en/stable/classes/class_image.html)
- [TextureRect class](https://docs.godotengine.org/en/stable/classes/class_texturerect.html)

## Exercise

1. Add a `"donut"` shape to `_draw_food()` — a filled ring — and wire it to a new
   food. You will need a helper that draws a disc with a hole.
2. `PlaceholderArt.clear_cache()` exists but nothing calls it. Describe a
   situation where forgetting to call it produces a visible bug.

## Solution

**1.** Add the ring helper next to the other primitives:

```gdscript
static func _ring(img: Image, cx: float, cy: float, outer: float, inner: float,
		c: Color) -> void:
	var x0 := int(floorf(cx - outer))
	var x1 := int(ceilf(cx + outer))
	var y0 := int(floorf(cy - outer))
	var y1 := int(ceilf(cy + outer))
	for iy in range(y0, y1 + 1):
		for ix in range(x0, x1 + 1):
			var dx := float(ix) + 0.5 - cx
			var dy := float(iy) + 0.5 - cy
			var d2 := dx * dx + dy * dy
			if d2 <= outer * outer and d2 >= inner * inner:
				_px(img, ix, iy, c)
```

Comparing squared distances avoids two `sqrt()` calls per pixel.

Add the branch in `_draw_food()`'s `match`:

```gdscript
"donut":
	_ring(img, s * 0.5, s * 0.52, s * 0.36, s * 0.13, color)
	_ring(img, s * 0.5, s * 0.46, s * 0.34, s * 0.15, light)
	for i in 6:
		var angle := TAU * float(i) / 6.0
		_disc(img, s * 0.5 + cos(angle) * s * 0.24,
				s * 0.46 + sin(angle) * s * 0.24, s * 0.022,
				Color(1.0, 0.45, 0.65))
```

Register the shape:

```gdscript
static func _shape_for(id: String) -> String:
	match id:
		...
		"donut", "donut_box":
			return "donut"
```

Then add the food in `engine/src/clicker_game/defs.rs`:

```rust
FoodDef {
    id: "donut",
    name: "Donut",
    calories: 350.0,
    cooldown: 0.75,
    unlock_tier: 1,
    color: "#f2c14e",
},
```

Rebuild with `cargo build --workspace` and restart Godot. The card appears with
no GDScript UI changes at all — `_rebuild_food_cards()` loops over whatever
`SceneManager.foods()` returns.

**2.** The cache is keyed by `"char:2:384"` and similar, and it is `static`, so
it lives as long as the process. Anything that should change the *output* for an
unchanged key is a bug.

The concrete case: you are running the game from the editor, the tier-2 character
is a drawn placeholder, and you drop a real `nikacado_overweight_comp.png` into
`art/`. Godot imports it live. But `PlaceholderArt.character(2)` finds
`"char:2:384"` already in the cache and returns the old drawing. You would swear
the file was not picked up — restarting the editor "fixes" it, which is the
worst kind of bug because it teaches you the wrong lesson.

Calling `clear_cache()` after an import, or hooking it to a hot-reload signal,
solves it. The same class of problem appears if you ever make the drawing depend
on a setting the player can change — a colourblind palette, say. Any cache that
outlives its inputs needs an invalidation story.

---

Next: [08 — Tweens and animation](08-tweens.md)
