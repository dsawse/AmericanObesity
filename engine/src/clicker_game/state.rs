//! The pure simulation. No Godot types appear in this module, which keeps it
//! unit-testable with plain `cargo test`.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use super::defs::{
    self, Condition, UpgradeKind, ACHIEVEMENTS, CALORIES_PER_POUND, FOODS, MAX_TIER,
    OFFLINE_CAP_SECONDS, OFFLINE_EFFICIENCY, STARTING_WEIGHT_LBS, TIER_THRESHOLDS, UPGRADES,
};
use super::SAVE_FILE_VERSION;

// ---------------------------------------------------------------------------
// Persisted state
// ---------------------------------------------------------------------------

/// Everything that survives a restart. Every field carries `#[serde(default)]`
/// so an older save file still loads after new fields are introduced.
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
    /// Upgrade id -> owned levels.
    #[serde(default)]
    pub upgrades: BTreeMap<String, u32>,
    /// Food id -> times clicked.
    #[serde(default)]
    pub food_clicks: BTreeMap<String, u64>,
    #[serde(default)]
    pub achievements: Vec<String>,
    /// Premium items bought with Lightning. Ids from [`defs::PREMIUM`].
    #[serde(default)]
    pub entitlements: Vec<String>,
    /// Unix timestamp of the last save, used for offline earnings.
    #[serde(default)]
    pub last_seen_unix: f64,
}

fn one() -> u32 {
    1
}

impl Default for SaveState {
    fn default() -> Self {
        Self {
            version: SAVE_FILE_VERSION.to_string(),
            lifetime_calories: 0.0,
            calorie_bank: 0.0,
            total_clicks: 0,
            tier: 1,
            upgrades: BTreeMap::new(),
            food_clicks: BTreeMap::new(),
            achievements: Vec::new(),
            entitlements: Vec::new(),
            last_seen_unix: 0.0,
        }
    }
}

// ---------------------------------------------------------------------------
// Events surfaced to the presentation layer
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "kind")]
pub enum Event {
    #[serde(rename = "tier_up")]
    TierUp { tier: u32 },
    #[serde(rename = "achievement")]
    Achievement {
        id: String,
        name: String,
        description: String,
    },
    #[serde(rename = "food_unlocked")]
    FoodUnlocked { id: String, name: String },
    #[serde(rename = "offline_earnings")]
    OfflineEarnings { seconds: f64, calories: f64 },
}

// ---------------------------------------------------------------------------
// Runtime game
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, Default)]
pub struct Game {
    pub save: SaveState,
    /// Food id -> seconds of cooldown remaining.
    cooldowns: BTreeMap<String, f64>,
    /// Drained by the presentation layer each frame.
    events: Vec<Event>,
}

impl Game {
    pub fn new() -> Self {
        let mut game = Self::default();
        // A brand new run should not fire "you were away" on the first tick.
        game.save.last_seen_unix = 0.0;
        game
    }

    // -- derived values ----------------------------------------------------

    pub fn weight_lbs(&self) -> f64 {
        STARTING_WEIGHT_LBS + self.save.lifetime_calories / CALORIES_PER_POUND
    }

    /// Calories accumulated toward the next pound.
    pub fn calories_into_pound(&self) -> f64 {
        self.save.lifetime_calories % CALORIES_PER_POUND
    }

    pub fn owned(&self, id: &str) -> u32 {
        self.save.upgrades.get(id).copied().unwrap_or(0)
    }

    pub fn automation_levels(&self) -> u32 {
        UPGRADES
            .iter()
            .filter(|u| u.kind == UpgradeKind::Automation)
            .map(|u| self.owned(u.id))
            .sum()
    }

    // -- premium entitlements ----------------------------------------------

    pub fn has_entitlement(&self, id: &str) -> bool {
        self.save.entitlements.iter().any(|e| e == id)
    }

    /// Records a premium purchase. Returns `false` for an unknown id or one
    /// already owned, so the caller can tell a real grant from a no-op.
    pub fn grant_entitlement(&mut self, id: &str) -> bool {
        if defs::premium(id).is_none() || self.has_entitlement(id) {
            return false;
        }
        self.save.entitlements.push(id.to_string());
        self.check_progress();
        true
    }

    /// Product of every owned premium item of `kind`.
    fn premium_multiplier(&self, kind: defs::PremiumKind) -> f64 {
        defs::PREMIUM
            .iter()
            .filter(|p| p.kind == kind && self.has_entitlement(p.id))
            .fold(1.0, |acc, p| acc * p.power)
    }

    /// Offline cap in seconds, extended by the freezer entitlement.
    fn offline_cap_seconds(&self) -> f64 {
        let hours = defs::PREMIUM
            .iter()
            .filter(|p| p.kind == defs::PremiumKind::OfflineHours && self.has_entitlement(p.id))
            .map(|p| p.power)
            .fold(OFFLINE_CAP_SECONDS / 3600.0, f64::max);
        hours * 3600.0
    }

    /// Multiplier applied to every automation source.
    pub fn idle_multiplier(&self) -> f64 {
        UPGRADES
            .iter()
            .filter(|u| u.kind == UpgradeKind::IdleBoost)
            .fold(1.0, |acc, u| acc * (1.0 + u.power * self.owned(u.id) as f64))
            * self.premium_multiplier(defs::PremiumKind::IdleMultiplier)
    }

    /// Multiplier applied to manual clicks.
    pub fn click_multiplier(&self) -> f64 {
        UPGRADES
            .iter()
            .filter(|u| u.kind == UpgradeKind::ClickPower)
            .fold(1.0, |acc, u| acc * (1.0 + u.power * self.owned(u.id) as f64))
            * self.premium_multiplier(defs::PremiumKind::ClickMultiplier)
    }

    /// Passive calories per second.
    pub fn cps(&self) -> f64 {
        let raw: f64 = UPGRADES
            .iter()
            .filter(|u| u.kind == UpgradeKind::Automation)
            .map(|u| u.power * self.owned(u.id) as f64)
            .sum();
        raw * self.idle_multiplier()
    }

    /// Current price of the next level of `id`, or `None` if maxed/unknown.
    pub fn upgrade_cost(&self, id: &str) -> Option<f64> {
        let def = defs::upgrade(id)?;
        let owned = self.owned(id);
        if def.max_level > 0 && owned >= def.max_level {
            return None;
        }
        Some(def.base_cost * def.cost_growth.powi(owned as i32))
    }

    pub fn food_unlocked(&self, id: &str) -> bool {
        defs::food(id).is_some_and(|f| self.save.tier >= f.unlock_tier)
    }

    pub fn cooldown_remaining(&self, id: &str) -> f64 {
        self.cooldowns.get(id).copied().unwrap_or(0.0).max(0.0)
    }

    /// Times a single food item has been clicked.
    pub fn food_clicks(&self, id: &str) -> u64 {
        self.save.food_clicks.get(id).copied().unwrap_or(0)
    }

    /// Total clicks across every food belonging to `tier`.
    pub fn tier_food_clicks(&self, tier: u32) -> u64 {
        FOODS
            .iter()
            .filter(|f| f.unlock_tier == tier)
            .map(|f| self.food_clicks(f.id))
            .sum()
    }

    pub fn weight_class(&self) -> &'static str {
        defs::weight_class(self.weight_lbs())
    }

    pub fn character_state(&self) -> &'static str {
        defs::character_state(self.weight_lbs())
    }

    // -- mutation ----------------------------------------------------------

    /// Adds calories to both the lifetime total and the spendable bank.
    fn gain(&mut self, calories: f64) {
        if calories <= 0.0 || !calories.is_finite() {
            return;
        }
        self.save.lifetime_calories += calories;
        self.save.calorie_bank += calories;
    }

    /// Advances the simulation by `delta` seconds. Returns calories gained
    /// passively during that slice.
    pub fn tick(&mut self, delta: f64) -> f64 {
        if !delta.is_finite() || delta <= 0.0 {
            return 0.0;
        }
        // Guard against a huge delta after a stalled frame or a paused window.
        let delta = delta.min(1.0);

        for remaining in self.cooldowns.values_mut() {
            if *remaining > 0.0 {
                *remaining = (*remaining - delta).max(0.0);
            }
        }

        let gained = self.cps() * delta;
        self.gain(gained);
        self.check_progress();
        gained
    }

    /// Attempts to eat `id`. Returns the calories gained; `0.0` means the click
    /// was rejected (locked item, unknown id, or still cooling down).
    pub fn click_food(&mut self, id: &str) -> f64 {
        let Some(def) = defs::food(id) else {
            return 0.0;
        };
        if self.save.tier < def.unlock_tier {
            return 0.0;
        }
        if self.cooldown_remaining(id) > 0.0 {
            return 0.0;
        }

        let gained = def.calories * self.click_multiplier();
        self.gain(gained);
        self.save.total_clicks += 1;
        *self.save.food_clicks.entry(id.to_string()).or_insert(0) += 1;
        self.cooldowns.insert(id.to_string(), def.cooldown);
        self.check_progress();
        gained
    }

    /// Buys one level of `id`. Returns `true` on success.
    pub fn buy_upgrade(&mut self, id: &str) -> bool {
        let Some(def) = defs::upgrade(id) else {
            return false;
        };
        if self.save.tier < def.unlock_tier {
            return false;
        }
        let Some(cost) = self.upgrade_cost(id) else {
            return false;
        };
        if self.save.calorie_bank < cost {
            return false;
        }

        self.save.calorie_bank -= cost;
        *self.save.upgrades.entry(id.to_string()).or_insert(0) += 1;
        self.check_progress();
        true
    }

    /// How many levels of `id` are affordable right now, and their total cost.
    pub fn bulk_quote(&self, id: &str, count: u32) -> (u32, f64) {
        let Some(def) = defs::upgrade(id) else {
            return (0, 0.0);
        };
        let mut owned = self.owned(id);
        let mut budget = self.save.calorie_bank;
        let mut bought = 0;
        let mut spent = 0.0;
        while bought < count {
            if def.max_level > 0 && owned >= def.max_level {
                break;
            }
            let price = def.base_cost * def.cost_growth.powi(owned as i32);
            if price > budget {
                break;
            }
            budget -= price;
            spent += price;
            owned += 1;
            bought += 1;
        }
        (bought, spent)
    }

    pub fn buy_upgrade_bulk(&mut self, id: &str, count: u32) -> u32 {
        let mut bought = 0;
        for _ in 0..count {
            if !self.buy_upgrade(id) {
                break;
            }
            bought += 1;
        }
        bought
    }

    /// Grants idle earnings for time spent with the game closed.
    /// Returns the calories awarded.
    pub fn apply_offline(&mut self, now_unix: f64) -> f64 {
        let last = self.save.last_seen_unix;
        self.save.last_seen_unix = now_unix;

        if last <= 0.0 || now_unix <= last {
            return 0.0;
        }
        let elapsed = (now_unix - last).min(self.offline_cap_seconds());
        // Anything under a minute is not worth a popup.
        if elapsed < 60.0 {
            return 0.0;
        }
        let calories = self.cps() * elapsed * OFFLINE_EFFICIENCY;
        if calories <= 0.0 {
            return 0.0;
        }
        self.gain(calories);
        self.events.push(Event::OfflineEarnings {
            seconds: elapsed,
            calories,
        });
        self.check_progress();
        calories
    }

    pub fn mark_seen(&mut self, now_unix: f64) {
        self.save.last_seen_unix = now_unix;
    }

    pub fn reset(&mut self) {
        self.save = SaveState::default();
        self.cooldowns.clear();
        self.events.clear();
    }

    // -- progression -------------------------------------------------------

    /// Promotes tiers and unlocks achievements. Safe to call every frame.
    fn check_progress(&mut self) {
        // Tier promotion. A single call can span more than one threshold.
        loop {
            if self.save.tier >= MAX_TIER {
                break;
            }
            let idx = (self.save.tier - 1) as usize;
            let Some(&threshold) = TIER_THRESHOLDS.get(idx) else {
                break;
            };
            if self.weight_lbs() < threshold {
                break;
            }
            self.save.tier += 1;
            let new_tier = self.save.tier;
            self.events.push(Event::TierUp { tier: new_tier });
            // `new_tier` is copied into the closure so the filter does not hold
            // a borrow of `self` across the mutable `self.events.push` below.
            for f in FOODS.iter().filter(|f| f.unlock_tier == new_tier) {
                self.events.push(Event::FoodUnlocked {
                    id: f.id.to_string(),
                    name: f.name.to_string(),
                });
            }
        }

        // Achievements.
        for a in ACHIEVEMENTS {
            if self.save.achievements.iter().any(|id| id == a.id) {
                continue;
            }
            let met = match a.condition {
                Condition::Clicks(n) => self.save.total_clicks >= n,
                Condition::Weight(w) => self.weight_lbs() >= w,
                Condition::Lifetime(c) => self.save.lifetime_calories >= c,
                Condition::AutomationOwned(n) => self.automation_levels() >= n,
                Condition::UpgradeLevel(id, n) => self.owned(id) >= n,
                Condition::Tier(t) => self.save.tier >= t,
                Condition::Cps(c) => self.cps() >= c,
                Condition::ClickPower(m) => self.click_multiplier() >= m,
                Condition::FoodClicks(id, n) => self.food_clicks(id) >= n,
                Condition::TierFoodClicks(tier, n) => self.tier_food_clicks(tier) >= n,
                Condition::Banked(c) => self.save.calorie_bank >= c,
            };
            if met {
                self.save.achievements.push(a.id.to_string());
                self.events.push(Event::Achievement {
                    id: a.id.to_string(),
                    name: a.name.to_string(),
                    description: a.description.to_string(),
                });
            }
        }
    }

    // -- events ------------------------------------------------------------

    pub fn drain_events(&mut self) -> Vec<Event> {
        std::mem::take(&mut self.events)
    }

    // -- persistence -------------------------------------------------------

    pub fn to_json(&mut self, now_unix: f64) -> String {
        self.save.last_seen_unix = now_unix;
        self.save.version = SAVE_FILE_VERSION.to_string();
        serde_json::to_string(&self.save).unwrap_or_else(|_| "{}".to_string())
    }

    /// Replaces the current state with `json`. Returns `false` if the payload
    /// could not be parsed, in which case the existing state is untouched.
    pub fn from_json(&mut self, json: &str) -> bool {
        match serde_json::from_str::<SaveState>(json) {
            Ok(mut save) => {
                // Clamp anything a hand-edited save could have broken.
                save.tier = save.tier.clamp(1, MAX_TIER);
                if !save.lifetime_calories.is_finite() || save.lifetime_calories < 0.0 {
                    save.lifetime_calories = 0.0;
                }
                if !save.calorie_bank.is_finite() || save.calorie_bank < 0.0 {
                    save.calorie_bank = 0.0;
                }
                save.upgrades.retain(|id, _| defs::upgrade(id).is_some());
                save.food_clicks.retain(|id, _| defs::food(id).is_some());
                save.achievements
                    .retain(|id| ACHIEVEMENTS.iter().any(|a| a.id == *id));
                save.entitlements.retain(|id| defs::premium(id).is_some());
                // `dedup` only collapses *consecutive* duplicates, so sort
                // first. Otherwise a hand-edited save listing the same item
                // twice would apply its multiplier twice.
                save.entitlements.sort();
                save.entitlements.dedup();

                self.save = save;
                self.cooldowns.clear();
                self.events.clear();
                true
            }
            Err(_) => false,
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn click_grants_calories_and_starts_cooldown() {
        let mut g = Game::new();
        let gained = g.click_food("fries");
        assert_eq!(gained, 25.0);
        assert_eq!(g.save.total_clicks, 1);
        // Second click is refused while cooling down.
        assert_eq!(g.click_food("fries"), 0.0);
        g.tick(0.5);
        assert_eq!(g.click_food("fries"), 25.0);
    }

    #[test]
    fn locked_food_is_rejected() {
        let mut g = Game::new();
        assert_eq!(g.click_food("pizza"), 0.0);
        assert_eq!(g.click_food("not_a_real_food"), 0.0);
    }

    #[test]
    fn weight_tracks_lifetime_calories() {
        let mut g = Game::new();
        g.save.lifetime_calories = CALORIES_PER_POUND * 10.0;
        assert!((g.weight_lbs() - (STARTING_WEIGHT_LBS + 10.0)).abs() < 1e-9);
    }

    #[test]
    fn tier_promotes_and_unlocks_food() {
        let mut g = Game::new();
        // Tier 2 is 250 lbs, i.e. 100 lbs gained == 350_000 calories.
        g.save.lifetime_calories = 100.0 * CALORIES_PER_POUND;
        g.check_progress();
        assert_eq!(g.save.tier, 2);
        assert!(g.food_unlocked("pizza"));
        assert!(!g.food_unlocked("fried_butter"));
        assert!(g
            .events
            .iter()
            .any(|e| matches!(e, Event::TierUp { tier: 2 })));
    }

    #[test]
    fn a_single_check_can_span_several_tiers() {
        let mut g = Game::new();
        // Straight past 250, 500, 750 and 1000 lbs in one go.
        g.save.lifetime_calories = 2_000.0 * CALORIES_PER_POUND;
        g.check_progress();
        assert_eq!(g.save.tier, MAX_TIER);
        assert!(g.food_unlocked("entire_buffet"));

        let tier_ups = g
            .events
            .iter()
            .filter(|e| matches!(e, Event::TierUp { .. }))
            .count();
        assert_eq!(tier_ups, 4);
    }

    #[test]
    fn weight_classes_track_the_design_document() {
        let mut g = Game::new();
        assert_eq!(g.weight_class(), "Beginner");
        assert_eq!(g.character_state(), "Base");

        g.save.lifetime_calories = 100.0 * CALORIES_PER_POUND; // 250 lbs
        assert_eq!(g.weight_class(), "Heavyweight");
        assert_eq!(g.character_state(), "Chunky");

        g.save.lifetime_calories = 350.0 * CALORIES_PER_POUND; // 500 lbs
        assert_eq!(g.weight_class(), "Super Size");
        assert_eq!(g.character_state(), "Heavy");

        g.save.lifetime_calories = 600.0 * CALORIES_PER_POUND; // 750 lbs
        assert_eq!(g.character_state(), "Massive");

        g.save.lifetime_calories = 850.0 * CALORIES_PER_POUND; // 1000 lbs
        assert_eq!(g.weight_class(), "Ultimate Glutton");
        assert_eq!(g.character_state(), "Ultimate");
    }

    #[test]
    fn food_mastery_counts_per_tier() {
        let mut g = Game::new();
        assert_eq!(g.tier_food_clicks(1), 0);

        g.click_food("fries");
        g.tick(0.5);
        g.click_food("soda");
        assert_eq!(g.tier_food_clicks(1), 2);
        assert_eq!(g.food_clicks("fries"), 1);
        // Tier 2 is still locked, so nothing landed there.
        assert_eq!(g.tier_food_clicks(2), 0);
    }

    #[test]
    fn buying_spends_the_bank_and_raises_the_price() {
        let mut g = Game::new();
        g.save.calorie_bank = 1_000.0;
        let first = g.upgrade_cost("microwave").unwrap();
        assert!(g.buy_upgrade("microwave"));
        let second = g.upgrade_cost("microwave").unwrap();
        assert!(second > first);
        assert!((g.save.calorie_bank - (1_000.0 - first)).abs() < 1e-9);
        assert!(g.cps() > 0.0);
    }

    #[test]
    fn cannot_overspend() {
        let mut g = Game::new();
        g.save.calorie_bank = 1.0;
        assert!(!g.buy_upgrade("microwave"));
        assert_eq!(g.owned("microwave"), 0);
    }

    #[test]
    fn max_level_is_respected() {
        let mut g = Game::new();
        g.save.calorie_bank = f64::MAX / 2.0;
        let def = defs::upgrade("bigger_bites").unwrap();
        for _ in 0..def.max_level {
            assert!(g.buy_upgrade("bigger_bites"));
        }
        assert!(g.upgrade_cost("bigger_bites").is_none());
        assert!(!g.buy_upgrade("bigger_bites"));
    }

    #[test]
    fn offline_earnings_are_capped_and_halved() {
        let mut g = Game::new();
        g.save.calorie_bank = 100.0;
        g.buy_upgrade("microwave"); // 1 cal/s
        let cps = g.cps();
        g.mark_seen(1_000.0);
        let awarded = g.apply_offline(1_000.0 + OFFLINE_CAP_SECONDS * 4.0);
        let expected = cps * OFFLINE_CAP_SECONDS * OFFLINE_EFFICIENCY;
        assert!((awarded - expected).abs() < 1e-6);
    }

    #[test]
    fn save_round_trips() {
        let mut g = Game::new();
        g.save.calorie_bank = 5_000.0;
        g.click_food("burger");
        g.buy_upgrade("microwave");
        let json = g.to_json(42.0);

        let mut restored = Game::new();
        assert!(restored.from_json(&json));
        assert_eq!(restored.owned("microwave"), 1);
        assert_eq!(restored.save.total_clicks, g.save.total_clicks);
        assert!((restored.save.lifetime_calories - g.save.lifetime_calories).abs() < 1e-9);
    }

    #[test]
    fn corrupt_save_is_rejected_without_wiping_state() {
        let mut g = Game::new();
        g.click_food("fries");
        let before = g.save.lifetime_calories;
        assert!(!g.from_json("{ this is not json"));
        assert_eq!(g.save.lifetime_calories, before);
    }

    #[test]
    fn unknown_ids_in_a_save_are_dropped() {
        let mut g = Game::new();
        assert!(g.from_json(r#"{"upgrades":{"ghost_upgrade":9},"tier":99}"#));
        assert_eq!(g.owned("ghost_upgrade"), 0);
        assert_eq!(g.save.tier, MAX_TIER);
    }

    #[test]
    fn premium_multipliers_stack_on_top_of_upgrades() {
        let mut g = Game::new();
        let base_click = g.click_multiplier();
        assert!(g.grant_entitlement("golden_spatula"));
        assert!((g.click_multiplier() - base_click * 2.0).abs() < 1e-9);

        // Granting twice is a no-op, so a replayed payment cannot double-apply.
        assert!(!g.grant_entitlement("golden_spatula"));
        assert!((g.click_multiplier() - base_click * 2.0).abs() < 1e-9);
    }

    #[test]
    fn unknown_entitlements_are_refused_and_stripped() {
        let mut g = Game::new();
        assert!(!g.grant_entitlement("free_money_please"));
        assert!(!g.has_entitlement("free_money_please"));

        assert!(g.from_json(r#"{"entitlements":["free_money_please","neon_kitchen"]}"#));
        assert!(!g.has_entitlement("free_money_please"));
        assert!(g.has_entitlement("neon_kitchen"));
    }

    #[test]
    fn duplicated_entitlements_do_not_stack() {
        let mut g = Game::new();
        let base = g.click_multiplier();
        // A hand-edited save listing the same item three times, non-adjacent.
        assert!(g.from_json(
            r#"{"entitlements":["golden_spatula","neon_kitchen","golden_spatula"]}"#
        ));
        assert_eq!(g.save.entitlements.len(), 2);
        assert!((g.click_multiplier() - base * 2.0).abs() < 1e-9);
    }

    #[test]
    fn freezer_extends_the_offline_cap() {
        let mut g = Game::new();
        g.save.calorie_bank = 100.0;
        g.buy_upgrade("microwave");
        let cps = g.cps();

        g.mark_seen(1_000.0);
        let capped = g.apply_offline(1_000.0 + 100.0 * 3600.0);
        assert!((capped - cps * OFFLINE_CAP_SECONDS * OFFLINE_EFFICIENCY).abs() < 1e-6);

        g.grant_entitlement("deep_freezer");
        g.mark_seen(1_000.0);
        let extended = g.apply_offline(1_000.0 + 100.0 * 3600.0);
        assert!((extended - cps * 24.0 * 3600.0 * OFFLINE_EFFICIENCY).abs() < 1e-6);
        assert!(extended > capped);
    }

    #[test]
    fn achievements_fire_once() {
        let mut g = Game::new();
        g.click_food("fries");
        let events = g.drain_events();
        let count = events
            .iter()
            .filter(|e| matches!(e, Event::Achievement { id, .. } if id == "first_bite"))
            .count();
        assert_eq!(count, 1);
        g.tick(0.5);
        g.click_food("fries");
        let again = g.drain_events();
        assert!(!again
            .iter()
            .any(|e| matches!(e, Event::Achievement { id, .. } if id == "first_bite")));
    }
}
