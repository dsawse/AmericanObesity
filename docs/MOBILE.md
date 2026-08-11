# Shipping American Obesity on mobile

Two very different stories. **Android you can do entirely from your Windows
machine today.** **iOS you cannot** — Apple requires compilation and signing on
macOS with Xcode, with no supported workaround. Both are covered below.

---

## Part 1 — Android

### 1.1 One-time toolchain setup

**Rust cross-compilation targets:**

```powershell
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cargo install cargo-ndk
```

**Android SDK + NDK.** Easiest through Android Studio (you never have to open a
project in it):

1. Install [Android Studio](https://developer.android.com/studio).
2. **More Actions → SDK Manager → SDK Tools** tab.
3. Tick **Android SDK Build-Tools**, **Android SDK Platform-Tools**,
   **Android SDK Command-line Tools**, and **NDK (Side by side)**. Apply.

**JDK 17.** Godot's Android exporter needs it specifically — not 8, not 21.
[Microsoft Build of OpenJDK 17](https://learn.microsoft.com/java/openjdk/download)
is a clean choice on Windows.

**Environment variable** for the NDK. Set it permanently via System Properties →
Environment Variables, or per-session:

```powershell
$env:ANDROID_NDK_HOME = "$env:LOCALAPPDATA\Android\Sdk\ndk\27.0.12077973"
```

Use whatever version number is actually in that folder.

### 1.2 Build the Rust extension

```powershell
cd C:\Users\Shadow\Documents\GitHub\AmericanObesity
powershell -ExecutionPolicy Bypass -File .\build-android.ps1
```

That produces `target\aarch64-linux-android\debug\libengine.so`, which is where
`amerobe/engine.gdextension` looks for it.

For a store build:

```powershell
.\build-android.ps1 -Release -Abi all
```

`-Abi all` adds armeabi-v7a (phones older than ~2017) and x86_64 (the emulator).
arm64 alone covers essentially every device sold today; adding the others costs
build time and roughly doubles the packaged library size.

### 1.3 Configure Godot for Android

**Export templates:** Editor → **Manage Export Templates → Download and Install**.
These must match your Godot version exactly (4.7.1).

**Editor Settings → Export → Android:**

| Setting | Value |
|---|---|
| Android SDK Path | `%LOCALAPPDATA%\Android\Sdk` |
| Java SDK Path | your JDK 17 install root |
| Debug Keystore | leave blank and press **Create Android Debug Keystore**, or point at `~/.android/debug.keystore` |

### 1.4 Create the export preset

**Project → Export → Add… → Android.** The settings that matter:

- **Unique Name**: `com.yourname.americanobesity` — this is permanent once
  published. Use a domain you control, reversed.
- **Version Code**: integer, must increase with every upload.
- **Version Name**: `1.0.0`, shown to users.
- **Min SDK**: 24. This matches the `--platform 24` in `build-android.ps1`;
  change both together or the library will fail to load on old devices.
- **Architectures**: tick exactly the ABIs you built. Ticking an ABI you did not
  build produces an APK that crashes on launch for that architecture, and you
  will not notice because your test device is arm64.
- **Permissions**: leave everything unticked. The game needs none — unless you
  enable Lightning, which needs **Internet**. Requesting permissions you do not
  use is a common review rejection.

Then **Export Project** for a testable APK, or tick **Export as AAB** for the
Play Store.

### 1.5 Test on a real device

```powershell
# Enable Developer Options + USB Debugging on the phone first.
adb install -r .\target\export\american-obesity.apk
adb logcat -s godot
```

That `logcat` line is the mobile equivalent of Godot's Output panel — it is
where you will see GDScript errors and the `[engine]::on_level_init() called`
line from the Rust extension. If the extension failed to load, you will see
`GDExtension dynamic library not found` here and the game will show the
"simulation engine not loaded" banner.

**Check specifically:**

- Portrait layout — the food grid should be 2 columns, tabs below.
- Rotate to landscape — should switch to the three-column desktop layout.
- Tap targets — every button has a 48px minimum height.
- Background the app for a few minutes, return — offline earnings toast fires.

### 1.6 Signing for release

Debug keys cannot be published. Generate a release keystore **once** and never
lose it — Play Store updates must be signed with the same key.

```powershell
keytool -genkey -v -keystore american-obesity-release.keystore `
  -alias americanobesity -keyalg RSA -keysize 2048 -validity 10000
```

Store it outside the repository. Add to `.gitignore`:

```
*.keystore
*.jks
```

In the export preset's **Keystore** section, point **Release** at the file and
fill in the user/password fields. Godot stores those in `export_presets.cfg`,
which is why that file must never be committed with real credentials — consider
using **Export → Export as .zip** of just the preset, or Godot's environment
variable overrides, for CI.

### 1.7 Google Play

- **$25 one-time** developer registration.
- **AAB required** for new apps, not APK.
- **Target API level**: Play enforces a minimum target API that rises annually.
  Godot's export template sets this; keeping Godot current keeps you compliant.
- **Content rating questionnaire**, **Data safety form**, and a **privacy
  policy URL** are mandatory even for a game that collects nothing. Say so
  honestly on the form — "no data collected" is a valid and fast answer.
- **Closed testing with 12 testers for 14 days** is required before a personal
  developer account can go to production. Budget for this; it surprises people.

On the **content** side, be aware this game's subject matter is a satire about
obesity. Play's policy prohibits content that bullies or demeans real
individuals; a satire of consumer culture is fine, but naming or caricaturing a
real person is not. The character art and any food names should stay generic.
That is worth deciding deliberately rather than discovering at review.

---

## Part 2 — iOS

### 2.1 The hard blocker

You cannot build, sign, or submit an iOS app from Windows. Apple's toolchain is
macOS-only. Your options:

| Route | Cost | Notes |
|---|---|---|
| Buy a Mac | ~$600+ | Mac mini is the cheap entry. Everything just works. |
| Rent a cloud Mac | ~$25-80/mo | MacStadium, MacinCloud, Scaleway. Full remote desktop. |
| GitHub Actions macOS runner | Free tier, then per-minute | Good for CI builds; painful for the first setup, since you are debugging blind. |

You also need the **Apple Developer Program, $99/year**, before you can install
on a physical device or use TestFlight.

### 2.2 The Rust side is different on iOS

iOS forbids loading arbitrary dynamic libraries, so the GDExtension must be a
**static** library rather than a `.so`/`.dll`.

Add the target and the crate type:

```bash
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
```

In `engine/Cargo.toml`:

```toml
[lib]
crate-type = ["cdylib", "staticlib", "rlib"]
```

`staticlib` is intentionally not enabled by default in this repo, because it
makes every desktop build slower for no benefit. Add it when you start iOS work.

```bash
cargo build -p engine --release --target aarch64-apple-ios
```

Then uncomment the `ios.*` block in `amerobe/engine.gdextension`.

### 2.3 Export

1. Godot → **Manage Export Templates** (the macOS editor build).
2. **Project → Export → Add… → iOS.**
3. Set **Bundle Identifier** to match an App ID in your Apple Developer account.
4. Export produces an **Xcode project**, not an `.ipa`.
5. Open it in Xcode, select your signing team, build to a device or Archive →
   Distribute for TestFlight.

### 2.4 App Store review notes

- **Lightning payments must be compiled out.** See below — this is not optional.
- Apple requires a privacy policy URL and a completed App Privacy questionnaire.
- Expect the satire angle to draw more scrutiny than on Play. Apple's guideline
  1.1.1 covers "defamatory, discriminatory, or mean-spirited content". Framing
  matters: a game satirising the food industry reads very differently from one
  mocking overweight people. The current copy leans toward the former; keep it
  there.

---

## Part 3 — Lightning and the app stores

This is the part where the plan and the platform rules collide, so it is worth
being precise.

### What Apple's guidelines say

App Review Guideline 3.1.1 states that apps "may not use their own mechanisms to
unlock content or functionality, such as license keys, augmented reality
markers, QR codes, **cryptocurrencies and cryptocurrency wallets**, etc."

That sentence is fatal to the obvious design. Paying an invoice to unlock a
premium food or a booster is exactly the prohibited pattern, and a Lightning QR
code manages to hit two of the named examples at once. Guideline 3.1.5(b)
permits crypto *transmission* only for licensed exchanges. There is no reading
under which an in-game Lightning shop passes iOS review.

### What Google says

Google's position moved substantially in 2026 following the Epic settlement.
Alternative billing systems are now permitted for digital goods in the US, UK
and EU (rolling out from 30 June 2026, with more regions through 2027), subject
to enrolment in the relevant programme and a service fee in the 9–20% range.
This is a genuine opening that did not exist a year ago, but it is a
*programme with rules*, not a free-for-all, and crypto specifically is not
called out either way. Treat it as "possible, verify before you rely on it".

### What this repo does about it

The Lightning integration is behind a compile-time flag and is **off by
default**. See `docs/LIGHTNING.md`. The three shipping configurations:

| Build | Lightning | Distribution |
|---|---|---|
| `store` (default) | compiled out | App Store, Play Store |
| `direct` | enabled | APK from your own site, itch.io |
| `desktop` | enabled | Windows/Linux/macOS builds |

The gate is a Godot **feature tag** plus a Cargo feature, so the store build
does not merely hide the UI — the networking code is not in the binary. That
distinction matters if a reviewer decompiles, and it matters more for your own
peace of mind.

---

## Quick reference

```powershell
# Desktop dev loop
cargo build --workspace

# Android debug build + install
.\build-android.ps1
adb install -r .\target\export\american-obesity.apk
adb logcat -s godot

# Android release
.\build-android.ps1 -Release -Abi all
# then Project > Export > Android > Export as AAB
```

Godot only reads `.gdextension` files at project load, and `reloadable = false`,
so **restart the editor after any Rust rebuild**. On Android there is no
equivalent shortcut: you re-export.
