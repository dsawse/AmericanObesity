class_name Num
extends RefCounted

## Number formatting helpers shared by the HUD and the shop.
##
## Idle games run into absurd magnitudes quickly, so every number the player
## sees goes through [method fmt].

const SUFFIXES := [
	"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc",
]


## Compact notation: 1234 -> "1.23K", 5_600_000 -> "5.60M".
static func fmt(value: float) -> String:
	if not is_finite(value):
		return "∞"
	var sign_text := "-" if value < 0.0 else ""
	var n := absf(value)

	if n < 1000.0:
		if n < 10.0 and n != floorf(n):
			return "%s%.1f" % [sign_text, n]
		return "%s%d" % [sign_text, int(n)]

	var tier := 0
	while n >= 1000.0 and tier < SUFFIXES.size() - 1:
		n /= 1000.0
		tier += 1

	if n >= 100.0:
		return "%s%.0f%s" % [sign_text, n, SUFFIXES[tier]]
	elif n >= 10.0:
		return "%s%.1f%s" % [sign_text, n, SUFFIXES[tier]]
	return "%s%.2f%s" % [sign_text, n, SUFFIXES[tier]]


## Weight always reads with one decimal: "218.4 lbs".
static func weight(lbs: float) -> String:
	return "%.1f lbs" % lbs


## "2h 14m", "45s" — used by the offline-earnings popup.
static func duration(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	var hours := total / 3600
	var minutes := (total % 3600) / 60
	var secs := total % 60
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	if minutes > 0:
		return "%dm %ds" % [minutes, secs]
	return "%ds" % secs
