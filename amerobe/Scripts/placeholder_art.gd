class_name PlaceholderArt
extends RefCounted

## Procedural stand-in artwork.
##
## Several source PNGs referenced by the original project were never committed
## (`.gitignore` had `/art/*.png`), which left the scenes pointing at textures
## that do not exist. Rather than ship a broken build, every sprite goes through
## [method texture_for_food] / [method character] / [method backdrop], which
## load the real file when it is present and draw a readable placeholder when it
## is not. Drop a real PNG at the expected path and it takes over automatically.

static var _cache: Dictionary = {}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Real art if `res://art/<id>.png` exists, otherwise a drawn placeholder.
static func texture_for_food(id: String, color: Color, size: int = 128) -> Texture2D:
	var key := "food:%s:%d" % [id, size]
	if _cache.has(key):
		return _cache[key]

	var tex := _try_load("res://art/%s.png" % id)
	if tex == null:
		tex = _draw_food(id, color, size)
	_cache[key] = tex
	return tex


## Character silhouette for a progression tier (1..3).
static func character(tier: int, size: int = 384) -> Texture2D:
	var key := "char:%d:%d" % [tier, size]
	if _cache.has(key):
		return _cache[key]

	# Five character states, per the design document: Base, Chunky, Heavy,
	# Massive, Ultimate. Only the first three have (partially committed) art.
	var names := {
		1: "res://art/nikacado_skinny_comp.png",
		2: "res://art/nikacado_overweight_comp.png",
		3: "res://art/nikacado_obese_comp_nbg.png",
		4: "res://art/character_massive.png",
		5: "res://art/character_ultimate.png",
	}
	var tex := _try_load(names.get(tier, ""))
	if tex == null:
		tex = _draw_character(tier, size)
	_cache[key] = tex
	return tex


## Kitchen backdrop for a tier.
static func backdrop(tier: int, width: int = 320, height: int = 180) -> Texture2D:
	var key := "bg:%d" % tier
	if _cache.has(key):
		return _cache[key]

	var tex := _try_load("res://art/kitchen_background_8bit.png")
	if tex == null:
		tex = _try_load("res://art/Kitchen Pixel Art.png")
	if tex == null:
		tex = _draw_backdrop(tier, width, height)
	_cache[key] = tex
	return tex


## Title-screen art.
static func title_art(width: int = 320, height: int = 180) -> Texture2D:
	var key := "title"
	if _cache.has(key):
		return _cache[key]
	var tex := _try_load("res://art/start_screen.png")
	if tex == null:
		tex = _draw_backdrop(1, width, height)
	_cache[key] = tex
	return tex


static func clear_cache() -> void:
	_cache.clear()


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

static func _try_load(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		return null
	var res := ResourceLoader.load(path)
	return res as Texture2D


# ---------------------------------------------------------------------------
# Drawing primitives
# ---------------------------------------------------------------------------

static func _blank(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


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
		(c.g * c.a + under.g * under.a * (1.0 - c.a)) / a,
		(c.b * c.a + under.b * under.a * (1.0 - c.a)) / a,
		a))


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for iy in range(y, y + h):
		for ix in range(x, x + w):
			_px(img, ix, iy, c)


static func _round_rect(img: Image, x: int, y: int, w: int, h: int, r: int, c: Color) -> void:
	for iy in range(y, y + h):
		for ix in range(x, x + w):
			var dx := 0
			var dy := 0
			if ix < x + r:
				dx = x + r - ix
			elif ix > x + w - 1 - r:
				dx = ix - (x + w - 1 - r)
			if iy < y + r:
				dy = y + r - iy
			elif iy > y + h - 1 - r:
				dy = iy - (y + h - 1 - r)
			if dx * dx + dy * dy <= r * r:
				_px(img, ix, iy, c)


static func _disc(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	var x0 := int(floorf(cx - r))
	var x1 := int(ceilf(cx + r))
	var y0 := int(floorf(cy - r))
	var y1 := int(ceilf(cy + r))
	for iy in range(y0, y1 + 1):
		for ix in range(x0, x1 + 1):
			var dx := float(ix) + 0.5 - cx
			var dy := float(iy) + 0.5 - cy
			if dx * dx + dy * dy <= r * r:
				_px(img, ix, iy, c)


static func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	for iy in range(int(floorf(cy - ry)), int(ceilf(cy + ry)) + 1):
		for ix in range(int(floorf(cx - rx)), int(ceilf(cx + rx)) + 1):
			var dx := (float(ix) + 0.5 - cx) / rx
			var dy := (float(iy) + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_px(img, ix, iy, c)


## Vertically-tapered box: `top_w` wide at `y`, `bottom_w` wide at `y + h`.
static func _taper(img: Image, cx: float, y: int, h: int, top_w: float,
		bottom_w: float, c: Color) -> void:
	for iy in range(y, y + h):
		var t := 0.0 if h <= 1 else float(iy - y) / float(h - 1)
		var half := lerpf(top_w, bottom_w, t) * 0.5
		for ix in range(int(cx - half), int(cx + half) + 1):
			_px(img, ix, iy, c)


static func _tex(img: Image) -> Texture2D:
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# Food placeholders
# ---------------------------------------------------------------------------

static func _draw_food(id: String, color: Color, size: int) -> Texture2D:
	var img := _blank(size, size)
	var s := float(size)
	var dark := color.darkened(0.35)
	var light := color.lightened(0.30)

	match _shape_for(id):
		"fries":
			# Carton of fries.
			var stick_w := int(s * 0.07)
			var xs := [0.30, 0.42, 0.54, 0.66]
			for i in xs.size():
				var sx := int(s * xs[i])
				var top := int(s * (0.16 + 0.05 * (i % 2)))
				_rect(img, sx, top, stick_w, int(s * 0.55), light if i % 2 == 0 else color)
			_taper(img, s * 0.5, int(s * 0.46), int(s * 0.42), s * 0.62, s * 0.46, dark)
			_rect(img, int(s * 0.22), int(s * 0.52), int(s * 0.56), int(s * 0.07),
					dark.lightened(0.25))
		"cup":
			# Soda cup with a lid and a straw.
			_taper(img, s * 0.5, int(s * 0.24), int(s * 0.62), s * 0.56, s * 0.40, color)
			_rect(img, int(s * 0.20), int(s * 0.20), int(s * 0.60), int(s * 0.08),
					light)
			_rect(img, int(s * 0.55), int(s * 0.04), int(s * 0.07), int(s * 0.20), dark)
			_taper(img, s * 0.5, int(s * 0.40), int(s * 0.10), s * 0.50, s * 0.48,
					Color(1, 1, 1, 0.18))
		"burger":
			# Bun, patty, bun.
			_ellipse(img, s * 0.5, s * 0.34, s * 0.36, s * 0.20, light)
			_rect(img, int(s * 0.14), int(s * 0.40), int(s * 0.72), int(s * 0.09),
					Color(0.42, 0.68, 0.30))
			_rect(img, int(s * 0.13), int(s * 0.48), int(s * 0.74), int(s * 0.12), dark)
			_rect(img, int(s * 0.15), int(s * 0.59), int(s * 0.70), int(s * 0.07),
					Color(0.95, 0.78, 0.28))
			_ellipse(img, s * 0.5, s * 0.72, s * 0.35, s * 0.13, color)
			# Sesame seeds.
			for i in 5:
				_disc(img, s * (0.28 + 0.11 * i), s * (0.28 + 0.03 * (i % 2)),
						s * 0.02, Color(1, 0.95, 0.80))
		"stick":
			# Something battered, on a stick.
			_rect(img, int(s * 0.47), int(s * 0.55), int(s * 0.06), int(s * 0.40),
					Color(0.72, 0.55, 0.33))
			_round_rect(img, int(s * 0.30), int(s * 0.12), int(s * 0.40),
					int(s * 0.50), int(s * 0.16), color)
			_round_rect(img, int(s * 0.35), int(s * 0.17), int(s * 0.16),
					int(s * 0.18), int(s * 0.07), light)
		"bucket":
			_taper(img, s * 0.5, int(s * 0.28), int(s * 0.56), s * 0.66, s * 0.44, color)
			_rect(img, int(s * 0.15), int(s * 0.24), int(s * 0.70), int(s * 0.08), light)
			_rect(img, int(s * 0.28), int(s * 0.44), int(s * 0.44), int(s * 0.12),
					Color(1, 1, 1, 0.85))
			_rect(img, int(s * 0.28), int(s * 0.44), int(s * 0.44), int(s * 0.04), dark)
		"cake":
			_rect(img, int(s * 0.12), int(s * 0.40), int(s * 0.76), int(s * 0.38), color)
			_rect(img, int(s * 0.12), int(s * 0.32), int(s * 0.76), int(s * 0.10), light)
			for i in 4:
				_rect(img, int(s * (0.22 + 0.18 * i)), int(s * 0.16), int(s * 0.04),
						int(s * 0.16), Color(0.98, 0.98, 0.92))
				_disc(img, s * (0.22 + 0.18 * i) + s * 0.02, s * 0.14, s * 0.035,
						Color(1.0, 0.72, 0.20))
		"pizza":
			# Whole pie with a slice lifted out.
			_disc(img, s * 0.5, s * 0.55, s * 0.38, light.darkened(0.15))
			_disc(img, s * 0.5, s * 0.55, s * 0.33, color)
			for i in 7:
				var a := TAU * float(i) / 7.0 + 0.4
				_disc(img, s * 0.5 + cos(a) * s * 0.19,
						s * 0.55 + sin(a) * s * 0.19, s * 0.035,
						Color(0.78, 0.18, 0.18))
			# A wedge missing from the top-right.
			for iy in range(int(s * 0.16), int(s * 0.56)):
				for ix in range(int(s * 0.5), int(s * 0.92)):
					var dx := float(ix) - s * 0.5
					var dy := s * 0.55 - float(iy)
					if dy > 0.0 and dx > 0.0 and dy < dx * 1.6 and dy > dx * 0.35:
						_px(img, ix, iy, Color(0, 0, 0, 0))
		"cone":
			# Scoops on a waffle cone.
			_taper(img, s * 0.5, int(s * 0.52), int(s * 0.44), s * 0.34, s * 0.04,
					Color(0.80, 0.60, 0.32))
			_disc(img, s * 0.42, s * 0.40, s * 0.16, color)
			_disc(img, s * 0.60, s * 0.42, s * 0.15, light)
			_disc(img, s * 0.51, s * 0.28, s * 0.15, color.lightened(0.15))
			_disc(img, s * 0.51, s * 0.16, s * 0.045, Color(0.85, 0.15, 0.25))
		_:
			# Generic blob.
			_disc(img, s * 0.5, s * 0.52, s * 0.36, color)
			_disc(img, s * 0.38, s * 0.38, s * 0.10, Color(1, 1, 1, 0.25))

	return _tex(img)


static func _shape_for(id: String) -> String:
	match id:
		"fries", "loaded_nachos":
			return "fries"
		"soda", "mega_shake", "gravy_fountain":
			return "cup"
		"burger", "triple_burger":
			return "burger"
		"fried_butter", "fried_chicken":
			return "stick"
		"family_bucket", "entire_buffet":
			return "bucket"
		"sheet_cake":
			return "cake"
		"pizza":
			return "pizza"
		"ice_cream":
			return "cone"
	return "blob"


# ---------------------------------------------------------------------------
# Character placeholder
# ---------------------------------------------------------------------------

static func _draw_character(tier: int, size: int) -> Texture2D:
	var img := _blank(size, size)
	var s := float(size)
	# `t` runs 0 -> 1 across the five tiers and drives every proportion below,
	# so adding a tier needs no new drawing code.
	var t := clampf(float(tier - 1) / 4.0, 0.0, 1.0)

	var skin := Color(0.92, 0.75, 0.60)
	var shirt := Color(0.30, 0.45, 0.72).lerp(Color(0.68, 0.28, 0.26), t)
	var shadow := shirt.darkened(0.30)

	var body_rx := lerpf(s * 0.15, s * 0.44, t)
	var body_ry := lerpf(s * 0.23, s * 0.33, t)
	var body_cy := s * 0.62
	var head_r := lerpf(s * 0.11, s * 0.16, t)
	var head_cy := body_cy - body_ry - head_r * 0.55

	# Ground shadow.
	_ellipse(img, s * 0.5, s * 0.92, body_rx * 1.05, s * 0.035, Color(0, 0, 0, 0.30))
	# Legs.
	var leg_w := lerpf(s * 0.09, s * 0.16, t)
	_round_rect(img, int(s * 0.5 - body_rx * 0.55 - leg_w * 0.5),
			int(body_cy + body_ry * 0.7), int(leg_w), int(s * 0.20),
			int(leg_w * 0.4), shirt.darkened(0.45))
	_round_rect(img, int(s * 0.5 + body_rx * 0.55 - leg_w * 0.5),
			int(body_cy + body_ry * 0.7), int(leg_w), int(s * 0.20),
			int(leg_w * 0.4), shirt.darkened(0.45))
	# Torso.
	_ellipse(img, s * 0.5, body_cy, body_rx, body_ry, shirt)
	_ellipse(img, s * 0.5, body_cy + body_ry * 0.35, body_rx * 0.86,
			body_ry * 0.45, shadow)
	# Arms.
	_ellipse(img, s * 0.5 - body_rx * 0.95, body_cy - body_ry * 0.1,
			body_rx * 0.24, body_ry * 0.55, shirt.lightened(0.06))
	_ellipse(img, s * 0.5 + body_rx * 0.95, body_cy - body_ry * 0.1,
			body_rx * 0.24, body_ry * 0.55, shirt.lightened(0.06))
	# Neck + head + chins.
	_rect(img, int(s * 0.5 - head_r * 0.35), int(head_cy), int(head_r * 0.7),
			int(head_r * 1.4), skin.darkened(0.10))
	_disc(img, s * 0.5, head_cy, head_r, skin)
	# One extra chin per tier.
	for chin in range(1, mini(tier, 5)):
		_ellipse(img, s * 0.5, head_cy + head_r * (0.55 + 0.33 * float(chin)),
				head_r * (0.70 + 0.08 * float(chin)),
				head_r * 0.32, skin.darkened(0.05 * float(chin)))
	# Face.
	_disc(img, s * 0.5 - head_r * 0.35, head_cy - head_r * 0.12, head_r * 0.10,
			Color(0.10, 0.09, 0.09))
	_disc(img, s * 0.5 + head_r * 0.35, head_cy - head_r * 0.12, head_r * 0.10,
			Color(0.10, 0.09, 0.09))
	_ellipse(img, s * 0.5, head_cy + head_r * 0.35, head_r * 0.30,
			head_r * lerpf(0.08, 0.20, t), Color(0.35, 0.16, 0.16))

	return _tex(img)


# ---------------------------------------------------------------------------
# Backdrop placeholder
# ---------------------------------------------------------------------------

static func _draw_backdrop(tier: int, w: int, h: int) -> Texture2D:
	var img := _blank(w, h)
	var top := Color(0.18, 0.15, 0.22).lerp(Color(0.30, 0.13, 0.13),
			clampf(float(tier - 1) / 4.0, 0.0, 1.0))
	var bottom := Color(0.09, 0.08, 0.11)

	for y in h:
		var c := top.lerp(bottom, float(y) / float(h))
		_rect(img, 0, y, w, 1, c)

	# Counter line and a checkered floor to give the scene a horizon.
	var horizon := int(h * 0.66)
	_rect(img, 0, horizon, w, 2, Color(0.35, 0.30, 0.28))
	var tile := maxi(8, int(w / 24.0))
	for y in range(horizon + 2, h):
		for x in range(0, w, tile):
			var shade := 0.06 if ((x / tile) + (y / tile)) % 2 == 0 else 0.0
			_rect(img, x, y, tile, 1, Color(1, 1, 1, shade))

	# Cabinet blocks along the back wall.
	var cab_h := int(h * 0.16)
	for x in range(0, w, int(w / 6.0)):
		_rect(img, x + 2, horizon - cab_h, int(w / 6.0) - 4, cab_h,
				Color(0.22, 0.19, 0.20, 0.85))
		_rect(img, x + 2, horizon - cab_h, int(w / 6.0) - 4, 2,
				Color(0.40, 0.35, 0.33, 0.9))

	return _tex(img)
