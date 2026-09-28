# Relive — Prototype 0.1

> Your love story already exists in your camera roll. Relive helps you rediscover it.

Relive turns photos and videos a couple already has into a private, beautiful timeline of their
relationship. You choose the photos; Relive organizes them on your iPhone into moments, trips and
a story you can scroll through, add your own notes to, and share.

Prototype 0.1 exists to test one hypothesis:

> Can 50–500 selected photos, organized automatically, feel meaningful and delightful?

Principles: **Remember → Appreciate → Live.** AI organizes the memory; people give it meaning.
No scores, streaks, comparisons, guilt or claims about the relationship. Titles are factual
("Kaş • August 2025").

## What works

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
11. Three tabs only: Today, Story, Us. Light and dark mode, Dynamic Type, VoiceOver labels.

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
