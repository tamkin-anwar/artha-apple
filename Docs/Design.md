# Artha visual system: Daybreak

Adopted October 22, 2026, for Artha 3: the relaunch's apps (iPhone, iPad, Mac) and the redesigned website, as one system. The look itself was chosen in the relaunch's third design round ("Round 3: Redesign" canvas, then the web canvas approved October 21); this document writes down the rules that keep every surface in step, the way Corres's `Docs/Design.md` does for Corres.

Artha and Corres are siblings, not twins. They share Anwar Creative Studio's craft rules (below); each has its own voice. Corres is quiet luxury in serif and titanium. Artha is daybreak: a calm navy night with one warm light, and money set in SF Rounded, the face of the big numbers in Fitness and Health.

## Shared with Corres (the studio's craft)

- One accent. Color that isn't the accent means something.
- Content sits on opaque surfaces. Glass (Liquid Glass on iOS 26) is only for controls that float above content: the tab bar and its Add button, and the web's phone tab bar. A chart's scrub label stays solid, so the line never runs through its figures.
- Depth from light and one-pixel hairlines, never bevels or heavy borders.
- Everything vector or a color: SF Symbols, SwiftUI paths and gradients, SVG on the web. The app icon is an Icon Composer document (`Artha/AppIcon.icon`), never an upscaled bitmap.
- Both themes follow the device; Settings can pin one.
- Motion is short and purposeful: press responses, sheets, numbers rolling to a new value. No ambient loops.
- Accessibility is part of the design, not a pass at the end.

## Themes

| Token | Day (light) | Night (dark) | Web variable |
| --- | --- | --- | --- |
| `ground` | #F4F6FA | #0A0E17 | `--bg-page` |
| `surface` | #FFFFFF | #121826 | `--bg-surface` |
| `raised` | #E4E9F2 | #1A2233 | `--raised` |
| `ink` | #0B1020 | #F2F4F8 | `--text-primary` |
| `secondary` | #586174 | #A3ABBD | `--text-secondary` |
| `accent` (orb blue) | #2F5FD0 | #6E95FF | `--accent` (`--gold`, legacy name) |
| `good` | #16804B | #3DD68C | `--good` |
| `caution` | #9A5B00 | #F5B544 | `--caution` |
| `cautionLine` (meters) | #D98A0B | #F5B544 | `--caution-line` |
| `band` | #1F2F57 | #16264F | `--band` |
| `inverse` / `onInverse` | #0B1020 / #FFFFFF | #F2F4F8 / #0A0E17 | `--inverse` / `--on-inverse` |

The apps read these from `Shared/Palette.xcassets` (one color set per token, in the app and the widgets; asset colors switch the instant the appearance does). `Shared/Palette.swift` repeats each value in a comment, and the website's `static/css/style.css` holds the same values; change all three together.

### What color means

- Blue is for what you can tap, and for the month's line.
- Green means on pace, paid, reached.
- Amber means look here: ahead of pace, over budget, a stale balance, net worth down. **Money status is never red.** Being over a budget is information, not a failure.
- Red is only for destroying something: Delete, Sign out, swipe to delete.

## Type

- **Words:** the system face (SF Pro; Segoe UI and Roboto on the web), always a Dynamic Type text style in the apps (`.font(.system(.subheadline, weight: .semibold))`, never `size:`), so every word follows the person's text size.
- **Money:** SF Rounded, heavy, tabular digits, through `.figureFont(_:weight:)`. Figures scale with Dynamic Type too, but display figures (40pt and up) grow at most 30%, and they keep one line with `minimumScaleFactor`, so a hero number never wraps or clips. `Font.figure` (fixed) is only for widgets.
- **Section labels:** small tracked uppercase (`SectionLabel`; `.section-label` on the web).
- On the web, ui-rounded (Apple devices) with Nunito as the fallback carries the rounded figures, and every size is in rem, so text follows the browser's own font-size setting the way the apps follow Dynamic Type.

## Shape and space

- Three corner radii, all continuous: `Radius.card` 22 (anything on the ground), `Radius.inner` 14 (a control or tile inside a card), `Radius.small` 10 (icon tiles, chips). The web mirrors them as `--radius-card`, `--radius-inner`, `--radius-small`. 22 is also Corres's surface radius.
- A 16-point page margin on iPhone, 4-point grid otherwise. Wide layouts (iPad, Mac, desktop web) go to two columns at 820 points and stop growing at 1180.

## Components

- **Hero figure:** the month's one number (Safe to spend by default; switchable), a status capsule (green on pace, amber ahead or over) and one plain sentence under it.
- **Pace chart:** spending so far against an even pace to the budget. Scrubbable with a finger, a pointer or the arrow keys; each day ticks a selection haptic. VoiceOver can play it as an Audio Graph.
- **Band:** "Where October went", the one full-bleed navy band, white type on it.
- **Cards and lists:** opaque `surface`, `Radius.card`, a hairline in Day, tonal separation only in Night.
- **Chrome:** on the desktop web there is no top bar; search sits under the logo in the sidebar (⌘K or Ctrl K), What's new under More, Send feedback above your name. Phones keep a slim top bar with Add and Search, like the app's toolbar.
- **Primary action:** the inverse capsule (ink on Day, white on Night). At most one per screen; the accent stays for links and selection.
- **Status cards:** symbol tile, title, one or two sentences, one action. Never a badge or a nag.

## Mark and icon

The orb: a blue planet with a warm sun glowing on its upper left, daybreak over a world. In the app it's `OrbMark` (gradients); on the web it's the sidebar logo and, with no background, the browser tab icon (`favicon.svg`).

The app icon is an Icon Composer document (`Artha/AppIcon.icon`) holding two drawings of the orb, switched per appearance with `hidden-specializations`. In Default and Dark it's the soft orb itself: the planet and the sun as SVG radial gradients in OrbMark's colors, on the navy field, without glass, so the sun glows into the planet. In Tinted and Clear, where iOS recolors everything, a soft glow turns into a plain disc, so those show two glass discs instead, the sun in front of the planet, and the sun keeps its own shape. Preview every rendition with Icon Composer's `ictool` (`.../Icon Composer.app/Contents/Executables/ictool Artha/AppIcon.icon --export-image ... --rendition TintedDark`). The website's Home Screen and install icons are rendered from the Default rendition, so the Home Screen shows one icon whether Artha is the app or the website.

## Motion and accessibility

- Numbers roll with `.contentTransition(.numericText)`; sheets and cards fade or move a short way. Reduce Motion keeps the state change and drops the movement.
- Every screen works at the largest accessibility text size: rows wrap instead of truncating where they can, and hero figures shrink to fit rather than clip.
- Charts carry an accessibility label that says what they show in words, and an Audio Graph (`AudioGraph`, or Swift Charts' own where each mark is labeled) that VoiceOver plays as sound.
- Every custom control has a label, rows combine into one VoiceOver element, and status is never color alone (a capsule always has words and a symbol).

## Before calling a screen finished

Check it in Day and Night, at the default and the largest accessibility text size, with VoiceOver, on iPhone and iPad (and the Mac if it's shared), and its web counterpart at phone width and desktop width.
