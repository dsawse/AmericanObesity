extends Node

## Autoloaded singleton (`SceneManager`).
##
## Owns the one and only [code]ClickerGame[/code] instance from the Rust
## GDExtension, drives the simulation every frame regardless of which scene is
## on screen, translates the engine's event queue into Godot signals, and
## handles saving, loading and scene transitions.
##
## The UI never talks to the extension directly — it goes through here.

# --- Signals ---------------------------------------------------------------

signal tier_up(tier: int)
signal achievement_unlocked(id: String, title: String, description: String)
signal food_unlocked(id: String, food_name: String)
signal offline_earnings(seconds: float, calories: float)
signal game_saved()
signal game_reset()

# --- Configuration ---------------------------------------------------------

const SCENES := {
	"title": "res://Scenes/title_screen.tscn",
	"main": "res://Scenes/main.tscn",
	"evolution": "res://Scenes/evolution.tscn",
}

const SAVE_PATH := "user://progress.save"
const AUTOSAVE_INTERVAL := 20.0

const ENGINE_MISSING_HINT := \
	"The 'engine' GDExtension is not loaded, so there is no game simulation.\n" + \
	"Build it first:  cargo build --workspace\n" + \
	"(or run build-windows-debug.ps1 / build-linux-debug.sh from the repo root)"

# --- State -----------------------------------------------------------------

## The Rust `ClickerGame` object, or `null` if the extension failed to load.
var game: RefCounted = null

## False when the GDExtension is missing; every screen degrades gracefully.
var engine_available := false
var engine_error := ""

## Tier the evolution cutscene should present. Set just before transitioning.
var pending_tier := 1

## Events produced before any scene was listening. Drained by the first screen
## that comes up, so offline earnings and achievements are never swallowed.
var startup_events: Array = []

var _autosave_accum := 0.0
var _changing_scene := false


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_game()
	if not engine_available:
		return

	load_game()
	game.apply_offline(_now())
	startup_events = _pop_events()


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


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		save_game()


func _create_game() -> void:
	if not ClassDB.class_exists("ClickerGame"):
		engine_available = false
		engine_error = ENGINE_MISSING_HINT
		push_error(engine_error)
		return

	var instance: Object = ClassDB.instantiate("ClickerGame")
	if instance == null:
		engine_available = false
		engine_error = "ClickerGame is registered but could not be instantiated."
		push_error(engine_error)
		return

	game = instance as RefCounted
	engine_available = game != null
	if not engine_available:
		engine_error = "ClickerGame did not resolve to a RefCounted object."
		push_error(engine_error)


# ---------------------------------------------------------------------------
# Simulation pass-throughs
# ---------------------------------------------------------------------------

## Eats a food item. Returns calories gained; 0.0 means the click was refused
## (item locked, or still on cooldown).
func click_food(id: String) -> float:
	if not engine_available:
		return 0.0
	return game.click_food(id)


func buy_upgrade(id: String) -> bool:
	if not engine_available:
		return false
	return game.buy_upgrade(id)


func buy_upgrade_bulk(id: String, count: int) -> int:
	if not engine_available:
		return 0
	return game.buy_upgrade_bulk(id, count)


func affordable_levels(id: String, count: int) -> int:
	if not engine_available:
		return 0
	return game.affordable_levels(id, count)


func cooldown_remaining(id: String) -> float:
	if not engine_available:
		return 0.0
	return game.cooldown_remaining(id)


func weight_lbs() -> float:
	if not engine_available:
		return 0.0
	return game.weight_lbs()


func tier() -> int:
	if not engine_available:
		return 1
	return game.tier()


# ---------------------------------------------------------------------------
# JSON views
# ---------------------------------------------------------------------------

func snapshot() -> Dictionary:
	if not engine_available:
		return {}
	return _parse_dict(game.snapshot_json())


func foods() -> Array:
	if not engine_available:
		return []
	return _parse_array(game.foods_json())


func upgrades() -> Array:
	if not engine_available:
		return []
	return _parse_array(game.upgrades_json())


func achievements() -> Array:
	if not engine_available:
		return []
	return _parse_array(game.achievements_json())


static func _parse_dict(json: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(json)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func _parse_array(json: String) -> Array:
	var parsed: Variant = JSON.parse_string(json)
	return parsed if typeof(parsed) == TYPE_ARRAY else []


# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------

func _pop_events() -> Array:
	if not engine_available:
		return []
	return _parse_array(game.drain_events_json())


## Replays anything that happened before the current scene existed.
func consume_startup_events() -> Array:
	var events := startup_events
	startup_events = []
	return events


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
		"food_unlocked":
			food_unlocked.emit(
				String(event.get("id", "")),
				String(event.get("name", "")))
		"offline_earnings":
			offline_earnings.emit(
				float(event.get("seconds", 0.0)),
				float(event.get("calories", 0.0)))


# ---------------------------------------------------------------------------
# Scene transitions
# ---------------------------------------------------------------------------

func go_to_title() -> void:
	_change_scene("title")


func go_to_main() -> void:
	_change_scene("main")


func go_to_evolution() -> void:
	_change_scene("evolution")


## Called by the evolution cutscene when its animation finishes.
func finish_evolution() -> void:
	save_game()
	go_to_main()


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
	# change_scene_to_file swaps at the end of the frame; wait it out before
	# accepting another request so a burst of events cannot double-transition.
	await get_tree().process_frame
	await get_tree().process_frame
	_changing_scene = false


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func save_game() -> bool:
	if not engine_available:
		return false

	var json: String = game.save_json(_now())
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SceneManager: could not write %s (%s)"
			% [SAVE_PATH, error_string(FileAccess.get_open_error())])
		return false

	file.store_string(json)
	file.close()
	game_saved.emit()
	return true


func load_game() -> bool:
	if not engine_available:
		return false
	if not FileAccess.file_exists(SAVE_PATH):
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("SceneManager: could not read %s" % SAVE_PATH)
		return false

	var text := file.get_as_text()
	file.close()

	if not game.load_json(text):
		push_warning("SceneManager: save file was unreadable; starting a fresh run.")
		return false
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Wipes progress and returns to the title screen.
func hard_reset() -> void:
	if engine_available:
		game.reset()
		game.mark_seen(_now())
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	startup_events = []
	pending_tier = 1
	game_reset.emit()
	go_to_title()


static func _now() -> float:
	return Time.get_unix_time_from_system()
