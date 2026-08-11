//! Static content definitions for the clicker game.
//!
//! Everything the designer would want to tweak — food items, upgrades,
//! achievements and progression thresholds — lives here as plain data so the
//! simulation in [`super::state`] stays generic.
//!
//! Structure follows the original design document: five character states across
//! four weight classes, food organised into tiers, automation split into
//! subscriptions / appliances / partnerships, and achievements grouped by
//! category.

/// Calories in one pound of body weight.
pub const CALORIES_PER_POUND: f64 = 3500.0;

/// Weight the player starts at, in pounds.
///
/// The design document says 130 lbs in one place and "Base model (150 lbs)"
/// with a "Beginner (150-250 lbs)" weight class in another. 150 is used here
/// because it is consistent with both the class table and the character states.
pub const STARTING_WEIGHT_LBS: f64 = 150.0;

/// Weight (lbs) required to advance *into* tier 2, 3, 4, 5 respectively.
/// `TIER_THRESHOLDS[0]` is the requirement to reach tier 2.
pub const TIER_THRESHOLDS: &[f64] = &[250.0, 500.0, 750.0, 1000.0];

/// Highest tier reachable. Tier 1 is the starting kitchen.
pub const MAX_TIER: u32 = 5;

/// Idle earnings are granted at this fraction of the online rate.
pub const OFFLINE_EFFICIENCY: f64 = 0.5;

/// Idle earnings are capped at this many seconds away (8 hours).
pub const OFFLINE_CAP_SECONDS: f64 = 8.0 * 60.0 * 60.0;

/// Display name for each tier's kitchen, indexed from tier 1.
pub const TIER_NAMES: &[&str] = &[
    "Your Average Kitchen",
    "The Comfort Food Era",
    "State Fair Territory",
    "Industrial Appetite",
    "The Final Buffet",
];

/// Weight-class name for a given body weight, per the design document.
pub fn weight_class(lbs: f64) -> &'static str {
    if lbs >= 1000.0 {
        "Ultimate Glutton"
    } else if lbs >= 500.0 {
        "Super Size"
    } else if lbs >= 250.0 {
        "Heavyweight"
    } else {
        "Beginner"
    }
}

/// Character-state name, which changes more often than the weight class.
pub fn character_state(lbs: f64) -> &'static str {
    if lbs >= 1000.0 {
        "Ultimate"
    } else if lbs >= 750.0 {
        "Massive"
    } else if lbs >= 500.0 {
        "Heavy"
    } else if lbs >= 250.0 {
        "Chunky"
    } else {
        "Base"
    }
}

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
    // --- Tier 1: Fast Food --------------------------------------------------
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
        name: "Soft Drink",
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
    // --- Tier 2: Comfort Food -----------------------------------------------
    FoodDef {
        id: "pizza",
        name: "Pizza",
        calories: 1_200.0,
        cooldown: 1.0,
        unlock_tier: 2,
        color: "#d9662b",
    },
    FoodDef {
        id: "ice_cream",
        name: "Ice Cream",
        calories: 2_000.0,
        cooldown: 1.2,
        unlock_tier: 2,
        color: "#f2c9d8",
    },
    FoodDef {
        id: "fried_chicken",
        name: "Fried Chicken",
        calories: 3_500.0,
        cooldown: 1.5,
        unlock_tier: 2,
        color: "#c98a2e",
    },
    // --- Tier 3: Extreme Foods ----------------------------------------------
    FoodDef {
        id: "fried_butter",
        name: "Deep-Fried Butter",
        calories: 9_000.0,
        cooldown: 2.0,
        unlock_tier: 3,
        color: "#f5e05a",
    },
    FoodDef {
        id: "triple_burger",
        name: "Triple Burger",
        calories: 16_000.0,
        cooldown: 2.5,
        unlock_tier: 3,
        color: "#7b4a1e",
    },
    FoodDef {
        id: "mega_shake",
        name: "Mega Shake",
        calories: 30_000.0,
        cooldown: 3.0,
        unlock_tier: 3,
        color: "#b06fc4",
    },
    // --- Tier 4: Super Size -------------------------------------------------
    FoodDef {
        id: "family_bucket",
        name: "Family Bucket",
        calories: 75_000.0,
        cooldown: 3.0,
        unlock_tier: 4,
        color: "#b03030",
    },
    FoodDef {
        id: "loaded_nachos",
        name: "Loaded Nachos",
        calories: 130_000.0,
        cooldown: 3.5,
        unlock_tier: 4,
        color: "#f0a500",
    },
    FoodDef {
        id: "sheet_cake",
        name: "Whole Sheet Cake",
        calories: 240_000.0,
        cooldown: 4.0,
        unlock_tier: 4,
        color: "#e58ac0",
    },
    // --- Tier 5: Legendary --------------------------------------------------
    FoodDef {
        id: "gravy_fountain",
        name: "Gravy Fountain",
        calories: 900_000.0,
        cooldown: 4.0,
        unlock_tier: 5,
        color: "#8a6234",
    },
    FoodDef {
        id: "whole_hog",
        name: "The Whole Hog",
        calories: 1_800_000.0,
        cooldown: 4.5,
        unlock_tier: 5,
        color: "#d98c8c",
    },
    FoodDef {
        id: "entire_buffet",
        name: "The Entire Buffet",
        calories: 4_000_000.0,
        cooldown: 5.0,
        unlock_tier: 5,
        color: "#f2e2b8",
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

/// Shop grouping, mirroring the design document's automation categories.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum UpgradeCategory {
    Subscription,
    Appliance,
    Partnership,
    Body,
    Lifestyle,
}

impl UpgradeCategory {
    pub fn as_str(self) -> &'static str {
        match self {
            UpgradeCategory::Subscription => "Fast Food Subscriptions",
            UpgradeCategory::Appliance => "Kitchen Appliances",
            UpgradeCategory::Partnership => "Restaurant Partnerships",
            UpgradeCategory::Body => "Body Modifications",
            UpgradeCategory::Lifestyle => "Lifestyle Choices",
        }
    }

    /// Display order in the shop.
    pub fn sort_key(self) -> u32 {
        match self {
            UpgradeCategory::Subscription => 0,
            UpgradeCategory::Appliance => 1,
            UpgradeCategory::Partnership => 2,
            UpgradeCategory::Body => 3,
            UpgradeCategory::Lifestyle => 4,
        }
    }
}

pub struct UpgradeDef {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    pub kind: UpgradeKind,
    pub category: UpgradeCategory,
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
    // --- Kitchen Appliances -------------------------------------------------
    UpgradeDef {
        id: "microwave",
        name: "Microwave",
        description: "Reheats leftovers around the clock.",
        kind: UpgradeKind::Automation,
        category: UpgradeCategory::Appliance,
        base_cost: 100.0,
        cost_growth: 1.15,
        power: 1.0,
        max_level: 0,
        unlock_tier: 1,
    },
    UpgradeDef {
        id: "deep_fryer",
        name: "Deep Fryer",
        description: "Anything is food if you are brave enough.",
        kind: UpgradeKind::Automation,
        category: UpgradeCategory::Appliance,
        base_cost: 14_000.0,
        cost_growth: 1.15,
        power: 47.0,
        max_level: 0,
        unlock_tier: 1,
    },
    UpgradeDef {
        id: "industrial_grill",
        name: "Industrial Grill",
        description: "Continuous cooking. It never actually turns off.",
        kind: UpgradeKind::Automation,
        category: UpgradeCategory::Appliance,
        base_cost: 51_000_000.0,
        cost_growth: 1.15,
        power: 7_800.0,
        max_level: 0,
        unlock_tier: 3,
    },
    // --- Fast Food Subscriptions --------------------------------------------
    UpgradeDef {
        id: "mcdoordash",
        name: "McDoorDash",
        description: "A driver is always three minutes away.",
        kind: UpgradeKind::Automation,
        category: UpgradeCategory::Subscription,
        base_cost: 1_200.0,
        cost_growth: 1.15,
        power: 8.0,
        max_level: 0,
        unlock_tier: 1,
    },
    UpgradeDef {
        id: "uberfeasts",
        name: "UberFeasts",
        description: "Dinner arrives before you finish ordering it.",
        kind: UpgradeKind::Automation,
        category: UpgradeCategory::Subscription,
        base_cost: 200_000.0,
        cost_growth: 1.15,
        power: 260.0,
        max_level: 0,
        unlock_tier: 2,
    },
    UpgradeDef {
        id: "grubsquad",
        name: "GrubSquad",
        description: "A standing order. Nobody remembers placing it.",
        kind: UpgradeKind::Automation,
        category: UpgradeCategory::Subscription,
        base_cost: 750_000_000.0,
        cost_growth: 1.15,
        power: 44_000.0,
        max_level: 0,
        unlock_tier: 3,
    },
    // --- Restaurant Partnerships --------------------------------------------
    UpgradeDef {
        id: "local_diner",
        name: "Local Diner",
        description: "They named a booth after you. Then a menu.",
        kind: UpgradeKind::Automation,
        category: UpgradeCategory::Partnership,
        base_cost: 3_300_000.0,
        cost_growth: 1.15,
        power: 1_400.0,
        max_level: 0,
        unlock_tier: 2,
    },
    UpgradeDef {
        id: "franchise",
        name: "Fast Food Franchise",
        description: "You are now technically a food system.",
        kind: UpgradeKind::Automation,
        category: UpgradeCategory::Partnership,
        base_cost: 10_000_000_000.0,
        cost_growth: 1.15,
        power: 260_000.0,
        max_level: 0,
        unlock_tier: 4,
    },
    UpgradeDef {
        id: "buffet",
        name: "All-You-Can-Eat Buffet",
        description: "The sign was a challenge and you accepted it.",
        kind: UpgradeKind::Automation,
        category: UpgradeCategory::Partnership,
        base_cost: 140_000_000_000.0,
        cost_growth: 1.15,
        power: 1_600_000.0,
        max_level: 0,
        unlock_tier: 5,
    },
    // --- Body Modifications (click power) -----------------------------------
    UpgradeDef {
        id: "bigger_bites",
        name: "Bigger Bites",
        description: "+50% calories per click, compounding.",
        kind: UpgradeKind::ClickPower,
        category: UpgradeCategory::Body,
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
        category: UpgradeCategory::Body,
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
        category: UpgradeCategory::Body,
        base_cost: 900_000.0,
        cost_growth: 1.8,
        power: 2.0,
        max_level: 10,
        unlock_tier: 3,
    },
    UpgradeDef {
        id: "jaw_of_steel",
        name: "Jaw of Steel",
        description: "+400% calories per click. Chewing is now optional.",
        kind: UpgradeKind::ClickPower,
        category: UpgradeCategory::Body,
        base_cost: 50_000_000.0,
        cost_growth: 1.9,
        power: 4.0,
        max_level: 10,
        unlock_tier: 4,
    },
    // --- Lifestyle Choices (idle boost) -------------------------------------
    UpgradeDef {
        id: "slow_metabolism",
        name: "Slower Metabolism",
        description: "+25% to everything your automation produces.",
        kind: UpgradeKind::IdleBoost,
        category: UpgradeCategory::Lifestyle,
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
        category: UpgradeCategory::Lifestyle,
        base_cost: 400_000.0,
        cost_growth: 2.2,
        power: 0.5,
        max_level: 10,
        unlock_tier: 2,
    },
    UpgradeDef {
        id: "mobility_scooter",
        name: "Mobility Scooter",
        description: "+100% idle output. Walking was the bottleneck.",
        kind: UpgradeKind::IdleBoost,
        category: UpgradeCategory::Lifestyle,
        base_cost: 90_000_000.0,
        cost_growth: 2.4,
        power: 1.0,
        max_level: 8,
        unlock_tier: 4,
    },
];

pub fn upgrade(id: &str) -> Option<&'static UpgradeDef> {
    UPGRADES.iter().find(|u| u.id == id)
}

// ---------------------------------------------------------------------------
// Premium content
// ---------------------------------------------------------------------------
//
// Bought with Lightning in direct-download and desktop builds. App-store builds
// compile the payment UI out entirely (see docs/LIGHTNING.md), but the
// definitions stay here so a save file created on desktop still loads on a
// phone — the entitlements just cannot be *acquired* in a store build.

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum PremiumKind {
    /// Multiplies calories from manual clicks.
    ClickMultiplier,
    /// Multiplies passive output.
    IdleMultiplier,
    /// Raises the offline earnings cap, in hours.
    OfflineHours,
    /// No gameplay effect.
    Cosmetic,
}

impl PremiumKind {
    pub fn as_str(self) -> &'static str {
        match self {
            PremiumKind::ClickMultiplier => "click_multiplier",
            PremiumKind::IdleMultiplier => "idle_multiplier",
            PremiumKind::OfflineHours => "offline_hours",
            PremiumKind::Cosmetic => "cosmetic",
        }
    }
}

pub struct PremiumDef {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    /// Price in satoshis.
    pub sats: u64,
    pub kind: PremiumKind,
    /// Multiplier for the multiplier kinds; hours for `OfflineHours`.
    pub power: f64,
}

pub const PREMIUM: &[PremiumDef] = &[
    PremiumDef {
        id: "golden_spatula",
        name: "Golden Spatula",
        description: "Doubles the calories from every manual click, forever.",
        sats: 2_000,
        kind: PremiumKind::ClickMultiplier,
        power: 2.0,
    },
    PremiumDef {
        id: "grease_trap",
        name: "Bottomless Grease Trap",
        description: "Doubles everything your automation produces, forever.",
        sats: 5_000,
        kind: PremiumKind::IdleMultiplier,
        power: 2.0,
    },
    PremiumDef {
        id: "deep_freezer",
        name: "Chest Freezer",
        description: "Offline earnings accrue for 24 hours instead of 8.",
        sats: 3_000,
        kind: PremiumKind::OfflineHours,
        power: 24.0,
    },
    PremiumDef {
        id: "neon_kitchen",
        name: "Neon Kitchen",
        description: "A garish alternate colour scheme. Purely cosmetic.",
        sats: 1_000,
        kind: PremiumKind::Cosmetic,
        power: 0.0,
    },
    PremiumDef {
        id: "supporter_badge",
        name: "Supporter Badge",
        description: "Buys nothing. Says thank you. Shown on the title screen.",
        sats: 500,
        kind: PremiumKind::Cosmetic,
        power: 0.0,
    },
];

pub fn premium(id: &str) -> Option<&'static PremiumDef> {
    PREMIUM.iter().find(|p| p.id == id)
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
    /// Levels owned of one specific upgrade.
    UpgradeLevel(&'static str, u32),
    /// Reached a given tier.
    Tier(u32),
    /// Calories per second from automation.
    Cps(f64),
    /// Click multiplier reached.
    ClickPower(f64),
    /// Clicks on one specific food item.
    FoodClicks(&'static str, u64),
    /// Total clicks across every food in a tier.
    TierFoodClicks(u32, u64),
    /// Calories held in the bank at once.
    Banked(f64),
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum AchievementCategory {
    Weight,
    Clicking,
    FoodMastery,
    Automation,
    Wealth,
}

impl AchievementCategory {
    pub fn as_str(self) -> &'static str {
        match self {
            AchievementCategory::Weight => "Weight Milestones",
            AchievementCategory::Clicking => "Clicking",
            AchievementCategory::FoodMastery => "Food Mastery",
            AchievementCategory::Automation => "Automation Excellence",
            AchievementCategory::Wealth => "Excess",
        }
    }

    pub fn sort_key(self) -> u32 {
        match self {
            AchievementCategory::Weight => 0,
            AchievementCategory::FoodMastery => 1,
            AchievementCategory::Automation => 2,
            AchievementCategory::Clicking => 3,
            AchievementCategory::Wealth => 4,
        }
    }
}

pub struct AchievementDef {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    pub category: AchievementCategory,
    pub condition: Condition,
}

pub const ACHIEVEMENTS: &[AchievementDef] = &[
    // --- Weight Milestones --------------------------------------------------
    AchievementDef {
        id: "baby_steps",
        name: "Baby Steps",
        description: "Reach 200 lbs.",
        category: AchievementCategory::Weight,
        condition: Condition::Weight(200.0),
    },
    AchievementDef {
        id: "heavyweight",
        name: "Heavyweight",
        description: "Reach 250 lbs and leave the beginner class behind.",
        category: AchievementCategory::Weight,
        condition: Condition::Weight(250.0),
    },
    AchievementDef {
        id: "sister_status",
        name: "Sister Status",
        description: "Reach 500 lbs. You know the show.",
        category: AchievementCategory::Weight,
        condition: Condition::Weight(500.0),
    },
    AchievementDef {
        id: "massive",
        name: "Structurally Concerning",
        description: "Reach 750 lbs.",
        category: AchievementCategory::Weight,
        condition: Condition::Weight(750.0),
    },
    AchievementDef {
        id: "absolute_unit",
        name: "Absolute Unit",
        description: "Reach 1,000 lbs.",
        category: AchievementCategory::Weight,
        condition: Condition::Weight(1_000.0),
    },
    AchievementDef {
        id: "beyond_the_scale",
        name: "Beyond the Scale",
        description: "Reach 5,000 lbs. The scale gave up. You did not.",
        category: AchievementCategory::Weight,
        condition: Condition::Weight(5_000.0),
    },
    AchievementDef {
        id: "own_gravity",
        name: "Your Own Gravity",
        description: "Reach 25,000 lbs.",
        category: AchievementCategory::Weight,
        condition: Condition::Weight(25_000.0),
    },
    // --- Food Mastery -------------------------------------------------------
    AchievementDef {
        id: "fast_food_fanatic",
        name: "Fast Food Fanatic",
        description: "500 clicks on tier 1 food.",
        category: AchievementCategory::FoodMastery,
        condition: Condition::TierFoodClicks(1, 500),
    },
    AchievementDef {
        id: "comfort_food_king",
        name: "Comfort Food King",
        description: "500 clicks on tier 2 food.",
        category: AchievementCategory::FoodMastery,
        condition: Condition::TierFoodClicks(2, 500),
    },
    AchievementDef {
        id: "extreme_eater",
        name: "Extreme Eater",
        description: "500 clicks on tier 3 food.",
        category: AchievementCategory::FoodMastery,
        condition: Condition::TierFoodClicks(3, 500),
    },
    AchievementDef {
        id: "super_sizer",
        name: "Super Sizer",
        description: "500 clicks on tier 4 food.",
        category: AchievementCategory::FoodMastery,
        condition: Condition::TierFoodClicks(4, 500),
    },
    AchievementDef {
        id: "legend_eater",
        name: "Living Legend",
        description: "500 clicks on tier 5 food.",
        category: AchievementCategory::FoodMastery,
        condition: Condition::TierFoodClicks(5, 500),
    },
    AchievementDef {
        id: "fry_guy",
        name: "Fry Guy",
        description: "1,000 orders of fries.",
        category: AchievementCategory::FoodMastery,
        condition: Condition::FoodClicks("fries", 1_000),
    },
    AchievementDef {
        id: "butter_believer",
        name: "Butter Believer",
        description: "250 sticks of deep-fried butter.",
        category: AchievementCategory::FoodMastery,
        condition: Condition::FoodClicks("fried_butter", 250),
    },
    AchievementDef {
        id: "hog_wild",
        name: "Hog Wild",
        description: "100 whole hogs.",
        category: AchievementCategory::FoodMastery,
        condition: Condition::FoodClicks("whole_hog", 100),
    },
    // --- Automation Excellence ----------------------------------------------
    AchievementDef {
        id: "automated_appetite",
        name: "Automated Appetite",
        description: "Buy your first automation.",
        category: AchievementCategory::Automation,
        condition: Condition::AutomationOwned(1),
    },
    AchievementDef {
        id: "machine_master",
        name: "Machine Master",
        description: "Own 50 automation levels.",
        category: AchievementCategory::Automation,
        condition: Condition::AutomationOwned(50),
    },
    AchievementDef {
        id: "industrial_eater",
        name: "Industrial Eater",
        description: "Own 200 automation levels.",
        category: AchievementCategory::Automation,
        condition: Condition::AutomationOwned(200),
    },
    AchievementDef {
        id: "logistics_empire",
        name: "Logistics Empire",
        description: "Own 500 automation levels.",
        category: AchievementCategory::Automation,
        condition: Condition::AutomationOwned(500),
    },
    AchievementDef {
        id: "hands_free",
        name: "Hands Free",
        description: "Reach 1,000 calories per second.",
        category: AchievementCategory::Automation,
        condition: Condition::Cps(1_000.0),
    },
    AchievementDef {
        id: "conveyor_belt",
        name: "Conveyor Belt",
        description: "Reach 1,000,000 calories per second.",
        category: AchievementCategory::Automation,
        condition: Condition::Cps(1_000_000.0),
    },
    AchievementDef {
        id: "franchise_owner",
        name: "Franchise Owner",
        description: "Own 10 Fast Food Franchises.",
        category: AchievementCategory::Automation,
        condition: Condition::UpgradeLevel("franchise", 10),
    },
    AchievementDef {
        id: "buffet_baron",
        name: "Buffet Baron",
        description: "Own 5 All-You-Can-Eat Buffets.",
        category: AchievementCategory::Automation,
        condition: Condition::UpgradeLevel("buffet", 5),
    },
    // --- Clicking -----------------------------------------------------------
    AchievementDef {
        id: "first_bite",
        name: "First Bite",
        description: "Click anything at all.",
        category: AchievementCategory::Clicking,
        condition: Condition::Clicks(1),
    },
    AchievementDef {
        id: "century_club",
        name: "Century Club",
        description: "100 manual clicks.",
        category: AchievementCategory::Clicking,
        condition: Condition::Clicks(100),
    },
    AchievementDef {
        id: "repetitive_strain",
        name: "Repetitive Strain",
        description: "1,000 manual clicks.",
        category: AchievementCategory::Clicking,
        condition: Condition::Clicks(1_000),
    },
    AchievementDef {
        id: "carpal_tunnel",
        name: "Carpal Tunnel",
        description: "10,000 manual clicks.",
        category: AchievementCategory::Clicking,
        condition: Condition::Clicks(10_000),
    },
    AchievementDef {
        id: "heavy_hitter",
        name: "Heavy Hitter",
        description: "Reach a x50 click multiplier.",
        category: AchievementCategory::Clicking,
        condition: Condition::ClickPower(50.0),
    },
    AchievementDef {
        id: "one_punch",
        name: "One Bite Wonder",
        description: "Reach a x1,000 click multiplier.",
        category: AchievementCategory::Clicking,
        condition: Condition::ClickPower(1_000.0),
    },
    // --- Excess -------------------------------------------------------------
    AchievementDef {
        id: "six_figures",
        name: "Six Figures",
        description: "Consume 100,000 lifetime calories.",
        category: AchievementCategory::Wealth,
        condition: Condition::Lifetime(100_000.0),
    },
    AchievementDef {
        id: "seven_figures",
        name: "Seven Figures",
        description: "Consume 1,000,000 lifetime calories.",
        category: AchievementCategory::Wealth,
        condition: Condition::Lifetime(1_000_000.0),
    },
    AchievementDef {
        id: "nine_figures",
        name: "Nine Figures",
        description: "Consume 100,000,000 lifetime calories.",
        category: AchievementCategory::Wealth,
        condition: Condition::Lifetime(100_000_000.0),
    },
    AchievementDef {
        id: "twelve_figures",
        name: "Twelve Figures",
        description: "Consume 1,000,000,000,000 lifetime calories.",
        category: AchievementCategory::Wealth,
        condition: Condition::Lifetime(1_000_000_000_000.0),
    },
    AchievementDef {
        id: "hoarder",
        name: "Hoarder",
        description: "Hold 1,000,000 calories in the bank at once.",
        category: AchievementCategory::Wealth,
        condition: Condition::Banked(1_000_000.0),
    },
    AchievementDef {
        id: "final_form",
        name: "Final Form",
        description: "Reach tier 5.",
        category: AchievementCategory::Wealth,
        condition: Condition::Tier(5),
    },
];
