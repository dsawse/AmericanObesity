//! Static content definitions for the clicker game.
//!
//! Everything the designer would want to tweak — food items, upgrades,
//! achievements and progression thresholds — lives here as plain data so the
//! simulation in [`super::state`] stays generic.

/// Calories in one pound of body weight.
pub const CALORIES_PER_POUND: f64 = 3500.0;

/// Weight the player starts at, in pounds.
pub const STARTING_WEIGHT_LBS: f64 = 150.0;

/// Weight (lbs) required to advance *into* tier 2, 3, ... respectively.
/// `TIER_THRESHOLDS[0]` is the requirement to reach tier 2.
pub const TIER_THRESHOLDS: &[f64] = &[175.0, 250.0];

/// Highest tier reachable. Tier 1 is the starting kitchen.
pub const MAX_TIER: u32 = 3;

/// Idle earnings are granted at this fraction of the online rate.
pub const OFFLINE_EFFICIENCY: f64 = 0.5;

/// Idle earnings are capped at this many seconds away (8 hours).
pub const OFFLINE_CAP_SECONDS: f64 = 8.0 * 60.0 * 60.0;

// ---------------------------------------------------------------------------
// Food
// ---------------------------------------------------------------------------

pub struct FoodDef {
    pub id: &'static str,
    pub name: &'static str,
    /// Base calories granted per click, before multipliers.
    pub calories: f64,
    /// Seconds the button is unusable after a click.
    pub cooldown: f64,
    /// Tier at which this item becomes clickable.
    pub unlock_tier: u32,
    /// Hex colour used for the procedural placeholder sprite.
    pub color: &'static str,
}

pub const FOODS: &[FoodDef] = &[
    // --- Tier 1: the humble beginnings -------------------------------------
    FoodDef {
        id: "fries",
        name: "Fries",
        calories: 25.0,
        cooldown: 0.25,
        unlock_tier: 1,
        color: "#e8b83a",
    },
    FoodDef {
        id: "soda",
        name: "Soda",
        calories: 150.0,
        cooldown: 0.5,
        unlock_tier: 1,
        color: "#c0392b",
    },
    FoodDef {
        id: "burger",
        name: "Burger",
        calories: 550.0,
        cooldown: 1.0,
        unlock_tier: 1,
        color: "#8b5a2b",
    },
    // --- Tier 2: the supersize era -----------------------------------------
    FoodDef {
        id: "cheezy_fries",
        name: "Cheezy Fries",
        calories: 800.0,
        cooldown: 1.0,
        unlock_tier: 2,
        color: "#f0a500",
    },
    FoodDef {
        id: "big_gulp",
        name: "Big Gulp",
        calories: 900.0,
        cooldown: 1.2,
        unlock_tier: 2,
        color: "#d94f70",
    },
    FoodDef {
        id: "double_burger",
        name: "Double Burger",
        calories: 1100.0,
        cooldown: 1.5,
        unlock_tier: 2,
        color: "#7b4a1e",
    },
    // --- Tier 3: state fair territory --------------------------------------
    FoodDef {
        id: "fried_butter",
        name: "Deep-Fried Butter",
        calories: 2500.0,
        cooldown: 2.0,
        unlock_tier: 3,
        color: "#f5e05a",
    },
    FoodDef {
        id: "family_bucket",
        name: "Family Bucket",
        calories: 5000.0,
        cooldown: 3.0,
        unlock_tier: 3,
        color: "#b03030",
    },
    FoodDef {
        id: "sheet_cake",
        name: "Whole Sheet Cake",
        calories: 9000.0,
        cooldown: 4.0,
        unlock_tier: 3,
        color: "#e58ac0",
    },
];

pub fn food(id: &str) -> Option<&'static FoodDef> {
    FOODS.iter().find(|f| f.id == id)
}

// ---------------------------------------------------------------------------
// Upgrades
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum UpgradeKind {
    /// Generates calories passively, per second.
    Automation,
    /// Multiplies the calories gained from a manual click.
    ClickPower,
    /// Multiplies the output of every automation source.
    IdleBoost,
}

impl UpgradeKind {
    pub fn as_str(self) -> &'static str {
        match self {
            UpgradeKind::Automation => "automation",
            UpgradeKind::ClickPower => "click_power",
            UpgradeKind::IdleBoost => "idle_boost",
        }
    }
}

pub struct UpgradeDef {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    pub kind: UpgradeKind,
    /// Cost of the first level.
    pub base_cost: f64,
    /// Each owned level multiplies the next cost by this factor.
    pub cost_growth: f64,
    /// Automation: calories/second added per level.
    /// ClickPower / IdleBoost: fractional bonus added per level (0.5 == +50%).
    pub power: f64,
    /// Maximum owned levels. `0` means unlimited.
    pub max_level: u32,
    /// Tier at which this upgrade appears in the shop.
    pub unlock_tier: u32,
}

pub const UPGRADES: &[UpgradeDef] = &[
    // --- Automation ---------------------------------------------------------
    UpgradeDef {
        id: "microwave",
        name: "Microwave",
        description: "Reheats leftovers around the clock.",
        kind: UpgradeKind::Automation,
        base_cost: 100.0,
        cost_growth: 1.15,
        power: 1.0,
        max_level: 0,
        unlock_tier: 1,
    },
    UpgradeDef {
        id: "roommate",
        name: "Enabling Roommate",
        description: "Keeps the pantry suspiciously well stocked.",
        kind: UpgradeKind::Automation,
        base_cost: 1_200.0,
        cost_growth: 1.15,
        power: 8.0,
        max_level: 0,
        unlock_tier: 1,
    },
    UpgradeDef {
        id: "grubhub",
        name: "GrubHub Subscription",
        description: "Dinner arrives before you finish ordering it.",
        kind: UpgradeKind::Automation,
        base_cost: 14_000.0,
        cost_growth: 1.15,
        power: 47.0,
        max_level: 0,
        unlock_tier: 1,
    },
    UpgradeDef {
        id: "vending_machine",
        name: "Bedroom Vending Machine",
        description: "Why walk to the kitchen at all?",
        kind: UpgradeKind::Automation,
        base_cost: 200_000.0,
        cost_growth: 1.15,
        power: 260.0,
        max_level: 0,
        unlock_tier: 2,
    },
    UpgradeDef {
        id: "ghost_kitchen",
        name: "Ghost Kitchen",
        description: "Twelve virtual restaurants, one very real fryer.",
        kind: UpgradeKind::Automation,
        base_cost: 3_300_000.0,
        cost_growth: 1.15,
        power: 1_400.0,
        max_level: 0,
        unlock_tier: 2,
    },
    UpgradeDef {
        id: "franchise",
        name: "Drive-Thru Franchise",
        description: "You are now technically a food system.",
        kind: UpgradeKind::Automation,
        base_cost: 51_000_000.0,
        cost_growth: 1.15,
        power: 7_800.0,
        max_level: 0,
        unlock_tier: 3,
    },
    // --- Click power --------------------------------------------------------
    UpgradeDef {
        id: "bigger_bites",
        name: "Bigger Bites",
        description: "+50% calories per click, compounding.",
        kind: UpgradeKind::ClickPower,
        base_cost: 500.0,
        cost_growth: 1.6,
        power: 0.5,
        max_level: 20,
        unlock_tier: 1,
    },
    UpgradeDef {
        id: "stretched_stomach",
        name: "Stretched Stomach",
        description: "+100% calories per click, compounding.",
        kind: UpgradeKind::ClickPower,
        base_cost: 25_000.0,
        cost_growth: 1.7,
        power: 1.0,
        max_level: 15,
        unlock_tier: 2,
    },
    UpgradeDef {
        id: "dead_taste_buds",
        name: "Retired Taste Buds",
        description: "+200% calories per click. Flavour is a formality.",
        kind: UpgradeKind::ClickPower,
        base_cost: 900_000.0,
        cost_growth: 1.8,
        power: 2.0,
        max_level: 10,
        unlock_tier: 3,
    },
    // --- Idle boost ---------------------------------------------------------
    UpgradeDef {
        id: "slow_metabolism",
        name: "Slower Metabolism",
        description: "+25% to everything your automation produces.",
        kind: UpgradeKind::IdleBoost,
        base_cost: 5_000.0,
        cost_growth: 2.0,
        power: 0.25,
        max_level: 12,
        unlock_tier: 1,
    },
    UpgradeDef {
        id: "recliner",
        name: "Permanent Recliner",
        description: "+50% to everything your automation produces.",
        kind: UpgradeKind::IdleBoost,
        base_cost: 400_000.0,
        cost_growth: 2.2,
        power: 0.5,
        max_level: 10,
        unlock_tier: 2,
    },
];

pub fn upgrade(id: &str) -> Option<&'static UpgradeDef> {
    UPGRADES.iter().find(|u| u.id == id)
}

// ---------------------------------------------------------------------------
// Achievements
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, Debug)]
pub enum Condition {
    /// Total manual clicks across the run.
    Clicks(u64),
    /// Current body weight in pounds.
    Weight(f64),
    /// Lifetime calories consumed.
    Lifetime(f64),
    /// Total automation levels owned across all sources.
    AutomationOwned(u32),
    /// Reached a given tier.
    Tier(u32),
    /// Calories per second from automation.
    Cps(f64),
}

pub struct AchievementDef {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    pub condition: Condition,
}

pub const ACHIEVEMENTS: &[AchievementDef] = &[
    AchievementDef {
        id: "first_bite",
        name: "First Bite",
        description: "Click anything at all.",
        condition: Condition::Clicks(1),
    },
    AchievementDef {
        id: "century_club",
        name: "Century Club",
        description: "100 manual clicks.",
        condition: Condition::Clicks(100),
    },
    AchievementDef {
        id: "repetitive_strain",
        name: "Repetitive Strain",
        description: "1,000 manual clicks.",
        condition: Condition::Clicks(1_000),
    },
    AchievementDef {
        id: "carpal_tunnel",
        name: "Carpal Tunnel",
        description: "10,000 manual clicks.",
        condition: Condition::Clicks(10_000),
    },
    AchievementDef {
        id: "hired_help",
        name: "Hired Help",
        description: "Buy your first automation.",
        condition: Condition::AutomationOwned(1),
    },
    AchievementDef {
        id: "supply_chain",
        name: "Supply Chain",
        description: "Own 25 automation levels.",
        condition: Condition::AutomationOwned(25),
    },
    AchievementDef {
        id: "logistics_empire",
        name: "Logistics Empire",
        description: "Own 100 automation levels.",
        condition: Condition::AutomationOwned(100),
    },
    AchievementDef {
        id: "hands_free",
        name: "Hands Free",
        description: "Reach 1,000 calories per second.",
        condition: Condition::Cps(1_000.0),
    },
    AchievementDef {
        id: "the_spread",
        name: "The Spread",
        description: "Reach 175 lbs.",
        condition: Condition::Weight(175.0),
    },
    AchievementDef {
        id: "load_bearing",
        name: "Load Bearing",
        description: "Reach 250 lbs.",
        condition: Condition::Weight(250.0),
    },
    AchievementDef {
        id: "quarter_ton",
        name: "Quarter Ton",
        description: "Reach 500 lbs.",
        condition: Condition::Weight(500.0),
    },
    AchievementDef {
        id: "six_figures",
        name: "Six Figures",
        description: "Consume 100,000 lifetime calories.",
        condition: Condition::Lifetime(100_000.0),
    },
    AchievementDef {
        id: "seven_figures",
        name: "Seven Figures",
        description: "Consume 1,000,000 lifetime calories.",
        condition: Condition::Lifetime(1_000_000.0),
    },
    AchievementDef {
        id: "nine_figures",
        name: "Nine Figures",
        description: "Consume 100,000,000 lifetime calories.",
        condition: Condition::Lifetime(100_000_000.0),
    },
    AchievementDef {
        id: "evolved_once",
        name: "Second Helping",
        description: "Reach tier 2.",
        condition: Condition::Tier(2),
    },
    AchievementDef {
        id: "evolved_twice",
        name: "Final Form",
        description: "Reach tier 3.",
        condition: Condition::Tier(3),
    },
];
