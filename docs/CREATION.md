# Creation — Relive v0.2

> Choose memories. Relive makes something beautiful from them.

v0.2 adds a small set of opinionated ways to turn real memories into something worth keeping or
sharing: **Memory Collage**, **Story Maker**, **Monthly Recap**, **Our Year**, plus an occasional
**Surprise Memory** on Today and **Create from this** on every moment. Everything is made on the
iPhone; nothing is uploaded, and nothing is invented.

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

No new dependencies, no network calls, no remote AI. Creation reads the same photos the user
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

