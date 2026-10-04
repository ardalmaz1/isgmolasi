# Creation — Relive v0.2, v0.3, v0.3.1

> Choose memories. Relive makes something beautiful from them.

**v0.3** adds two things on top of the v0.2 creation infrastructure described here:
**Memory Book** ([MEMORY_BOOK.md](MEMORY_BOOK.md)) and **Trending Now**
([TRENDS.md](TRENDS.md)). Both reuse the same pieces — `CreationLibrary` for which photos may be
used and what facts may be said, design-point canvases with preview = export, `CreationImageSource`
for sized loading, and `ExportController` for Save/Share with duplicate-save protection. The
Create tab now opens with Trending Now, then the permanent tools: Memory Collage, Story Maker,
Memory Book, Monthly Recap, Our Year. `CreationSource` gained `.trip` (a whole trip chapter),
used by Memory Book and by Story Maker.

v0.2 adds a small set of opinionated ways to turn real memories into something worth keeping or
sharing: **Memory Collage**, **Story Maker**, **Monthly Recap**, **Our Year**, plus an occasional
**Surprise Memory** on Today and **Create from this** on every moment. Everything is made on the
iPhone; nothing is uploaded, and nothing is invented.

## v0.3.1 — metadata follows the photo

**The rule:** everything a creation prints about its photos — title, dates, place, coordinates
— is derived from *those photos*. Never from the screen, month, request or first photo a
creation started from.

**Root cause of the "September Together" bug** (reproduced by tests before the fix):

1. `CreationLibrary.facts(for:photos:)` took a creation's headline from its *source* (`.month`,
   `.year`, `.trip`) without checking the photos actually in it. A book started from September
   kept "September Together" / "SEPTEMBER 2026" after photos from other months were added
   (Add or Remove Photos), and collages and stories did the same after photo edits.
2. The book's grouping put a photo that had no owning moment into the *previous* section, so it
   inherited that section's name ("September Evening") and dates.
3. Page footers in one-section books showed the whole book's dates, not the page's.
4. Date spans were aggregated with `compactMap`, silently ignoring undated photos.

**The model** (`Creation/CreationAsset.swift`, pure and tested on Linux):

- `CreationAsset` — one photo's own capture date, location, size, favorite flag, and (for
  memories) its moment, trip and known place name. Photos from the photo library have no place
  name: none is looked up for a creation.
- `CreationMetadata.summarize` — what can truthfully be said about a selection:
  - period: one day / one month / one year (several months) / several years — **only when
    every photo has a date**;
  - place: only when every photo has the same known place;
  - coordinate: only when every photo has a location within 1 km of their centre;
  - moment / trip: when every photo belongs to the same one.
- Titles: one moment or trip → its name; one shared place → the place; one month → "September
  Together"; several months of one year → "Our 2026"; several years or unknown dates → no title
  (the app shows the date range, or a neutral "Our Memories"). A source's name, month or year
  is used only when every photo belongs to it. A year source is "Our 2026" only when its photos
  span several months.

Required cases, all tested (`CreationMetadataTests`): six September photos → September 2026;
August + September → not September; 2025 + 2026 → no single year; all Aliağa → Aliağa; Aliağa
+ Kaş → no place; no location → no place; no date → no month or year.

**Photo Library source.** Collage, Story Maker and Memory Book can use photos straight from the
iPhone library: Choose Photos → *From Relive* or *From Photo Library* (the system picker; still
photos, no screenshots, in pick order). Picked identifiers are read through the existing
`PhotoLibraryProviding.assets(withIdentifiers:)`, which returns PhotoKit's own date, location
and size. Picks are **never imported into the story**; a photo that already is a memory keeps
its memory metadata. `CreationLibrary.addingPhotoLibraryAssets` makes them usable by every
creation without duplicating any creation code. Books store the picks' metadata (never pixels)
so they reopen correctly; picks Relive can't read (limited access) are explained, not guessed.
Exports made from them are still recorded as Relive-created and never imported as memories.

**Story Maker 2.0** (`Creation/StoryDesigner.swift`). Relive designs the story: an opening cover
from the strongest tall photo, the strongest body photo on its own card, neighbours of one
moment together (two landscapes stack, two portraits sit side by side, trios when needed), a
place card only where the place really changes, and a factual close ("And that's our 2026."
only for a year that is one; otherwise place and dates; nothing when nothing is known). 3–7
cards from up to ten photos; each card's date and place come from its own photos. Eleven
layouts (cover, coverFramed, fullBleed, framed, postcard, duo, duoOffset, trio, trioStrip,
caption, closing), each drawn by the five styles' own design systems from one shared geometry
(`StoryCardGeometry`), so preview and export match and each photo is exported at its frame's
size. **Make it for me** ranks styles from known properties only — a real place (Travel), many
days (Film), a strong portrait and many photos (Editorial), mostly portraits (Romantic), few
photos (Minimal) — and each press takes the next style and lead photo, deterministically. Edit
Card: Change Layout, Replace Photo (per slot, from Relive or the library), Show/Hide Date,
Place, Coordinates, Remove Card. No free positioning, fonts, stickers or text boxes. Cropping
uses the shared focus point; manual reposition is not offered in this version.

**Our Year eligibility** (`YearEligibility`): at least 2 different months, 8 memories and 2
moments. One month is not a year however many photos it has: Our Year then says "Your 2026
story is just getting started", offers Add Memories and Build from Photo Library, lists the
year as "2026" (not "Our 2026"), and never says "And that's our 2026".

## Structure

```
Packages/ReliveCore/Sources/ReliveCore/Creation/   pure logic, tested on Linux
  CreationGeometry.swift      design-point canvases, crop math, export sizes
  CollageLayoutEngine.swift   the six collage arrangements
  CollageAutoDesigner.swift   "Make it for me"
  CreationLibrary.swift       which photos may be used, sources, factual captions
  StorySequenceBuilder.swift  3–6 story cards from a moment, photos, a month or a year
  RecapBuilders.swift         Monthly Recap and Our Year content
  SurpriseMemoryService.swift anniversary-based Surprise Memory

Relive/Creation/                                   app layer
  CreationRequest.swift       what to make, from where (one request type for every entry point)
  CreationText.swift          formats real facts into words; nil when there is nothing true to say
  CollageEditorModel.swift    collage state; layout is a pure function of it
  StoryMakerModel.swift       story state; rebuilt without photos that can't be loaded
  Exporting.swift             export-size image loading, Save to Photos, Share, one export at a time
  Rendering/                  CollageCanvas, StoryCardCanvas, SummaryCardCanvas, ScaledCanvas
  Views/                      Create home, pickers, editors, recaps, Our Year, Surprise Memory
```

The Memory Engine, clustering, similarity detection, scoring and place resolution are unchanged;
creation only *reads* the story through `CreationLibrary`, which applies the app's existing
visibility rules (hidden moments and unavailable photos never appear) and adds one creation
rule: only still photos, never videos, screenshots or receipts.

## Preview = export

Every canvas is laid out in **design points, 1080 wide** (1080×1080, 1080×1350, 1080×1920) with
fixed type sizes. The editor shows the *same view* scaled down (`ScaledCanvas`); the export
renders it with `ImageRenderer` at scale 2 (**2160×2160, 2160×2700, 2160×3840 px**). Layouts are
pure, deterministic functions of the photos' shapes, style, shape and caption lines, so the
saved image is the arrangement the user saw. Text is never re-flowed at a different size because
both are drawn from the same 1080-point layout.

Performance: previews load each photo once at ≤1200 px (1800 for story cards) and reuse it
across style and shape changes. Exports load each photo only at the size its frame needs in the
final image (`CreationImageSizing`, capped at 4096 px per side), without caching, one at a time.
Full-resolution originals are never requested. JPEG encoding runs off the main thread.

## Memory Collage

- Start from **Choose Photos** (2–12, from Relive's own memories only — no new photo access) or
  **Choose a Moment** (6 representative photos are preselected: the cover plus the best photo of
  each stretch of time).
- Six styles, each a different arrangement that accounts for portrait and landscape photos:
  - **Minimal** — justified rows that keep every photo's own shape; nothing is cropped.
  - **Editorial** — the lead photo as a tall column or across the top, whichever crops least.
  - **Grid** — equal-height rows; the row arrangement that crops least is chosen.
  - **Film** — 35 mm contact strips running the way most photos were taken.
  - **Polaroid** — instant prints whose window matches each photo's orientation.
  - **Scrapbook** — slightly overlapping, turned, taped prints; the lead photo on top.
- **Make it for me** lays out every style × shape and scores them on photo size, cropping and
  how well the style suits the number of photos. The best photo leads; the rest follow in capture
  order. Pressing again offers the next-best *different* style. Deterministic.
- Editing is deliberately small: swap (tap two photos), replace, move earlier/later, remove,
  edit the selection, style, shape (1:1, 4:5, 9:16), and Title/Date/Place toggles — each toggle
  only appears when that fact exists.
- Captions: a title only when the photos share one moment, trip or place; a place only when it
  is shared; dates are the photos' own capture dates.

## Story Maker

- From a moment, 3–10 chosen photos, a month or a year. Relive arranges **3–6 cards**: an
  opening card (place or moment and period), photo cards, and "memory" cards only where the
  moment or day actually changes (e.g. *Kekova · August 7*). A year closes with *And that's our
  2026.*
- Five looks: Minimal, Film (with a date imprint from the photo's own capture date), Travel
  (with the real coordinate when there is a place), Romantic, Editorial.
- Preview each card; save this card or all; share one or all through the share sheet.
- Too few usable photos → a gentle explanation and "Choose Photos". A photo that can't be loaded
  is left out and the story re-arranged.

## Monthly Recap and Our Year

- Months and years with visible dated moments, newest first. Counts (memories, moments, trips,
  places) use the same `StoryStatistics` rules as the rest of the app; zero counts are omitted.
- Fewer than 4 memories in a month (6 memories / 2 moments in a year) → a quiet "Just a few
  memories" state instead of a recap.
- Recaps show the best photos interleaved across moments, trips only if the story has them, and
  links to every moment. Actions: Make a Collage, Create a Story, Share (a 4:5 summary card).
- Our Year goes month by month, with trips in the month they began, the first memory of the year,
  and *And that's our 2026.* Seasons are not used: "Summer" depends on the hemisphere, which
  Relive doesn't reliably know. Exporting the whole scrolling retrospective is not implemented;
  Share Our Year shares the summary card, and Create Story makes year story cards.

## Surprise Memory

- Lives on Today as a compact card, only when a photo's capture date is a **real anniversary**:
  a whole number of years ago, or six months ago, within three days ("A year ago this week",
  "2 years ago today", "6 months ago today").
- Occasional: after a surprise, Today rests for 3 days; a moment shown on Today by either card
  isn't a surprise again for 14 days; it never repeats Found for You's moment; hidden moments and
  "Don't Show This Again" are respected; "Not now" hides it for the day. Stable for the whole day.
- Opening it offers See the Moment, Make a Collage (this photo leads) and Make a Story.

## Saving and sharing

- **Save to Photos** asks only for *add* permission (`NSPhotoLibraryAddUsageDescription`).
- **Share** writes JPEGs to a private temporary folder and opens the share sheet.
- One export at a time per screen; repeated taps are ignored. After a collage is saved, Save
  stays disabled until something about it changes, so it can't be saved twice by accident.
  Exports continue briefly if the app goes to the background (`BackgroundActivity`).
- Images Relive saves are recorded (`StoredCreatedAsset`) and **never imported back as
  memories** — with limited photo access they become visible to Relive, and "Add Memories" would
  otherwise pull them into the story. This list survives Start Over for the same reason.
- A subtle "Made with Relive" appears on exported images (one flag per canvas, ready for a
  future option; there is no monetization logic).

## Privacy

No new dependencies, no network calls, no remote AI (v0.3 adds the *architecture* for AI trends
and an optional remote trend catalog; neither is configured, so this still holds — see
[TRENDS.md](TRENDS.md) §4 and §8). Creation reads the same photos the user
already chose; choosing photos for a collage never shows the full library. Analytics remain local
log lines with non-identifying properties (kind, style, shape, counts).

## Testing

- **ReliveCore** (`Tests/ReliveCoreTests/Collage*`, `CreationLibraryTests`, `StorySequenceTests`):
  layouts for every style × shape × 2–12 photos (bounds, overlaps, orientation), Make it for me,
  captions that never invent, sources, recaps, Our Year, story sequences, Surprise Memory dates
  (including leap days, rest days and cooldowns). Runs on Linux.
- **App, hosted** (`ReliveTests/CreationTests.swift`): export pixel sizes for every shape and
  style, export = previewed layout, per-frame image requests, missing photos, editor behaviour,
  Story Maker shortfalls, one export at a time, Relive's own images never imported, Surprise
  Memory on Today. These tests never touch PhotoKit: doing so in the test host raises the system
  permission prompt, and an unanswered prompt is recorded as "Don't Allow" for the UI tests that
  follow.
- **UI** (`ReliveUITests/CreationFlowUITests.swift`): onboarding, then collage from a moment →
  Make it for me → styles and shapes → Save to Photos; Story Maker → Save This Card; Monthly
  Recap; Our Year; Create from this (including the "Not enough photos" path).
- **v0.3**: `MemoryBookTests`, `MemoryBookEditingTests`, `TrendCatalogTests` (ReliveCore, Linux);
  `ReliveTests/BookAndTrendTests.swift` (books saved/reopened/deleted, v0.2 → v0.3 store
  migration, every page kind × style at export size, every recipe × variation at export size,
  deterministic processing, mid-tones kept by every recipe, studio export, AI honestly
  unavailable, catalog fallback; page and recipe renders are attached for review in CI);
  `ReliveUITests/BookAndTrendsUITests.swift` (trend → studio → variation → Save; AI trend
  disclosure; Memory Book from a trip → pages → Save Page → style → relaunch).

