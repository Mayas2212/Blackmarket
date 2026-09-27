# BLACKMARKET

A native SwiftUI + SwiftData underground business-sim game for iOS.
Buy → Resell → Profit → Reputation → Unlock → Expand → Repeat.

Everything is fictional (products, NPCs, "BTC" is a simulated in-game
currency only — no real crypto or payments are involved anywhere).

## What's in here

```
BlackMarket/
  BlackMarketApp.swift        App entry point, SwiftData container
  Models/Models.swift         @Model persistence: player, inventory, listings,
                               transactions, follows, reviews, messages,
                               market events, prices, achievements, objectives
  Core/GameData.swift         Static catalog: products, suppliers, NPCs,
                               seller levels, achievement defs
  Core/GameEngine.swift       ALL gameplay logic: buy/sell, pricing,
                               reputation/leveling, events, BTC exchange,
                               objectives, stats, admin/dev tools
  Utilities/Formatters.swift  Currency/number/date formatting
  Views/
    RootView.swift            5-tab TabView (Home / Market / Network / Business / Profile)
    Home/                     Activity feed, balances, daily objectives, BTC exchange
    Market/                   Browse + buy products, supplier picker
    Network/                  Underground "social" layer: NPCs, follow, reviews, DMs
    Business/                 Swift Charts: revenue/profit/margin, inventory, listings
    Profile/                  Identity, achievements, your shop/listings
    Admin/                    Hidden dev/testing panel
    Components/               Shared card/pill/badge UI pieces
project.yml                   XcodeGen spec — generates the .xcodeproj
                               (used locally or in CI; not committed itself)
.github/workflows/ios-build.yml   GitHub Actions: builds this on GitHub's
                               macOS runners so you can build from Windows
.gitignore                    Excludes the generated .xcodeproj/build output
```

## Building on a Mac (if you have one)

This is delivered as source files rather than a prebuilt `.xcodeproj`
(project files are fragile to hand-generate). It takes about 2 minutes
to wire up:

1. Open Xcode → **File → New → Project → iOS → App**.
2. Name it `BlackMarket`. Interface: **SwiftUI**. Set the minimum
   deployment target to **iOS 17.0** (required for `@Observable` and
   SwiftData). Do NOT check "Use Core Data" — this project uses SwiftData.
3. Delete the default `ContentView.swift` and the generated
   `BlackMarketApp.swift` that Xcode creates.
4. Drag the entire contents of the inner `BlackMarket/` folder (the one
   containing `BlackMarketApp.swift`, `Models/`, `Core/`, `Utilities/`,
   `Views/`) into your Xcode project navigator. Check
   **"Copy items if needed"** and make sure your app target is checked.
5. Build & run on an iOS 17+ simulator or device.

That's it — no external dependencies, no server, no signing beyond the
usual free personal team for local testing.

## Building on Windows, via GitHub Actions

Xcode itself only runs on macOS, so Windows can't compile this directly —
but this repo includes a GitHub Actions workflow that builds it for you
on GitHub's own macOS machines. From Windows you only need Git (or
GitHub Desktop) and a web browser.

### 1. Push this project to GitHub

Install [Git for Windows](https://git-scm.com/download/win) or
[GitHub Desktop](https://desktop.github.com/) if you don't have either.
From a terminal (PowerShell, Git Bash, or cmd) inside this unzipped
folder:

```powershell
git init
git add .
git commit -m "Initial BLACKMARKET commit"
git branch -M main
git remote add origin https://github.com/<your-username>/<your-repo>.git
git push -u origin main
```

(Create the empty repo on github.com first, then use the URL it gives you.
GitHub Desktop can do all of the above through its UI instead if you'd
rather not use the command line.)

### 2. Let CI build it

Pushing to `main` automatically triggers `.github/workflows/ios-build.yml`.
You can also trigger it manually: on your repo's GitHub page go to
**Actions → Build BLACKMARKET (unsigned IPA) → Run workflow**.

The workflow:
- installs **XcodeGen** and generates the `.xcodeproj` from `project.yml`
  (this is why there's no committed `.xcodeproj` — it's regenerated fresh
  every run, which avoids the usual Xcode project-file merge conflicts)
- builds an **unsigned** `.app` for real iOS devices
- packages it into `BlackMarket-unsigned.ipa`
- also does a quick Simulator build, just to confirm the code compiles cleanly
- uploads the IPA as a downloadable workflow artifact

### 3. Download the build

Open the finished run under the **Actions** tab, scroll to **Artifacts**,
and download `BlackMarket-unsigned-ipa`. Unzip it to get
`BlackMarket-unsigned.ipa`. This works fine from a plain Windows browser.

### 4. Get it onto your iPhone (still from Windows)

The IPA from CI is intentionally **unsigned** — Apple requires every app
to be signed before it'll run on a real device, and that signing step
needs an Apple ID. The easiest Windows-native way to do that last step is
[**Sideloadly**](https://sideloadly.io/) (free, Windows & Mac):

1. Plug your iPhone into your Windows PC via USB (trust the computer if
   prompted on the phone).
2. Open Sideloadly, drag in `BlackMarket-unsigned.ipa`.
3. Enter your Apple ID (a free/personal one works, no paid developer
   account required) and click **Start**. Sideloadly signs the app with
   your Apple ID and installs it.
4. On the iPhone: **Settings → General → VPN & Device Management** →
   trust your Apple ID's developer profile, then open the app normally.

**Limitation to know about:** apps signed with a *free* Apple ID expire
after **7 days** and need re-signing/reinstalling (just re-run Sideloadly
with the same IPA — no rebuild needed). A paid Apple Developer Program
membership ($99/year) signs apps for a full year and also unlocks
TestFlight, if you want to avoid the weekly re-sign.

If you'd rather skip sideloading tools entirely, a cloud-Mac rental
service (e.g. MacinCloud) gives you a real Xcode GUI in the browser and
lets you install straight from Xcode over USB or WiFi.

### Troubleshooting CI

- **"project ... is in a future Xcode project file format"** — the
  runner has multiple Xcode versions installed, and XcodeGen wrote a
  project file newer than whichever one was selected by default. The
  workflow pins `xcode-version: latest-stable` before building to keep
  the two in sync; if this ever recurs, that's the line to check first.
- **Build product not found** — the "Package as unsigned .ipa" step
  prints a `find` of everything under `build/` so you can see the
  actual output path if Apple changes it in a future Xcode release.

## Core loop (fully functional, not a mockup)

- **Buy**: Market tab → pick a product → pick a supplier (if unlocked) →
  confirm. Cash is deducted, inventory increases, a transaction is logged.
- **Sell**: Network tab → open a buyer NPC → sell directly, or Profile tab →
  "New Listing" to list inventory for the network to buy over time
  (simulated on each Home refresh / pull-to-refresh).
- **Reputation & Levels**: every profitable sale grants reputation scaled
  by margin and product risk tier. Crossing a level's reputation threshold
  (`SellerLevel.repRequired`) unlocks new products/suppliers automatically.
- **Market prices**: drift randomly each tick (per-product volatility),
  nudge slightly from your own trades, and can be knocked by random
  events (demand spikes / crackdowns).
- **BTC**: a fully simulated exchange rate you can buy/sell against with
  your in-game cash. Never touches real Bitcoin or payments.
- **Persistence**: everything above is stored via SwiftData and survives
  app relaunches.

## Hidden Admin / Dev Mode

Go to **Profile** and tap the avatar circle **7 times**. This opens a
panel to add/remove USD and BTC, set reputation, spawn inventory, edit
prices, force-unlock seller levels, trigger a random market event, and
wipe all data back to a fresh start. Intended for testing only.

## Extending it

- New products/suppliers/NPCs/achievements: add entries to
  `Core/GameData.swift` — everything else (unlocking, pricing, UI lists)
  reads from that catalog automatically.
- New mechanics: `GameEngine` is the single place that mutates state,
  so new systems should be added there as new methods operating on the
  SwiftData `ModelContext`, then called from views.
