<p align="center">
  <img src="Artha/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="128" height="128" alt="The Artha app icon: a blue orb with an amber sun rising in its upper left.">
</p>

<h1 align="center">Artha for iPhone</h1>

<p align="center">The native Artha app for iPhone and iPad, built in SwiftUI.<br>
By Anwar Creative Studio. The web app lives at <a href="https://arthaapp.com">arthaapp.com</a>.</p>

---

## Status

Prototype of the Today screen with sample data. It exists to feel the design on a real iPhone before the rest is built: the motion, the haptics, the glass. Nothing here talks to the Artha server yet.

## What to try

- **Drag across the chart.** A glass label follows your finger and each day ticks a haptic. It stops at today.
- **Tap "Safe to spend".** Pick Spent this month or Net worth; the big number rolls to the new value.
- **Tap Add.** The sheet arrives already filled from an Apple Pay tap. Tap "Add $6.75" and watch Safe to Spend, the chart and Where October went update together.
- **Tap SK.** Switch the sample month between On pace, Ahead of pace, Over budget and First day.

## Running it

Open `Artha.xcodeproj` in Xcode, choose the **Artha** scheme and your iPhone, then Run. The project targets iOS 26 or later. Files added inside the `Artha/` folder are picked up by Xcode automatically.

```bash
xcodebuild -project Artha.xcodeproj -scheme Artha -destination 'generic/platform=iOS Simulator' build
```

The app icon is drawn from vector gradients by `Scripts/RenderIcon.swift`:

```bash
swiftc -parse-as-library Scripts/RenderIcon.swift -o /tmp/artha-render-icon && /tmp/artha-render-icon Artha/Assets.xcassets
```

## Shape of the code

- `Artha/Model/MonthModel.swift`: the sample month. Every number on Today is derived from the budget, what has been spent and the bills still due, the same way the real app will derive them from the Artha API.
- `Artha/DesignSystem/`: colors, the SF Rounded figure style, money formatting and the orb.
- `Artha/Today/`: the Today screen, one file per part.
- `Artha/Add/`: the add sheet.
