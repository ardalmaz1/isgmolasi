# Relive — v0.3.1

> Your love story already exists in your camera roll. Relive helps you rediscover it.

Relive turns photos and videos a couple already has into a private, beautiful timeline of their
relationship. You choose the photos; Relive organizes them on your iPhone into moments, trips and
a story you can scroll through, add your own notes to, and share.

Prototype 0.1 exists to test one hypothesis:

> Can 50–500 selected photos, organized automatically, feel meaningful and delightful?

Principles: **Remember → Appreciate → Live.** AI organizes the memory; people give it meaning.
No scores, streaks, comparisons, guilt or claims about the relationship. Titles are factual
("Kaş • August 2025").

## New in v0.3.1 — creation intelligence and the photo library

- **Metadata follows the photo.** Titles, dates and places on every creation come from the
  photos in it. Photos from August and September are not "September"; 2025 and 2026 are not
  "2026"; Aliağa and Kaş are not "Aliağa"; unknown dates and places are left out. (Fixes the
  "September Together" bug — root cause in [docs/CREATION.md](docs/CREATION.md).)
- **Photo Library source.** Collage, Story Maker and Memory Book can use any photo on the
  iPhone (From Relive / From Photo Library), with its own date, place and size. Such photos are
  never added to your story.
- **Memory Book**: grouped by each photo's own moment or day, no repeated generic titles, page
  footers with each page's own dates, orientation-aware pages with a new asymmetric spread,
  6–40 photos, Favorites and Photo Library sources.
- **Our Year** only presents a year that is one (memories from at least two months, eight
  memories). Otherwise: "Your 2026 story is just getting started", with Add Memories and Build
  from Photo Library.
- **Story Maker 2.0**: Relive designs a 3–7 card sequence (cover, hero, pairs and trios, place
  cards where the place changes, a factual close) in five genuinely different styles, with
  **Make it for me** and simple card edits (layout, replace photo, show/hide date, place,
  coordinates, remove).
- **Layout fixes**: the collage save bar no longer covers controls, styles wrap instead of
  running off-screen, Share moved to the navigation bar on Our Year and Monthly Recap.

## New in v0.3 — Memory Book and Trending Now

- **Memory Book**: a book made automatically from a moment, a trip, a month, a year or chosen
  photos — cover, factual title pages (real names, dates, places), varied photo pages that respect
  each photo's orientation, the couple's own notes, and a closing page. Three styles (Classic,
  Editorial, Film). Read it page by page; save or share any page at 2160 × 2700. Light editing:
  style, cover, add/remove/replace/reorder photos, a note for the first page, refresh from the
  source, delete. Books are saved as definitions (photo identifiers, style, note) — never photo
  copies — and reopen from Create → Your books.
- **Trending Now** at the top of Create: five original on-device looks made from your own photos
  (B&W Editorial, Film Couple, Photo Booth Strip, Magazine Cover, Cinematic Poster), each with a
  real preview, "You'll need" and "Best results", variations, Save to Photos and Share. Trends
  come from a validated, data-only catalog bundled in the app (remote-ready, not configured).
- **AI trends: architecture only.** One AI trend is listed as *Coming soon* with an honest
  "About AI creations" disclosure. No AI provider, API key or upload exists in this version.
- No paywall, purchases or accounts.

Details: [docs/MEMORY_BOOK.md](docs/MEMORY_BOOK.md), [docs/TRENDS.md](docs/TRENDS.md).

## New in v0.2 — creating from memories

> Choose memories. Relive makes something beautiful from them.

- **Create tab** (Today · Story · Create · Us): Memory Collage, Story Maker, Monthly Recap, Our Year.
- **Memory Collage**: 2–12 photos (chosen, or from a moment), six curated styles (Minimal,
  Editorial, Grid, Film, Polaroid, Scrapbook) that account for portrait and landscape photos,
  **Make it for me**, swap/replace/reorder, 1:1 · 4:5 · 9:16, factual title/date/place toggles.
- **Story Maker**: 3–6 9:16 cards from a moment, photos, a month or a year, in five looks.
- **Monthly Recap** and **Our Year**: real counts, moments, trips, best photos; gentle states
  when there isn't enough; shareable summary cards.
- **Surprise Memory** on Today, only on real anniversaries ("A year ago this week").
- **Create from this** on every moment.
- Everything renders on device at 2160 px wide; Save to Photos (add-only permission) or Share.
  Preview and export are drawn from the same layout.

Details: [docs/CREATION.md](docs/CREATION.md).

## What works (since 0.1)

1. Onboarding: welcome → partner's first name → when the story began (month or exact day) →
   why photos are needed → Apple's photo selection UI.
2. Import of 50–500 photos/videos by reference (identifier, date, location, type, duration,
   size, favorite). Fewer is allowed, with a gentle suggestion.
3. On-device processing with honest progress: Vision analysis on thumbnails, duplicate and
   near-identical detection, time + place moment clustering, trip detection, cover selection,
   place names, factual titles.
4. Story reveal with real numbers only (days, memories, moments, places).
5. Timeline: Year → Trip → Moment, photo-led editorial cards, oldest first.
6. Moment detail: cover, dates, place, counts, private note ("What do you remember about this?"),
   photo grid, "Show similar", "Use as Cover", full-screen viewer with video playback.
7. Found for You: one older, good memory a day; hidden moments never resurface;
   "Don't show this again".
8. Hide this memory (with undo, reversible in Us → Hidden Memories). No questions asked.
9. Share: an on-device 4:5 card ("KAŞ / August 2025 / Remember this? ❤️") through the system
   share sheet. The recipient doesn't need Relive.
10. "Did you find something that made you smile?" — asked once, after a few moments have been
    explored, answer stored locally.
11. Tabs: Today, Story, Create (v0.2), Us. Light and dark mode, Dynamic Type, VoiceOver labels.

No account, no payment, no uploads, no AI API.

## Running it

Requirements: **Xcode 16 or later** (the project uses synchronized folders), iOS 18 device or
simulator.

1. Open `Relive.xcodeproj`.
2. Select the **Relive** target → Signing & Capabilities → choose your team (the bundle
   identifier `app.relive.prototype` may need to be changed to something unique to you).
3. Run on an iPhone — a real library is what the prototype is for.

To try it in the Simulator, load a generated sample library (~80 photos with real dates and
places: evenings at home, a trip to Kaş with a day in Kekova, New Year's Eve, a burst, a
WhatsApp-style copy):

```bash
pip install pillow && brew install exiftool
python3 scripts/make_sample_library.py /tmp/relive-sample
xcrun simctl addmedia booted /tmp/relive-sample/*.jpg
```

Tests (the Memory Engine):

```bash
cd Packages/ReliveCore
swift test          # or ⌘U on the Relive scheme in Xcode
```

The same tests run on Linux, so the engine can be verified anywhere Swift runs.

CI (`.github/workflows/ci.yml`) runs the engine tests on Linux and macOS, builds the app with
Xcode 16.4 and Xcode 26, and runs `ReliveUITests` end to end in a simulator loaded with the
sample library: onboarding → processing → reveal → timeline → moment → note → share → Today →
Us. Screenshots of each step are uploaded as a build artifact.

## Documentation

- [docs/MEMORY_BOOK.md](docs/MEMORY_BOOK.md) — v0.3 Memory Book: model, sources, auto-layout,
  styles, persistence, rendering, performance, accessibility, the future PDF and print paths.
- [docs/TRENDS.md](docs/TRENDS.md) — v0.3 Trends: trend and catalog model, recipes and versions,
  LOCAL/TEMPLATE/AI, the AI provider abstraction and privacy boundary, Trend Radar and human
  review, publishing, monetization hook, copyright, fallback behaviour.
- [docs/CREATION.md](docs/CREATION.md) — v0.2 creation: collage layouts, Make it for me, story
  cards, recaps, Surprise Memory, rendering and export.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — structure, decisions, iOS 18 target, privacy,
  persistence, concurrency.
- [docs/MEMORY_ENGINE.md](docs/MEMORY_ENGINE.md) — every heuristic with its thresholds: moment
  clustering, trips, duplicates, cover selection, naming, Found for You.
- [docs/VALIDATION.md](docs/VALIDATION.md) — how to run a validation session with a couple and
  read the signals.

## Known limitations of 0.1

- **Thresholds are first guesses.** Clustering has been tested with synthetic libraries (unit
  tests and the simulator flow), not yet with many real ones. The Vision feature-print thresholds
  for "same photo" and "similar shot" are the least certain; Debug builds log every duplicate
  decision to help tune them (see *Tuning* in MEMORY_ENGINE.md).
- **In the Simulator, Vision's feature prints are uniform**, so the engine detects this and falls
  back to perceptual hashes. On a device the embeddings are used.
- **Capture times** are read in the device's current time zone (PhotoKit doesn't expose the time
  zone a photo was taken in), so trips across time zones can shift a late-night photo by a day.
- **Place names** come from Apple's reverse geocoder (town/city level). Offline or rate-limited
  lookups leave a moment unnamed rather than guessing; a later "Add Memories" run fills gaps.
- **Photos only in iCloud** (Optimize Storage) aren't downloaded for analysis, so they get
  neutral quality scores. They still display normally.
- **English only.** Dates follow the user's region.
- The app target compiles in Swift 5 mode with complete concurrency checking; the core package
  is Swift 6.
- Analytics events only go to the device log (Console.app, subsystem `app.relive`).

## Known limitations of v0.2

- **Creation output has been checked in the Simulator and by automated tests, not yet on a
  physical device.** Rendering speed and memory with very large libraries, and how saved images
  look in other apps, need a device check (see the checklist in the v0.2 notes).
- Our Year's full scrolling retrospective isn't exported as one piece; Share Our Year shares a
  summary card and Create Story makes year story cards.
- Seasons ("Summer") are not used, because they depend on the hemisphere.
- Collage editing is intentionally limited (no free positioning, filters or text editing).
- Drafts aren't saved: closing an editor discards it.

## Known limitations of v0.3.1

- **Not physically verified.** Everything above was verified by unit tests, hosted tests, UI
  tests in the iOS Simulator and CI builds — not on a physical iPhone.
- The Photo Library picker itself is Apple's; UI tests replace it with a debug stand-in, so the
  real picker's behaviour (and limited-access picks) needs a device check.
- With limited photo access, photos not shared with Relive can't be used; Relive explains this
  and points to Us → Photo Access.
- Photos from outside the story have no place names (no network lookups for creations); Travel
  shows their coordinates only when the photos were taken close together.
- Story cards can't be repositioned or cropped by hand; photos are cropped around the shared
  focus point.
- Story Maker drafts and collages are still not saved (books are).

## Known limitations of v0.3

- **Not physically verified.** Memory Book and Trends were checked by automated tests and in the
  iOS Simulator only. Page-turn feel, image quality of saved pages and trends, memory use with
  large books, and Dark Mode on a real screen need a device check.
- Memory Book exports single pages (save/share). There is no PDF export and no printed-book
  ordering yet — see the planned paths in MEMORY_BOOK.md.
- Books aren't updated automatically when the source changes; Edit → *Update from …* does it
  on request. Photos that disappear simply drop out.
- The remote trend catalog is implemented but switched off (no URL configured); trends change
  only with an app update for now.
- AI trends can't be made: no provider is integrated (by design for this version).
- Trend recipes don't read catalog `parameters` yet.
- Page and trend canvases are fixed-size artwork; their text doesn't follow Dynamic Type (the
  app around them does, and VoiceOver reads each page's facts).
