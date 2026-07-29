# 10 — The Rust layer

Godot lets you write engine-level code in a compiled language and register it as
if it were built in. That mechanism is **GDExtension**, and
[godot-rust](https://godot-rust.github.io/book/) is the Rust binding for it.

Your `ClickerGame` class is written in Rust. GDScript uses it exactly like a
built-in type.

## What GDExtension is

A shared library — `.dll` on Windows, `.so` on Linux, `.dylib` on macOS — that
Godot loads at startup. It registers classes into `ClassDB`, the same registry
that holds `Node` and `Label`. From GDScript's side there is no seam.

This is not the same as building a custom engine. You are not modifying Godot;
you are adding to it through a stable C API. Your extension keeps working across
Godot patch releases.

## The manifest

`amerobe/engine.gdextension` tells Godot what to load:

```ini
[configuration]
entry_symbol = "engine_init"
compatibility_minimum = 4.1
reloadable = false

[libraries]
windows.debug.x86_64 = "res://../target/debug/engine.dll"
windows.release.x86_64 = "res://../target/release/engine.dll"
linux.debug.x86_64 = "res://../target/debug/libengine.so"
...
```

- **`entry_symbol`** — the exported C function Godot calls. It must match the
  Rust side exactly.
- **`compatibility_minimum`** — the oldest Godot that may load this.
- **`reloadable`** — whether the editor can hot-reload it. `false` means you
  restart Godot after each build.
- **`[libraries]`** — one path per platform/build combination.

Those paths were the bug that cost you an evening. They originally read
`res://../engine/target/debug/engine.dll`. But `res://` is `amerobe/`, and the
root `Cargo.toml` declares a **workspace**:

```toml
[workspace]
members = ["engine"]
```

Cargo puts every workspace member's output in the *workspace root's* `target/`,
not the member's. So the DLL lands at `<repo>/target/debug/engine.dll` and the
manifest was pointing at `<repo>/engine/target/debug/engine.dll`, which never
existed. Godot reported "GDExtension dynamic library not found" and the class was
simply absent.

The lesson generalises: **when an extension will not load, verify the path
resolution before you suspect your code.** `res://` is the project folder, not
the repository root.

## The Rust entry point

`engine/src/lib.rs`:

```rust
#[gdextension(entry_symbol = engine_init)]
unsafe impl ExtensionLibrary for engine::Engine {
    fn on_level_init(level: InitLevel) {
        raw_engine_init::initialization_check(level);
        println!("[engine]::on_level_init() called");
    }
    ...
}
```

The macro generates the `extern "C"` function named in the manifest. Godot calls
`on_level_init` several times as it brings subsystems up — `Core`, `Servers`,
`Scene`, `Editor` — which is why the guard filters to one level.

Everything with `#[derive(GodotClass)]` anywhere in the crate is registered
automatically. There is no manual list.

## Defining a class

`engine/src/clicker_game/game.rs`:

```rust
#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct ClickerGame {
    game: Game,
}
```

- **`base = RefCounted`** — the Godot class to inherit. `RefCounted` is
  reference-counted and freed automatically, which suits a plain data object.
  Use `Node` if it needs to live in the scene tree.
- **`init`** — generate a default constructor, so GDScript can create one. Every
  field must implement `Default`.

Methods are exposed with `#[func]` inside a `#[godot_api]` block:

```rust
#[godot_api]
impl ClickerGame {
    #[func]
    fn click_food(&mut self, id: GString) -> f64 {
        self.game.click_food(&id.to_string())
    }
}
```

`GString` is Godot's string type; `String` is Rust's. Convert at the boundary.

## Instancing it from GDScript

Normally you would write `ClickerGame.new()`. This project deliberately does not:

```gdscript
if not ClassDB.class_exists("ClickerGame"):
	engine_available = false
	engine_error = ENGINE_MISSING_HINT
	push_error(engine_error)
	return

var instance: Object = ClassDB.instantiate("ClickerGame")
```

Because `ClickerGame.new()` is resolved when GDScript *compiles the file*. If the
DLL is missing the whole script fails to parse, and you get a cascade of
unrelated errors instead of the real one. `ClassDB` looks the name up at runtime,
so the script always loads and can report the actual problem.

This is why you saw a clear red banner rather than a wall of parse errors.

## The interface design: scalars in, JSON out

The most important decision in this project, and the one worth stealing.

Nothing crosses the boundary except numbers, booleans and strings:

```rust
#[func] fn tick(&mut self, delta: f64) -> f64
#[func] fn click_food(&mut self, id: GString) -> f64
#[func] fn buy_upgrade(&mut self, id: GString) -> bool
#[func] fn snapshot_json(&self) -> GString
#[func] fn upgrades_json(&self) -> GString
#[func] fn drain_events_json(&mut self) -> GString
```

No `Dictionary`, no `Array`, no signals from Rust.

**Why.** Godot's `Dictionary` and `Array` APIs have churned across godot-rust
versions — `push()` taking a value versus a reference, `set()` argument
conventions, typed-array ergonomics. `GString` and `f64` have not. A binding
built only from those keeps compiling as the crate moves. That mattered here
because this code was written without the ability to compile it, but it matters
generally: it is the difference between a version bump being a one-line change
and an afternoon.

**The cost.** Every `snapshot_json()` call serialises with serde and parses with
Godot's `JSON`. At 60fps that is 60 round-trips a second.

**Why it is fine here.** The snapshot is about fifteen fields. That is
microseconds. And the shop, which produces a larger payload, refreshes at
`SHOP_REFRESH_INTERVAL = 0.15` rather than every frame — because it does not
need to be smoother than that.

For a bullet-hell passing thousands of positions per frame, this design would be
wrong; you would use `PackedVector2Array` and eat the API churn. Match the
interface to the data rate.

## Three-layer structure

```
engine/src/clicker_game/
├── defs.rs     content tables — no logic
├── state.rs    the simulation — no Godot types at all
└── game.rs     the binding — no game logic
```

`state.rs` importing nothing from `godot` is the valuable part. It means the
simulation is testable with plain `cargo test`, no engine, no window:

```bash
cargo test -p engine
```

Eleven tests run in milliseconds:

```rust
#[test]
fn click_grants_calories_and_starts_cooldown() {
    let mut g = Game::new();
    let gained = g.click_food("fries");
    assert_eq!(gained, 25.0);
    assert_eq!(g.save.total_clicks, 1);
    assert_eq!(g.click_food("fries"), 0.0);   // still cooling down
    g.tick(0.5);
    assert_eq!(g.click_food("fries"), 25.0);
}
```

```rust
#[test]
fn corrupt_save_is_rejected_without_wiping_state() {
    let mut g = Game::new();
    g.click_food("fries");
    let before = g.save.lifetime_calories;
    assert!(!g.from_json("{ this is not json"));
    assert_eq!(g.save.lifetime_calories, before);
}
```

That second test encodes the guarantee lesson 09's backup exercise depends on.
Testing it through the engine would mean launching Godot, faking a save file and
inspecting the UI. Keeping Godot out of `state.rs` is what makes it a three-line
test.

**This is the transferable idea, and it is not about Rust.** Separate your rules
from your framework. You can do the same in pure GDScript: a `RefCounted` class
holding the simulation, a `Node` that displays it. The framework-free half is
where the bugs live and where tests are cheap.

## The event queue

Rust cannot conveniently emit Godot signals across this narrow boundary, so it
queues events and GDScript drains them:

```rust
pub fn drain_events(&mut self) -> Vec<Event> {
    std::mem::take(&mut self.events)
}
```

`std::mem::take` swaps in an empty `Vec` and hands back the full one — no clone.

Serialised with an internal tag:

```rust
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "kind")]
pub enum Event {
    #[serde(rename = "tier_up")]
    TierUp { tier: u32 },
    ...
}
```

which produces `{"kind":"tier_up","tier":2}`. GDScript matches on `kind` in
`SceneManager._dispatch()` and re-emits as typed signals. Lesson 05 covers that
translation.

## When Rust is worth it

Honestly: **for this game, it is not necessary.** A clicker's arithmetic is
trivial and GDScript would run it comfortably. The Rust layer here is a design
choice — you get a type-checked simulation with real unit tests — not a
performance requirement.

Reach for GDExtension when:

- You are CPU-bound in a hot loop — pathfinding, procedural generation, physics,
  large simulations.
- You need an existing native library.
- You want compile-time guarantees over a complex rule system.

Stay in GDScript when:

- You are iterating on gameplay feel. Rust needs a rebuild and an editor restart
  for every change; GDScript is instant.
- The work is UI, scene wiring, or anything touching nodes.

The split in this project reflects that. The simulation is Rust and rarely
changes. Every screen is GDScript and changes constantly.

## The build loop

```powershell
cargo build --workspace
```

Then **restart Godot** — `reloadable = false`, so the DLL is held open and only a
restart picks up a new one. If your rebuild seems to have no effect, that is why.

Prerequisites on Windows: rustup plus the MSVC linker. If you see
``linker `link.exe` not found``, install the C++ build tools:

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --override "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

rustup does not bundle a linker on the MSVC target — this is the single most
common first-build failure.

## Docs

- [godot-rust book](https://godot-rust.github.io/book/)
- [Compatibility matrix](https://godot-rust.github.io/book/toolchain/compatibility.html)
- [GDExtension overview](https://docs.godotengine.org/en/stable/tutorials/scripting/gdextension/what_is_gdextension.html)

## Exercise

1. Add a "Golden Fry" mechanic: a 1-in-50 chance that any click pays 10×. Put
   the roll in Rust, surface it as an event, and toast it in GDScript.
2. `snapshot_json()` is called every frame. Suppose profiling showed it was
   genuinely too slow. Give two ways to fix it without abandoning the JSON
   interface.

## Solution

**1.** In `state.rs`, add the event variant:

```rust
#[serde(rename = "golden")]
Golden { multiplier: f64, calories: f64 },
```

Then in `click_food()`, replace the gain calculation:

```rust
let mut gained = def.calories * self.click_multiplier();

// Deterministic pseudo-random from state we already track, so the run stays
// reproducible from a save file and we avoid pulling in a rng dependency.
let roll = (self.save.total_clicks.wrapping_mul(2_654_435_761)) % 50;
if roll == 0 {
    gained *= 10.0;
    self.events.push(Event::Golden {
        multiplier: 10.0,
        calories: gained,
    });
}

self.gain(gained);
```

Knuth's multiplicative hash gives a decent spread without a dependency, and
because it derives from `total_clicks` the sequence replays identically from a
save — which makes it testable. For real randomness, add the `rand` crate.

In `scene_manager.gd`, add the signal and the dispatch arm:

```gdscript
signal golden_click(multiplier: float, calories: float)
```

```gdscript
"golden":
	golden_click.emit(
		float(event.get("multiplier", 1.0)),
		float(event.get("calories", 0.0)))
```

And in `arena.gd._ready()`:

```gdscript
SceneManager.golden_click.connect(_on_golden_click)
```

```gdscript
func _on_golden_click(multiplier: float, calories: float) -> void:
	_toasts.push("GOLDEN FRY", "x%.0f — %s calories!" % [multiplier, Num.fmt(calories)],
		UiTheme.GOLD)
```

Notice the shape of the change: Rust owns the rule, GDScript owns the
presentation, and they meet at one `match` arm. Neither side knows how the other
works.

**2.** Two approaches.

*Cache and invalidate.* Keep the serialised string on the Rust side and rebuild
it only when the state actually changes:

```rust
snapshot_cache: Option<String>,
snapshot_dirty: bool,
```

Set `snapshot_dirty = true` in `gain()`, `buy_upgrade()` and `check_progress()`;
`snapshot_json()` reuses the cached string otherwise. Most frames change nothing
but the calorie count, though, so the win is smaller than it looks for this
particular game.

*Split hot from cold.* Most of the snapshot is static between frames — `max_tier`,
`achievements_total`, `next_tier_weight`. Only four values move continuously.
Expose those as scalar getters, which cost nothing:

```gdscript
_bank_label.text = "%s cal banked" % Num.fmt(SceneManager.game.calorie_bank())
_weight_label.text = Num.weight(SceneManager.game.weight_lbs())
```

and call the full `snapshot_json()` on the shop's 0.15s cadence instead. The
scalar getters already exist in `game.rs` — `calorie_bank()`, `weight_lbs()`,
`cps()`, `tier()` — precisely so this option is available.

The second is the better first move: it costs no cache-invalidation complexity,
which is where the bugs would come from.

---

Next: [11 — Debugging and where to go next](11-debugging-and-next.md)
