# UI Audit — alignment, spacing and consistency

Scope: every shipped screen, reviewed from the CI screenshots (iPhone 16 and iPhone SE 3rd gen;
light, dark and the largest accessibility text size) and from the SwiftUI source. Simulator only
— nothing here was checked on a physical device.

Goal: not a redesign. Find what makes Relive look less deliberate than it is, and say how to fix
it.

## 1. What already works

Relive already has a small token system, and most screens use it:

| Token | Value | Uses in `Relive/` |
|---|---|---|
| `Spacing.xxs / xs / s / m / l / xl / xxl` | 4 / 8 / 12 / 16 / 24 / 32 / 48 | ≈ 460 |
| `Spacing.screenMargin` | 20 | 80 |
| `Radius.photo / card / button` | 6 / 14 / (button) | 70 |
| `Typography.*`, `.eyebrowStyle()` | serif display + system text | everywhere |

Literal paddings are rare (≈ 30 in the whole app, most inside export canvases where pixel values
are intentional). **No new design system is needed.** The fixes below are a handful of named
sizes and a few layout corrections.

## 2. Couple-name presentation (product-wide rule)

Current state — one formatter, five places, one exception:

| Where | What it shows | Source |
|---|---|---|
| Us header | "You + Emma" / "Jake + Emma" | `UsView` → `app.coupleName` |
| Story header | "You + Emma" | `StoryTimelineView.StoryHeader` |
| Our Year eyebrow ("YOU + EMMA") | uppercase couple name | `RecapViews` (2 places) |
| Our Year share card eyebrow | couple name | `RecapExperienceView.share()` |
| Edit Names preview | couple name | `EditProfileView` |
| Trend credits ("starring Jake & Emma") | **"&"**, separate formatter | `TrendSamples.coupleNames` |
| Tests | "You + Emma", "Jake + Emma", "Jake & Emma" | core + hosted tests |
| Docs/comments | "You + Emma" | `UsView`, `StoryTimelineView`, `RelationshipProfile` |

Root: `RelationshipProfile.coupleDisplayName` (ReliveCore) returns `"\(lead) + \(partner)"`.

Correction (mechanical, Phase A):

- One presentation type in ReliveCore, `CoupleName`, with:
  - `display`: "Arda ♥ Kübra" — U+2665 BLACK HEART SUIT, rendered as text (not the red emoji,
    which is U+2764 + VS16). Spaced with normal spaces.
  - `spoken`: "Arda and Kübra" — for VoiceOver (`accessibilityLabel`), so the heart is never read
    as "black heart suit".
  - `plain`: "Arda & Kübra" — for places where a symbol is wrong (file names, share text).
- SwiftUI `CoupleNameText` view: the heart drawn smaller and in `Palette.textSecondary` (so it
  reads as a quiet mark, not an icon), the whole thing one accessibility element read as `spoken`.
- "You + Emma" (no user name) becomes "You ♥ Emma" — **product question** (see report §42): the
  alternative is showing only "Emma" until the user adds their own name.
- Trends keep "starring Arda & Kübra" inside the export (film credits read naturally with "&");
  **product question** whether to switch to ♥ there too.
- Uppercase eyebrows: `.textCase(.uppercase)` uppercases letters only; ♥ is unchanged. Turkish
  "i" casing (İ/ı) is handled by the locale-aware uppercase SwiftUI applies — must be checked.

## 3. Findings

Severity: **H** visible on a main screen or blocks reading; **M** noticeable; **L** polish.
Kind: **Mech** = mechanical fix; **Judg** = needs a product/design call.

### Shared components

| # | Component | Issue | Sev | Correction | File | Kind |
|---|---|---|---|---|---|---|
| C1 | Thumbnails (4:5) | Seven sizes for the same thing: 56×70, 60×75, 60×84, 64×80, 72×90, 88×110, 96×120 | M | Three named sizes: `Thumb.small` 56×70 (pickers, inline), `Thumb.row` 72×90 (list rows), `Thumb.feature` 96×120 (Today cards). Paywall hero and movie strip keep their own | `TodayView`, `CreateHomeView`, `MadeForYouViews`, `RecapViews`, `MemoryPickerView`, `PeriodPickerView`, `MemoryBookEditorView`, `AddFavoritesView`, `SurpriseMemoryViews`, `CollageEditorView`, `DraftsView`, `RecapPageView` | Mech |
| C2 | Card rows (Continue, discovery, archive rows, Made for You rows) | Same idea, three paddings (`Spacing.s`, `Spacing.m`) and two radii | M | One `ReliveRowCard` modifier: padding `Spacing.m`, `Radius.card`, `Palette.surface` | `TodayView`, `ArchiveViews`, `CreateHomeView` | Mech |
| C3 | Icon + text rows (discovery privacy, movie sources) | Icon column fixed at 24 pt and aligned `.top`: at the largest text size the glyph collides with the first line (seen in N93) and sits above the baseline at normal sizes | M | `HStack(alignment: .firstTextBaseline)`, icon width from `@ScaledMetric` | `DiscoveryViews.PrivacyLine`, `MovieSourceChooserView` | Mech |
| C4 | Pill buttons in two-column grids | Recap closing: "Make a Memory Book" wraps to two lines, its neighbour doesn't — the row's buttons have different heights | M | `.frame(maxHeight: .infinity)` on both buttons of a row (or a `Grid`) | `RecapPageView` | Mech |
| C5 | "Found for you ❤️" eyebrow | Red emoji heart next to the new quiet ♥ language | L | Use the same typographic ♥ in secondary colour | `TodayView` | Judg |
| C6 | Toast (`ToastView`) | Grows without limit at accessibility sizes; text wraps mid-word | L | Cap toasts at `.xxLarge` (done for the draft notice in Polish V1); apply in `ToastView` itself | `CommonViews` | Mech |
| C7 | Section header + "See All" | Correctly `.firstTextBaseline`; serif title vs sans link differ in size by design | — | No change | `CreateHomeView` | — |

### Onboarding / First Experience

| # | Screen | Issue | Sev | Correction | Kind |
|---|---|---|---|---|---|
| O1 | Welcome (largest text) | The line under the headline is cut by the bottom button with no sign it scrolls | M | Fade at the bottom edge of the scroll area, or let the button area scroll at accessibility sizes | Judg |
| O2 | How to begin (largest text) | Card body text clipped by the screen edge; scrolls, but looks cut | M | Same treatment as O1 | Judg |
| O3 | Discovery privacy | See C3 | M | C3 | Mech |
| O4 | Processing | Content sits low with a large empty top on SE | L | Centre the block vertically, the way First Discovery is | Mech |

### Today

| # | Issue | Sev | Correction | Kind |
|---|---|---|---|---|
| T1 | Thumbnails in Continue (72×90) vs discoveries (96×120) side by side look unrelated | L | C1 — both `Thumb.feature` | Mech |
| T2 | Add Memories card is outlined, all other cards are filled | L | Keep (it is an action, not content) — note only | — |

### Story

| # | Issue | Sev | Correction | Kind |
|---|---|---|---|---|
| S1 | Year control over the header at the largest text size | — | Fixed in `beb79ef` (scaled room) | — |
| S2 | Header name "You + Emma" | M | §2 | Mech |

### Moment detail / viewer / archive

| # | Issue | Sev | Correction | Kind |
|---|---|---|---|---|
| A1 | Viewer top controls (♡ ••• ✕) are 44 pt circles; the date pill is bottom-centred — good | — | — | — |
| A2 | Archive month header's count is `.footnote` next to a `.title3` title — baseline-aligned, correct | — | — | — |
| A3 | Moments/Places rows switch to vertical at accessibility sizes — correct | — | — | — |

### Create, editors, creations

| # | Screen | Issue | Sev | Correction | Kind |
|---|---|---|---|---|---|
| E1 | Story Maker style row | Styles are a wrapping row of plain words ("Minimal Film Travel Romantic / Editorial"): the fifth wraps alone on iPhone 16 | M | Horizontal scroll row, or the same segmented treatment as Collage | Judg |
| E2 | Collage editor | Both "Save" (nav bar) and "Save to Photos" (bottom) on one screen | M | Keep one primary; nav-bar "Save" = keep in Relive — label it "Keep" or remove | Judg |
| E3 | Movie editor (largest text) | The title under the preview is clipped by the Save bar | M | Bottom inset on the scroll content equal to the Save bar height | Mech |
| E4 | Create "Your Creations" empty state | Plain sentence under a section title, while every other section shows a card | L | Small outlined card with the same sentence | Mech |
| E5 | Book reader toolbar | "Share Page / Save Page" outline buttons + "Save Full Book" primary: OK | — | — | — |

### Recap / Our Year

| # | Issue | Sev | Correction | Kind |
|---|---|---|---|---|
| R1 | Closing actions | C4 | M | Mech |
| R2 | Our Year eyebrow "YOU + EMMA" | M | §2 | Mech |

### Us, Favorites, Drafts, My Creations, Premium

| # | Issue | Sev | Correction | Kind |
|---|---|---|---|---|
| U1 | Us header name | M | §2 | Mech |
| U2 | Favorites toolbar: wand and + icons have different optical weight | L | Same `.imageScale` and weight | Mech |
| U3 | Paywall: plan cards, checklist and close button align; no change | — | — | — |

## 4. Optical alignment notes

- SF Symbols with different widths (sparkles, airplane, calendar) in a fixed 24-pt column look
  ragged; use `.frame(width:)` with `.imageScale(.medium)` and centre alignment *plus* first
  baseline alignment for the row (C3).
- Serif display titles carry more space above the cap height than system text; headers that mix
  the two should align on `.firstTextBaseline` (Create already does).
- The circular "Make it for me" pill is centred while the controls below are leading-aligned. It
  reads as the primary action and is fine, but keep it the only centred control on the screen.

## 5. Proposed tokens (small)

```swift
enum Thumb {            // 4:5 photo thumbnails
    static let small = CGSize(width: 56, height: 70)
    static let row = CGSize(width: 72, height: 90)
    static let feature = CGSize(width: 96, height: 120)
}
```

Plus `ReliveRowCard` (C2). Nothing else: `Spacing`, `Radius` and `Typography` already cover the
rest.

## 6. Not audited

Landscape (the app is portrait-only on iPhone), iPad (not a target), widgets (none yet).
