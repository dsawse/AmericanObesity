# 09 — Saving and loading

Saving is where hobby projects break. It is easy to write a save system that
works today and corrupts every player's progress the moment you add a feature.
This lesson covers the mechanics and, more importantly, the format design.

## `FileAccess`

```gdscript
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
```

Points worth extracting:

**`FileAccess.open()` returns `null` on failure.** It does not throw. Check it
every time — disk full, permissions, path in use.

**Diagnose failures properly.** `FileAccess.get_open_error()` returns the error
code and `error_string()` turns it into readable text. "Could not write
user://progress.save (Permission denied)" is actionable; "save failed" is not.

**Return a bool.** The caller decides what to do:

```gdscript
func _on_save_pressed() -> void:
	if SceneManager.save_game():
		_toasts.push("Saved", "Progress written to disk.", UiTheme.GOOD)
	else:
		_toasts.push("Save failed", "Check the output log for details.",
			Color(0.9, 0.4, 0.4))
```

Silent failure is the worst outcome. The player deserves to know.

Loading is the mirror image:

```gdscript
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
```

Note the layering. "No save exists" is a normal first-run outcome and returns
quietly. "Save exists but cannot be opened" is a warning. "Save opened but is
garbage" is a warning *and* leaves the in-memory state untouched — the Rust
`from_json()` only commits after parsing succeeds.

## `user://` and where it actually goes

Saves must go to `user://`. `res://` is read-only in an exported game.

On Windows `user://` resolves to
`%APPDATA%\Godot\app_userdata\amerobe\`. To open it from the editor:
**Project → Open User Data Folder**.

To convert for something that needs a real OS path:

```gdscript
DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
```

That is from `hard_reset()`. Most Godot APIs take `user://` directly; the ones
that shell out to the OS need `globalize_path()`.

## When to save

```gdscript
const AUTOSAVE_INTERVAL := 20.0
```

Four triggers in this project:

1. **Every 20 seconds** via the accumulator in `_process()`.
2. **On window close** — `NOTIFICATION_WM_CLOSE_REQUEST`.
3. **On leaving to the menu** — `_on_menu_pressed()`.
4. **Manually** — the Save button.

Plus `finish_evolution()` saves right after a tier-up, because that is the most
painful moment to lose.

Twenty seconds is a reasonable idle-game compromise. Saving every frame would
thrash the disk; saving only on quit loses everything to a crash.

## Format design: the part that matters

The mechanics above are easy. This is the part that decides whether your game
survives its own updates.

The save is produced by serde in `engine/src/clicker_game/state.rs`:

```rust
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SaveState {
    #[serde(default)]
    pub version: String,
    #[serde(default)]
    pub lifetime_calories: f64,
    #[serde(default)]
    pub calorie_bank: f64,
    #[serde(default)]
    pub total_clicks: u64,
    #[serde(default = "one")]
    pub tier: u32,
    #[serde(default)]
    pub upgrades: BTreeMap<String, u32>,
    #[serde(default)]
    pub food_clicks: BTreeMap<String, u64>,
    #[serde(default)]
    pub achievements: Vec<String>,
    #[serde(default)]
    pub last_seen_unix: f64,
}
```

Four decisions, each solving a specific failure mode.

### 1. Every field has a default

`#[serde(default)]` means a missing key is filled in rather than failing.

Add `prestige_level` in a future version and yesterday's save still loads —
`prestige_level` gets `0`. Without the attribute, every existing save becomes
unreadable the day you add a field. This is *the* classic save-system bug.

`tier` uses `#[serde(default = "one")]` because its sensible default is 1, not 0.

### 2. Maps keyed by string id, not arrays by index

```rust
pub upgrades: BTreeMap<String, u32>,
```

A save looks like `{"microwave": 5, "grubhub": 2}`, not `[5, 0, 2, 0, ...]`.

With an array, inserting a new upgrade in the middle of `UPGRADES` shifts every
index and silently converts everyone's microwaves into roommates. With a map,
order is irrelevant and additions are free.

### 3. Unknown ids are dropped, not fatal

```rust
save.upgrades.retain(|id, _| defs::upgrade(id).is_some());
save.food_clicks.retain(|id, _| defs::food(id).is_some());
save.achievements
    .retain(|id| ACHIEVEMENTS.iter().any(|a| a.id == *id));
```

Remove an upgrade from the game and old saves referencing it load fine — the
stale entry is discarded. The alternative is either a crash or a phantom upgrade
contributing to `cps()` forever.

### 4. Hostile input is clamped

```rust
save.tier = save.tier.clamp(1, MAX_TIER);
if !save.lifetime_calories.is_finite() || save.lifetime_calories < 0.0 {
    save.lifetime_calories = 0.0;
}
```

The save is plain JSON in a folder the player can open. Someone will edit it.
`is_finite()` is the important one — JSON can carry values that parse to
infinity or NaN, and NaN propagates through every subsequent calculation,
producing a permanently broken run that no amount of playing repairs.

Clamping does not stop cheating. It stops *corruption*. Those are different
problems and only the second is your responsibility in a single-player game.

### Atomicity, and what this project does not do

One thing missing: if the process dies partway through `store_string()`, the
save is truncated. The standard fix is to write to a temp file and rename, since
rename is atomic on every mainstream filesystem:

```gdscript
var tmp := SAVE_PATH + ".tmp"
var file := FileAccess.open(tmp, FileAccess.WRITE)
if file == null:
	return false
file.store_string(json)
file.close()
DirAccess.rename_absolute(
	ProjectSettings.globalize_path(tmp),
	ProjectSettings.globalize_path(SAVE_PATH))
```

Worth adding if you ever ship this.

## Offline progress

Real elapsed time comes from the system clock:

```gdscript
static func _now() -> float:
	return Time.get_unix_time_from_system()
```

`last_seen_unix` is stamped on every save. On load, Rust computes the gap:

```rust
pub fn apply_offline(&mut self, now_unix: f64) -> f64 {
    let last = self.save.last_seen_unix;
    self.save.last_seen_unix = now_unix;

    if last <= 0.0 || now_unix <= last {
        return 0.0;
    }
    let elapsed = (now_unix - last).min(OFFLINE_CAP_SECONDS);
    if elapsed < 60.0 {
        return 0.0;
    }
    ...
}
```

Three guards on a clock you do not control:

- `last <= 0.0` — a fresh run has never been saved, so there is no gap.
- `now_unix <= last` — **time went backwards.** Either the player set their clock
  back to farm offline earnings, or they crossed a DST boundary, or their clock
  synced. Awarding nothing is the safe response.
- `.min(OFFLINE_CAP_SECONDS)` — eight hours maximum, so leaving for a month does
  not trivialise the game.

The under-a-minute check just avoids a pointless popup on a quick restart.

Note that `Time.get_unix_time_from_system()` is wall-clock and therefore
manipulable. `Time.get_ticks_msec()` is monotonic but resets when the process
does, so it cannot measure time while the game is closed. For a single-player
idle game, wall-clock plus a cap is the standard trade.

## Docs

- [Saving games](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html)
- [FileAccess](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html)
- [Data paths](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html)
- [JSON class](https://docs.godotengine.org/en/stable/classes/class_json.html)

## Exercise

1. Add a rolling backup: before overwriting the save, copy the existing one to
   `user://progress.save.bak`. If the main save fails to parse, fall back to the
   backup automatically.
2. You add `pub prestige_level: u32` to `SaveState` **without** `#[serde(default)]`.
   Exactly what does a player with an existing save experience, and at which line
   does it go wrong?

## Solution

**1.** In `scene_manager.gd`, add the path and rotate before writing:

```gdscript
const BACKUP_PATH := "user://progress.save.bak"
```

```gdscript
func save_game() -> bool:
	if not engine_available:
		return false

	var json: String = game.save_json(_now())

	# Rotate the previous save out before overwriting it.
	if FileAccess.file_exists(SAVE_PATH):
		var previous := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if previous != null:
			var old_text := previous.get_as_text()
			previous.close()
			var backup := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
			if backup != null:
				backup.store_string(old_text)
				backup.close()

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	...
```

Then teach `load_game()` to fall back:

```gdscript
func load_game() -> bool:
	if not engine_available:
		return false
	if _load_from(SAVE_PATH):
		return true
	if _load_from(BACKUP_PATH):
		push_warning("SceneManager: main save was unusable; restored the backup.")
		return true
	return false


func _load_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	return game.load_json(text)
```

This works precisely because `from_json()` on the Rust side does not mutate state
on failure. A destructive parser would leave the game half-loaded and the
fallback would restore into wreckage.

Also update `has_save()` and `hard_reset()` to account for the backup, or
"New Game" will leave a `.bak` that a later failure could resurrect.

**2.** The player launches, sees a title screen with **no Continue button**, and
their run is gone.

The chain: `serde_json::from_str::<SaveState>(json)` fails, because the JSON has
no `prestige_level` key and there is no default. `from_json()` hits its `Err(_)`
arm and returns `false`. `load_game()` logs "save file was unreadable; starting a
fresh run" and returns `false`.

The state is not corrupted — `from_json()` never touched it — so the game starts
a clean run at 150 lbs. The file on disk is still intact at that point, which
means it is recoverable if you notice fast. But the first autosave twenty seconds
later overwrites it with the fresh run, and then it really is gone.

That twenty-second window between "silently discarded your save" and
"permanently destroyed your save" is why `#[serde(default)]` on every field is
not a style preference. It is the difference between a shipped update and an
apology.

---

Next: [10 — The Rust layer](10-rust-gdextension.md)
