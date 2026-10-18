# Real Device Product Polish V1

A focused polish pass after the product owner tested Relive on a real iPhone with a real
personal library. It is refinement, not a new feature phase: Memory Intelligence, moment
grouping, naming, discovery and the first experience are unchanged.

Principle: **your relationship, told through the photos you already have.** The archive is the
couple's and is always free to browse; Premium is about what Relive *makes* from it.

## Observation log (product evidence)

Recorded by the product owner on one physical iPhone with one personal library. These are
observations, not universal truths: nothing below was tuned to this one library.

| Area | Observed |
|---|---|
| Library | About 990 memories selected or kept by Relive |
| Discovery | Mostly accurate |
| Moment grouping | Mostly accurate ("Four days in Kaş", "Three days in Kınık", "Two days in Çankaya", Fethiye, Demre; mornings, evenings and nights correctly separated) |
| Dates | Generally accurate |
| Locations | Generally accurate |
| Movie | Kaş source of about 217 memories → 15 photos, about 43 s. Overall selection good; about 5 photos matched the user's own likely choices; about 2 similar frames; stronger alternatives appeared to exist; some private/intimate photos were selected |
| Make it for me | Appeared to mostly reorder the same photos |
| Today | Too sparse |
| Story | Reaching 2026 needed a lot of scrolling past 2025 |
| Us | Memories / Moments / Places looked like static counts |
| Drafts | Duplicate-looking movie drafts ("Kaş — Movie — Edited 10 hours ago" twice) |
| My Creations | Functional but underdeveloped |
| Favorites | Directionally good |
| Branding | "Made with Relive" unnecessary on personal outputs |
| Free policy | The archive should stay fully browsable |

## What changed

### Today

Order: the hero (Found for You), Made for You (the strongest suggestion, history and
suppression unchanged), Continue your story, then **at most two discoveries** chosen by
`TodayPlanner` (ReliveCore) from real data only, stable for the day:

1. **On this day** — a moment within three days of today's date in an earlier year
   ("A year ago · Bergama").
2. **A trip to look back on** — a trip with two or more visible moments that ended over a month
   ago. Opens the trip's moments.
3. **A place you returned to** — a *named* place with moments in two or more months. Opens the
   place.
4. **Recently** — the latest moment, if it began within 45 days.

A discovery never repeats a moment already on Today (hero, surprise, Continue, Made for You's
moment or trip), skips hidden and "Don't show this again" moments, and opens the archive —
never a paywall. A small or new story may show none. No scores, streaks, "best" or emotional
claims.

### Story — year navigation

A compact "2025 ▾" control floats at the top right when the story has two or more sections.
It shows the year on screen (the year of the top row, from SwiftUI's `scrollPosition(id:)`,
which also performs the jump — so it reaches years the lazy timeline hasn't drawn yet), lists every year of the story (from `TimelineSection`s, so
"Before March 2021" and "Undated" too) and "Latest Memories". Jumps respect Reduce Motion.
VoiceOver: "Jump to a year, Showing 2025", plus a **Years** rotor over the year headings.
Normal vertical browsing is unchanged.

### Free archive (Us → Memories, Moments, Places)

The three counts on Us are now navigation, built on one derived index (`ArchiveIndex`,
ReliveCore) that counts exactly like `StoryStatistics` — "990 memories" opens 990 memories.

- **Memories:** newest month first, pinned month headers, a lazy adaptive grid of small
  thumbnails (each loaded at its cell size). Tap opens the full-screen viewer for that month
  only (never all memories at once). Touch and hold: Favorite, Open Its Moment, Don't Suggest.
- **Moments:** every visible moment, newest first: cover, title, dates, memory count.
- **Places:** named places by name; an unnamed location joins a named place within 10 km or
  stays "A place without a name" — Relive never invents a name. Place detail lists its moments.

Hidden moments, unavailable photos and re-saved duplicate copies are left out (as on Us). The
index is rebuilt when the story or visibility changes, not when Today opens.

### Premium policy

Already correct in `PremiumPolicy` (no archive capability exists); now locked by tests: the
capability list is pinned, archive words never appear in it, and movie save/share, Memory Book
export, full recaps and Our Year still require Premium. The one free creation, recap previews
and first-session protection are unchanged. No archive screen consults the entitlement.

### Drafts

Cause of the duplicates: every "Memory Movie → Kaş" started a new editor with a new draft
identity, and its first change wrote a new draft. Now, opening the **same kind from the same
source** (moment, trip, month, year, favorites) continues the most recent unfinished draft,
with a brief "Continuing your draft · Start New" notice; Start New deliberately makes another
version. Hand-picked photos always start a new creation. Existing drafts are never merged or
deleted by this change. Drafts already had swipe-to-delete, a context menu and a VoiceOver
action, each with a confirmation.

### My Creations

A counts summary ("4 creations · 2 movies · 1 collage · 1 book"), a "Kept …" line on each card,
one wide column at accessibility sizes, and an empty state that leads to Create. Cards keep
their cover, factual title, kind and photo count; opening one reopens it with the existing
editors (viewing never asks for Premium; saving/sharing follows the export rules).

### Favorites

No changes: memories, moments and creations open correctly, can be removed, and are never gated.

### Memory Movie selection

On top of Memory Intelligence (unchanged for collages, stories, books and recaps):

- **Coverage:** each day of the source (or each moment of a one-day source) gets its best photo
  first, evenly spread when there are more days than photos, using at most two thirds of the cut.
- **Look-alikes:** the same scene shot again later the same day (feature distance ≤ 0.5, or
  hash distance ≤ 12; not a burst, so not collapsed) costs 0.4 per similar chosen photo.
- **Stronger replacements:** near-identical groups keep their strongest (or favorite) photo.
- **Utility photos:** screenshots, receipts, documents and videos were already excluded.

Measured in the core tests: a 220-photo, four-day trip → 15 photos covering all four days;
plan + remake in 0.08 s on Linux.

### Make it for me — before and after

| | Before | After |
|---|---|---|
| Photos | Same selection, new opening photo | Re-chosen from the whole source; the earlier cut's photos cost more until at most half repeat (when the source has alternatives) |
| Style | Cycled to the next style | Kept |
| Shape, length, title | Kept | Kept |
| Order | Chronological after the opening | Chronological after the opening |
| User's own cut | Replaced silently | The editor asks: "Make a New Cut" / "Keep My Changes" |
| Hidden / not suggested | Hidden excluded | Both excluded |

A small source may legitimately return the same photos (e.g. five photos for a five-photo film).

### Private / intimate photos — what is and isn't detected

Relive **cannot** tell whether a photo is private, intimate or sexual, and does not pretend to.

- Signals Relive has on device: capture date, location, size, screenshot flag, face *count*
  (never identity), sharpness, an aesthetic estimate, a utility flag (receipts/documents) and a
  visual fingerprint. None of these detects nudity, intimacy or "body-dominant" images, and
  Relive does not infer it from them.
- Apple's on-device `SensitiveContentAnalysis` framework exists (iOS 17+), but it needs a special
  entitlement and only works when the user has turned on Sensitive Content Warnings or
  Communication Safety. It is **not** adopted in this pass (it would change the app's signing
  entitlements and would silently do nothing for most users). It remains a possible future step.
- No photo is uploaded; no remote moderation API is used.

What Relive does instead, conservatively and explicitly:

- **Hidden memories** are absolute exclusions everywhere (as before).
- **"Don't Suggest This Memory"** (new): from the Memories grid, the full-screen viewer, Found
  for You ("Don't Suggest This Photo") and the movie editor ("Don't Suggest", which also removes
  it from the movie). The memory stays in the story; Relive never chooses it automatically for
  movies, covers it picks, or Found for You. Hand-picked photos are still used. Stored locally
  (`StoredSuggestionExclusion`, an additive SwiftData model) and kept across Start Over.
- **Remove / Replace** in the movie editor, as before.

### Branding

Removed "Made with Relive" from: story cards, collages, summary/recap cards, Memory Book
closing pages, all trend recipes, the movie's closing card (core) and the recap closing text
(core), and the "Relive" signature on the moment share card. The collage layout keeps its
bottom-margin geometry, so layouts don't shift. The app still names itself where context needs
it (Us → version line, paywall, settings).

## First experience

Unchanged. The onboarding flow, "How would you like to begin?", discovery, manual selection,
permission handling, processing and First Discovery are covered by the existing First
Experience hosted and UI tests (clean install and returning user), which run unchanged in CI.

## Performance

- `ArchiveIndex`: 1,000 memories indexed in about 2 ms (Linux core test); linear.
- Grids use lazy containers and frame-sized thumbnails through the existing loader; no
  full-size images in grids; the viewer pages through one month.
- Today's discoveries are computed when Today refreshes (appear, story change), not per redraw.
- Movie selection works on metadata and cached analysis only; no image work.

## Accessibility

Year control with label, value and hint; Years rotor; archive rows combine into one element
with a factual label; memory cells have Favorite / Don't Suggest actions; month headers are
headers; one-column layouts at accessibility text sizes; 44-point targets; Reduce Motion
honoured for year jumps. Reviewed in CI screenshots at the largest text size and in dark mode,
on iPhone 16 and iPhone SE (simulator).

## Tests

- Core (Linux, Swift Testing): `RealDevicePolishTests.swift` — film coverage, a meaningfully
  different remake, small sources, hidden and not-suggested exclusions, look-alikes, other
  creations unchanged, no branding in movie or recap text, archive counts and grouping, Today
  discoveries, Found for You exclusion, the Premium capability lock, timing.
  Removing the new weights makes the remake test repeat 15 of 15 photos and the look-alike test
  fail — the tests capture the change.
- Hosted: `RealDevicePolishAppTests.swift` — archive vs. Us counts, hiding, free archive vs.
  Premium outputs, Don't Suggest persistence and Start Over, draft identity and deliberate new
  versions, Make it for me keeping settings, a user's cut, Today discoveries.
- UI: `ArchiveUITests` (iPhone 16 and iPhone SE): Today, the year control (jump to 2025, Latest),
  Us → Memories (open one), Moments (open one), Places (open one), as a free user with no
  paywall; dark mode and the largest text size. `MovieUITests` adds Make it for me, the
  confirmation on a user's cut, and the continued-draft notice.
- Changed on purpose: `MovieEditorModelTests.testOnlyMakeItForMeReplacesTheCut` now expects the
  user's style to be kept (it expected the style to change).

## Known limitations

- Private/intimate photos are not detected (see above); the user decides with Hide and Don't
  Suggest.
- Today's discoveries use dates and places only; with sparse dates or no locations there may be
  none (by design).
- Unnamed places are listed without a name.
- Memory Books opened from the same source still make a new book each time (books keep their own
  model; out of scope for this pass).
- Everything here was verified in the iOS Simulator and in tests. **Physical-device validation
  is still needed** for: scrolling a ~1,000-memory grid, the year control on a long multi-year
  library, Make it for me on the real Kaş trip, Today with a real library, and the draft notice.
