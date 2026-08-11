# American Obesity

A tongue-in-cheek clicker about American food culture. You start at 150 lbs in
an average kitchen and click your way through an expanding menu, converting
calories into pounds at the honest rate of 3,500 calories per pound. Along the
way you automate the whole operation — microwaves, an enabling roommate, a
GrubHub subscription, eventually a drive-thru franchise — until the clicking
becomes optional and the calories arrive on their own.

Built in **Godot 4**, with the simulation itself written in **Rust** as a
GDExtension. Runs on desktop and Android, with a layout that switches between a
three-column desktop view and a stacked phone view.

**Further reading**

- [docs/MOBILE.md](docs/MOBILE.md) — Android build pipeline, iOS requirements, store policy
- [docs/LIGHTNING.md](docs/LIGHTNING.md) — Bitcoin payments, platform gating, threat model
- [docs/godot-course/](docs/godot-course/README.md) — a Godot course taught through this codebase

---

## Running it

The Rust extension is not optional: it holds the entire game state. Build it
first, then open the project.

**Windows**

```powershell
powershell -ExecutionPolicy Bypass -File .\build-windows-debug.ps1
```

If cargo reports ``linker `link.exe` not found``, you need the MSVC C++ build
tools — rustup does not ship a linker:

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --override "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

Open a **new** terminal afterwards, then re-run the build.

**Linux / macOS**

```bash
./build-linux-debug.sh
```

Then open `amerobe/project.godot` and press Play. If you skip the build step the
game still launches, but every screen shows a "simulation engine not loaded"
banner instead of guessing at a fallback. Godot only reads `.gdextension` files
at project load, so **restart the editor** after the first successful build.

Run the simulation's unit tests with:

```bash
cargo test -p engine
```

---

## Architecture

The Rust/GDScript boundary is deliberately narrow: **scalars in, JSON strings
out**. No Dictionaries, Arrays or signals cross it. That keeps the binding
small enough to reason about, means the UI can be rewritten without
recompiling anything, and keeps the surface stable across godot-rust releases.

```
engine/src/
  lib.rs                    GDExtension entry point
  clicker_game/
    defs.rs                 content tables: food, upgrades, achievements
    state.rs                the simulation — no Godot types, plain cargo test
    game.rs                 the `ClickerGame` class GDScript talks to

amerobe/
  Scenes/                   one node per scene; all layout is built in code
  Scripts/
    scene_manager.gd        autoload: owns ClickerGame, ticks it, saves, routes
    arena.gd                the kitchen — HUD, food grid, shop, achievements
    title_screen.gd         menu
    evolution.gd            the between-tiers cutscene
    food_button.gd          one food card
    upgrade_row.gd          one shop row
    toast_layer.gd          transient notifications
    placeholder_art.gd      loads real art, draws stand-ins when it is missing
    ui_theme.gd             colours and StyleBox factories
    num.gd                  number formatting (1.23K, 5.60M, ...)
```

`SceneManager` is the only thing that touches the extension. Screens read
snapshots from it and listen to its signals.

### Save files

Saves live at `user://progress.save` — plain JSON, serialized by serde on the
Rust side, written to disk by GDScript. Every field is `#[serde(default)]`, so
old saves keep loading as the game grows, and unknown upgrade/food/achievement
ids are dropped on load rather than crashing. The game autosaves every 20
seconds, on quit, and when you return to the menu.

### Idle and offline progress

Automation produces calories per second while the game runs. Time spent with
the game closed is credited at 50% efficiency, capped at 8 hours, and reported
in a toast when you come back.

---

## Progression

Five tiers across the four weight classes from the design document.

| Tier | Reached at | Weight class | Kitchen | Unlocks |
|-----:|-----------:|--------------|---------|---------|
| 1 | 150 lbs | Beginner | Your Average Kitchen | Fries, Soft Drink, Burger |
| 2 | 250 lbs | Heavyweight | The Comfort Food Era | Pizza, Ice Cream, Fried Chicken |
| 3 | 500 lbs | Super Size | State Fair Territory | Deep-Fried Butter, Triple Burger, Mega Shake |
| 4 | 750 lbs | Super Size | Industrial Appetite | Family Bucket, Loaded Nachos, Whole Sheet Cake |
| 5 | 1,000 lbs | Ultimate Glutton | The Final Buffet | Gravy Fountain, The Whole Hog, The Entire Buffet |

The character sprite has five states — Base, Chunky, Heavy, Massive, Ultimate —
and gains a chin per tier. Crossing a threshold plays the evolution cutscene and
swaps both the character and the backdrop.

**15 foods. 16 upgrades. 35 achievements.**

Upgrades are grouped the way the design document describes them:

- **Fast Food Subscriptions** — McDoorDash, UberFeasts, GrubSquad
- **Kitchen Appliances** — Microwave, Deep Fryer, Industrial Grill
- **Restaurant Partnerships** — Local Diner, Fast Food Franchise, All-You-Can-Eat Buffet
- **Body Modifications** — click power
- **Lifestyle Choices** — idle multipliers

Achievements are grouped into Weight Milestones, Food Mastery, Automation
Excellence, Clicking and Excess.

Balance lives entirely in `engine/src/clicker_game/defs.rs` — every food,
upgrade, premium item and achievement is a plain struct literal in one file.
Nothing in the UI needs to change when you add one.

---

## Artwork

Several source PNGs were never committed, because `amerobe/.gitignore`
contained `/art/*.png`. That entry is gone now, but the missing files are still
missing. `Scripts/placeholder_art.gd` handles it: it loads the real texture
when it exists and procedurally draws a readable stand-in when it does not.
Drop a real PNG at the expected path and it takes over on the next run.

Still missing (placeholders in use):

- `art/start_screen.png`
- `art/nikacado_overweight_comp.png`, `art/nikacado_obese_comp_nbg.png`
- `art/character_massive.png`, `art/character_ultimate.png` (tiers 4 and 5)
- every food icon except `burger.png` and `fries.png` — drop
  `art/<food_id>.png` in and it is picked up automatically, ids are in
  `defs.rs`

---

## Leftovers you can delete

These are from the earlier prototype and are no longer referenced by anything.
`cleanup-stale-files.ps1` removes them, or delete them by hand:

```
amerobe/evolution.gd                 (moved to Scripts/evolution.gd)
amerobe/arena.gd.uid                 (orphan .uid, no matching script)
amerobe/clickbutt.gd.uid             (orphan .uid, no matching script)
amerobe/player.tscn*.tmp             (editor scratch files)
amerobe/Scripts/clickbutt.gd         (superseded by Scripts/food_button.gd)
amerobe/Scripts/tier_2.gd            (tiers are handled by arena.gd now)
amerobe/Scenes/tier_2.tscn           (ditto)
amerobe/art/*.png.import             (only the five with no source PNG)
```
