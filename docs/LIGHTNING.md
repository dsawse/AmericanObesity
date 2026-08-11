# Lightning payments

Premium items are paid for over the Bitcoin Lightning Network: no account, no
card, no personal data, settlement in about a second, and fees measured in
fractions of a cent.

This document covers the platform rules first, because they constrain
everything else.

---

## 1. Where this is allowed

### iOS — not allowed. Not "risky". Not allowed.

App Review Guideline 3.1.1 states that apps "may not use their own mechanisms to
unlock content or functionality, such as license keys, augmented reality
markers, QR codes, **cryptocurrencies and cryptocurrency wallets**, etc."

Paying an invoice to unlock the Golden Spatula is precisely that pattern. There
is no framing, wording or architecture that makes it pass. Guideline 3.1.5(b)
permits crypto *transmission* only for licensed exchanges, which a game is not.

If you want paid content on iOS it has to be StoreKit in-app purchase, at
Apple's commission.

### Android — a real option, with rules

Google's position changed substantially in 2026 after the Epic settlement.
Alternative billing for digital goods is now permitted for users in the US, UK
and EU (rolling out from 30 June 2026, further regions through 2027), subject to
enrolling in the programme and a service fee generally in the 9–20% band.

That is a genuine opening. It is also a *programme with requirements*, and it
does not specifically bless cryptocurrency. Verify against
[Play's payments policy](https://support.google.com/googleplay/android-developer/answer/10281818)
before you rely on it, and assume it may move again.

### Direct download and desktop — no restrictions

An APK on your own site, an itch.io build, a Windows/Linux/macOS build: nobody's
payment rules apply. This is where Lightning actually shines, and it is what the
default configuration targets.

Note that Steam separately prohibits applications built on blockchain
technology or that let users exchange cryptocurrency, so Steam is not a route
for this either.

---

## 2. How the gate works

The switch is [`LightningClient.is_available()`](../amerobe/Scripts/lightning.gd):

```gdscript
static func is_available() -> bool:
	if OS.has_feature("store_build"):
		return false
	return OS.has_feature("lightning") or OS.has_feature("editor")
```

`store_build` and `lightning` are **custom feature tags** you set per export
preset in Godot: **Project → Export → [preset] → Feature Tags**.

| Preset | Feature tags | Result |
|---|---|---|
| Android — Play Store | `store_build` | No payment code path, no Support button |
| Android — Direct APK | `lightning` | Full Lightning flow |
| Windows / Linux / macOS | `lightning` | Full Lightning flow |
| iOS | `store_build` | No payment code path |

Three things are gated, not one:

1. `SceneManager` does not create the `LightningClient` node, so no HTTP client
   and no polling timer exist.
2. `arena.gd` does not add the **Support** button.
3. `PremiumShop` is never instantiated.

The premium *definitions* stay in the Rust binary deliberately. A save file
created on desktop must still load on a phone — the entitlements are simply
un-buyable there rather than causing a parse failure.

**Be aware of the honest limitation:** feature tags gate behaviour, not bytes.
`lightning.gd` still ships inside the store build's PCK. If you want the code
genuinely absent, exclude it with an export filter
(**Resources → Filters to exclude files**: `Scripts/lightning.gd,Scripts/premium_shop.gd`)
and guard the two references with `ResourceLoader.exists()`. For most purposes
the behavioural gate is sufficient; the filter is belt-and-braces.

---

## 3. Backend setup

The game **never holds a node, a seed, or a spending key.** It talks to a
backend you control, using an invoice-only API key.

### Option A — LNbits (recommended to start)

[LNbits](https://lnbits.com) is a small self-hostable wallet layer that sits in
front of a Lightning node or a funding source.

1. Use a hosted instance to try it, or self-host with Docker.
2. Create a wallet for the game.
3. Open the wallet's **API info** panel. You will see two keys:
   - **Invoice/read key** — can create invoices and check their status.
   - **Admin key** — can *spend*.
4. **Only ever put the invoice/read key in the client.** If the admin key ends
   up in a shipped binary, anyone who unzips your APK can drain the wallet.

### Option B — a thin proxy you control

Better for anything beyond a hobby launch. Your server holds the key; the game
calls two endpoints of your own design. This lets you record which invoice
corresponds to which purchase server-side, which is the only way to make
entitlements tamper-resistant (see §5).

The client speaks the LNbits shape, so a proxy just needs to expose:

```
POST /api/v1/payments        -> { "payment_hash": "...", "payment_request": "lnbc..." }
GET  /api/v1/payments/<hash> -> { "paid": true|false }
```

### Option C — a custodial API

OpenNode, Strike, Zaprite and similar handle the node for you and can settle to
fiat. Simplest operationally, but you are trusting a third party with custody
and you inherit their KYC requirements.

---

## 4. Configuring a build

Configuration lives in `user://lightning.cfg`, **not** in the binary, so you can
repoint a build without recompiling. On first run the game writes an empty
template there.

On Windows that is:

```
%APPDATA%\Godot\app_userdata\amerobe\lightning.cfg
```

```ini
[backend]

base_url="https://your-lnbits-instance.example.com"
invoice_key="your_invoice_read_key_here"
```

Until both are filled in, `is_configured()` returns false and the premium shop
shows an explanatory notice instead of buy buttons.

**Android also needs the Internet permission.** In the export preset, tick
**Permissions → Internet**. Without it every request fails with a network error
and the cause is not obvious from inside the game.

---

## 5. Threat model — read this before charging anyone

**Entitlements are stored client-side and are trivially forgeable.**
`user://progress.save` is plain JSON. Anyone can add `"entitlements":
["golden_spatula"]` and get the item free.

For a single-player idle game this is an acceptable trade, and it is the same
posture as most premium mobile games. Cheating hurts only the cheater. But be
clear-eyed:

- Do **not** extend this design to anything with real scarcity, tradeable
  goods, or a multiplayer economy.
- If you need real enforcement, entitlements must live server-side behind an
  account, and the client must ask the server what it owns on every launch.
  That means running accounts, which means handling personal data, which is a
  meaningfully bigger project.

**What the current design does get right:**

- No spending key in the client. The worst an attacker can do with the invoice
  key is create invoices payable to *you*, and read their status.
- `grant_entitlement()` returns `false` for an already-owned item, so a replayed
  or duplicated settlement callback cannot double-apply.
- Unknown ids are stripped on load, so a hand-edited save cannot inject a
  phantom multiplier.
- The invoice expires after 10 minutes client-side and polling stops.

**What it does not do:**

- No verification that the settled invoice is the one this client requested.
  A proxy that records `payment_hash → item` at creation time closes this.
- No receipt or restore-purchases flow. Wipe your save and your purchases are
  gone. This is the single most likely thing to generate an angry email, so
  either implement restore (which needs server-side records) or say so plainly
  at the point of sale.

---

## 6. The purchase flow in code

```
PremiumShop._on_buy_pressed()
        │
        ▼
LightningClient.request_invoice(item_id, sats, memo)
        │  POST /api/v1/payments
        ▼
    invoice_ready(item_id, bolt11, sats)
        │  UI shows invoice + "Open in wallet"
        │  polls GET /api/v1/payments/<hash> every 2s
        ▼
    payment_settled(item_id)
        │
        ▼
SceneManager.grant_entitlement(id)  ->  Rust records it in SaveState
SceneManager.save_game()
```

There is deliberately **no QR code**. On mobile — the primary target — a
`lightning:` deep link is strictly better UX: `OS.shell_open("lightning:" + bolt11)`
opens the installed wallet with the amount pre-filled, no camera involved. On
desktop the invoice is shown as selectable text with a copy button.

If you later want a QR for desktop-to-phone scanning, use an existing addon
rather than writing an encoder — QR needs Reed-Solomon error correction and is
about 500 lines of easy-to-get-subtly-wrong code.

---

## 7. Testing without spending money

1. Point `base_url` at an LNbits instance running on **signet** or **testnet**.
2. Pay invoices with a testnet wallet.
3. For pure UI work, stub it: make `_on_create_completed` emit a fake
   `invoice_ready`, then fire `payment_settled` after a few seconds. That
   exercises the whole UI path with no network at all.

Before charging a real person, verify end to end on mainnet with a 1-sat item.

---

## 8. Pricing

Current catalogue, in `engine/src/clicker_game/defs.rs`:

| Item | Sats | Effect |
|---|---:|---|
| Supporter Badge | 500 | Cosmetic only |
| Neon Kitchen | 1,000 | Cosmetic palette |
| Golden Spatula | 2,000 | x2 click power, permanent |
| Chest Freezer | 3,000 | Offline cap 8h → 24h |
| Bottomless Grease Trap | 5,000 | x2 idle output, permanent |

Prices are in satoshis and therefore float against fiat. At $100k/BTC, 1,000
sats is about $1. If you want stable fiat pricing, compute the sat amount
server-side from a live rate at invoice creation — do not hard-code it as the
catalogue does now.

Note that these are all *permanent, non-consumable* items. That is a deliberate
choice: consumables and subscriptions create refund and restore expectations
that a client-side entitlement model cannot honour.
