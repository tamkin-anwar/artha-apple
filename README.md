<p align="center">
  <img src="Artha/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="128" height="128" alt="The Artha app icon: a blue orb with an amber sun rising in its upper left.">
</p>

<h1 align="center">Artha for iPhone</h1>

<p align="center">The native Artha app for iPhone and iPad, built in SwiftUI.<br>
By Anwar Creative Studio. The web app lives at <a href="https://arthaapp.com">arthaapp.com</a>.</p>

---

## Status

Early build. Signs in to a real Artha account and shows Today from the Artha server: Safe to Spend, the month's pace chart, where the money went, bills coming up and recent transactions. Add saves a real expense or income. Activity lists every transaction by day, with search, an Expenses/Income filter, swipe to delete with Undo, and tap to edit. Plan splits the month's budget into bills, everyday spending and what's left, lists this month's bills paid and still to come, and sets the budget and optional category limits with suggestions from your own spending. Wealth shows net worth over time and every account in its own currency, with a quick pass to confirm or update balances that are over a month old. Apple Pay purchases can log themselves: the app adds a Log Apple Pay Purchase action for a Wallet transaction automation in Shortcuts, with a setup guide in the app. Accounts are created on the web for now.

## What to try

- **Sign in** with your Artha username and password (plus your authenticator code if two-factor sign-in is on). You stay signed in until you sign out from the account menu, or change your password on the web.
- **Drag across the chart.** A glass label follows your finger and each day ticks a haptic. It stops at today.
- **Tap "Safe to spend".** Pick Spent this month or Net worth; the big number rolls to the new value.
- **Tap Add.** Type an amount and what it was. Artha picks the category, and Today updates as soon as it saves.
- **Pull down** on Today to refresh. It also refreshes whenever the app comes back to the foreground.

## Running it

Open `Artha.xcodeproj` in Xcode, choose the **Artha** scheme and your iPhone, then Run. The project targets iOS 26 or later. Files added inside the `Artha/` folder are picked up by Xcode automatically.

On a real iPhone the app talks to arthaapp.com. In the simulator it talks to the Mac's own dev server at `http://localhost:5050` (start it from the `artha` repo), which is the only plain-HTTP address the app allows (`Config/Info.plist`).

```bash
xcodebuild -project Artha.xcodeproj -scheme Artha -destination 'generic/platform=iOS Simulator' build
```

The app icon is drawn from vector gradients by `Scripts/RenderIcon.swift`:

```bash
swiftc -parse-as-library Scripts/RenderIcon.swift -o /tmp/artha-render-icon && /tmp/artha-render-icon Artha/Assets.xcassets
```

## Shape of the code

- `Artha/API/`: the client for the Artha server's `/api/v1` (the `artha` repo's `artha/blueprints/api`), the response models, and the Keychain where the sign-in token lives.
- `Artha/Model/`: `AppSession` (signed in or not, and the calls that change it) and `MonthModel` (Today's figures, shaped for display; the app never does its own budget math).
- `Artha/SignIn/`: the sign-in screen.
- `Artha/DesignSystem/`: colors, the SF Rounded figure style, money formatting and the orb.
- `Artha/Today/`: the Today screen, one file per part.
- `Artha/Add/`: the add sheet.
