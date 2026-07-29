//! The GDExtension surface.
//!
//! GDScript sees a single `ClickerGame` RefCounted object. Everything crossing
//! the boundary is either a scalar or a JSON string — no Dictionaries, Arrays
//! or signals — so the binding stays stable across godot-rust releases and the
//! UI can be rebuilt without touching Rust.

use godot::prelude::*;
use serde_json::json;

use super::defs::{self, UpgradeKind, ACHIEVEMENTS, CALORIES_PER_POUND, FOODS, MAX_TIER, UPGRADES};
use super::state::Game;
use super::SAVE_FILE_VERSION;

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct ClickerGame {
    game: Game,
}

#[godot_api]
impl ClickerGame {
    // -- constants ---------------------------------------------------------

    #[func]
    fn save_version(&self) -> GString {
        GString::from(SAVE_FILE_VERSION)
    }

    #[func]
    fn calories_per_pound(&self) -> f64 {
        CALORIES_PER_POUND
    }

    #[func]
    fn max_tier(&self) -> i64 {
        MAX_TIER as i64
    }

    // -- scalars the HUD polls every frame ---------------------------------

    #[func]
    fn weight_lbs(&self) -> f64 {
        self.game.weight_lbs()
    }

    #[func]
    fn lifetime_calories(&self) -> f64 {
        self.game.save.lifetime_calories
    }

    #[func]
    fn calorie_bank(&self) -> f64 {
        self.game.save.calorie_bank
    }

    #[func]
    fn calories_into_pound(&self) -> f64 {
        self.game.calories_into_pound()
    }

    #[func]
    fn cps(&self) -> f64 {
        self.game.cps()
    }

    #[func]
    fn click_multiplier(&self) -> f64 {
        self.game.click_multiplier()
    }

    #[func]
    fn tier(&self) -> i64 {
        self.game.save.tier as i64
    }

    #[func]
    fn total_clicks(&self) -> i64 {
        self.game.save.total_clicks as i64
    }

    /// Weight required for the next tier, or `-1.0` at max tier.
    #[func]
    fn next_tier_weight(&self) -> f64 {
        let idx = (self.game.save.tier - 1) as usize;
        match defs::TIER_THRESHOLDS.get(idx) {
            Some(&w) if self.game.save.tier < MAX_TIER => w,
            _ => -1.0,
        }
    }

    #[func]
    fn cooldown_remaining(&self, id: GString) -> f64 {
        self.game.cooldown_remaining(&id.to_string())
    }

    #[func]
    fn food_unlocked(&self, id: GString) -> bool {
        self.game.food_unlocked(&id.to_string())
    }

    /// Price of the next level, or `-1.0` if maxed out / unknown.
    #[func]
    fn upgrade_cost(&self, id: GString) -> f64 {
        self.game.upgrade_cost(&id.to_string()).unwrap_or(-1.0)
    }

    #[func]
    fn upgrade_owned(&self, id: GString) -> i64 {
        self.game.owned(&id.to_string()) as i64
    }

    // -- actions -----------------------------------------------------------

    /// Advances the simulation. Returns calories earned passively.
    #[func]
    fn tick(&mut self, delta: f64) -> f64 {
        self.game.tick(delta)
    }

    /// Eats `id`. Returns calories gained; `0.0` means the click was refused.
    #[func]
    fn click_food(&mut self, id: GString) -> f64 {
        self.game.click_food(&id.to_string())
    }

    #[func]
    fn buy_upgrade(&mut self, id: GString) -> bool {
        self.game.buy_upgrade(&id.to_string())
    }

    /// Buys up to `count` levels. Returns how many were actually bought.
    #[func]
    fn buy_upgrade_bulk(&mut self, id: GString, count: i64) -> i64 {
        let count = count.clamp(0, 10_000) as u32;
        self.game.buy_upgrade_bulk(&id.to_string(), count) as i64
    }

    /// How many levels of `id` are affordable right now.
    #[func]
    fn affordable_levels(&self, id: GString, count: i64) -> i64 {
        let count = count.clamp(0, 10_000) as u32;
        self.game.bulk_quote(&id.to_string(), count).0 as i64
    }

    #[func]
    fn reset(&mut self) {
        self.game.reset();
    }

    // -- persistence -------------------------------------------------------

    /// Serializes the run. GDScript owns the actual file I/O.
    #[func]
    fn save_json(&mut self, now_unix: f64) -> GString {
        GString::from(self.game.to_json(now_unix))
    }

    /// Restores a run. Returns `false` if the payload was unusable, in which
    /// case the current state is left untouched.
    #[func]
    fn load_json(&mut self, json: GString) -> bool {
        self.game.from_json(&json.to_string())
    }

    /// Grants idle earnings for time spent away. Returns calories awarded.
    #[func]
    fn apply_offline(&mut self, now_unix: f64) -> f64 {
        self.game.apply_offline(now_unix)
    }

    #[func]
    fn mark_seen(&mut self, now_unix: f64) {
        self.game.mark_seen(now_unix);
    }

    // -- JSON views --------------------------------------------------------

    /// Everything the HUD needs in one call, as a JSON object.
    #[func]
    fn snapshot_json(&self) -> GString {
        let value = json!({
            "weight_lbs": self.game.weight_lbs(),
            "lifetime_calories": self.game.save.lifetime_calories,
            "calorie_bank": self.game.save.calorie_bank,
            "calories_into_pound": self.game.calories_into_pound(),
            "calories_per_pound": CALORIES_PER_POUND,
            "cps": self.game.cps(),
            "click_multiplier": self.game.click_multiplier(),
            "idle_multiplier": self.game.idle_multiplier(),
            "tier": self.game.save.tier,
            "max_tier": MAX_TIER,
            "next_tier_weight": self.next_tier_weight(),
            "total_clicks": self.game.save.total_clicks,
            "automation_levels": self.game.automation_levels(),
            "achievements_unlocked": self.game.save.achievements.len(),
            "achievements_total": ACHIEVEMENTS.len(),
        });
        GString::from(value.to_string())
    }

    /// Every food item with its live state, as a JSON array.
    #[func]
    fn foods_json(&self) -> GString {
        let mult = self.game.click_multiplier();
        let items: Vec<_> = FOODS
            .iter()
            .map(|f| {
                json!({
                    "id": f.id,
                    "name": f.name,
                    "base_calories": f.calories,
                    "calories": f.calories * mult,
                    "cooldown": f.cooldown,
                    "cooldown_remaining": self.game.cooldown_remaining(f.id),
                    "unlock_tier": f.unlock_tier,
                    "unlocked": self.game.save.tier >= f.unlock_tier,
                    "color": f.color,
                    "clicks": self.game.save.food_clicks.get(f.id).copied().unwrap_or(0),
                })
            })
            .collect();
        GString::from(serde_json::Value::Array(items).to_string())
    }

    /// Every upgrade with cost and affordability, as a JSON array.
    #[func]
    fn upgrades_json(&self) -> GString {
        let items: Vec<_> = UPGRADES
            .iter()
            .map(|u| {
                let owned = self.game.owned(u.id);
                let cost = self.game.upgrade_cost(u.id);
                let effect = match u.kind {
                    UpgradeKind::Automation => {
                        format!("+{} cal/sec", format_number(u.power))
                    }
                    UpgradeKind::ClickPower => {
                        format!("+{}% per click", (u.power * 100.0).round())
                    }
                    UpgradeKind::IdleBoost => {
                        format!("+{}% idle output", (u.power * 100.0).round())
                    }
                };
                json!({
                    "id": u.id,
                    "name": u.name,
                    "description": u.description,
                    "kind": u.kind.as_str(),
                    "effect": effect,
                    "owned": owned,
                    "max_level": u.max_level,
                    "maxed": cost.is_none(),
                    "cost": cost.unwrap_or(-1.0),
                    "affordable": cost.is_some_and(|c| self.game.save.calorie_bank >= c),
                    "unlock_tier": u.unlock_tier,
                    "unlocked": self.game.save.tier >= u.unlock_tier,
                    "contribution": match u.kind {
                        UpgradeKind::Automation => u.power * owned as f64 * self.game.idle_multiplier(),
                        _ => u.power * owned as f64,
                    },
                })
            })
            .collect();
        GString::from(serde_json::Value::Array(items).to_string())
    }

    /// Every achievement and whether it has been earned, as a JSON array.
    #[func]
    fn achievements_json(&self) -> GString {
        let items: Vec<_> = ACHIEVEMENTS
            .iter()
            .map(|a| {
                json!({
                    "id": a.id,
                    "name": a.name,
                    "description": a.description,
                    "unlocked": self.game.save.achievements.iter().any(|id| id == a.id),
                })
            })
            .collect();
        GString::from(serde_json::Value::Array(items).to_string())
    }

    /// Pops the queued tier-ups, unlocks and achievements as a JSON array.
    /// Each entry has a `kind` field. Call once per frame.
    #[func]
    fn drain_events_json(&mut self) -> GString {
        let events = self.game.drain_events();
        match serde_json::to_string(&events) {
            Ok(s) => GString::from(s),
            Err(_) => GString::from("[]"),
        }
    }
}

/// Compact human-readable number used inside upgrade effect strings.
fn format_number(n: f64) -> String {
    if n >= 1_000.0 {
        format!("{:.0}", n)
    } else if n.fract().abs() < f64::EPSILON {
        format!("{:.0}", n)
    } else {
        format!("{:.1}", n)
    }
}
