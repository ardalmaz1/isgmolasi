# Monthly Recap 2.0 and Our Year 2.0

Intelligence v1, Phase 3. A recap is now a short, full-screen story of one real period, told chapter
by chapter. It reads like an editorial photo essay about the couple's own photos. It is not a
dashboard of statistics.

Everything runs on the iPhone. There are no network calls, no uploads, no remote AI and no
analytics upload.

## Where it lives

| Layer | File | Role |
| --- | --- | --- |
| Core | `ReliveCore/Intelligence/Recap/RecapStoryPlanner.swift` | `RecapPeriod`, `RecapInsights`, `RecapChapter`, `RecapPlan`, `RecapStoryPlanner` |
| Core | `ReliveCore/Intelligence/Recap/EditorialText.swift` | `EditorialFacts`, `EditorialTextProviding`, `DeterministicEditorialTextProvider`, `ValidatedEditorialTextProvider` |
| App | `Relive/Recap/RecapExperienceView.swift` | The full-screen pager: progress, Close, Next/Previous, analytics, Premium shape, create, share; `RecapPlayButton` |
| App | `Relive/Recap/RecapPageView.swift` | One chapter's layout |
| App | `AppModel.openRecap / startCreationFromRecap / recapDismissed`, `MainTabView` | Presentation (a second `fullScreenCover`) |

The planner reuses the systems that were already there and does not replace them:

- `TemporalIndex` provides canonical capture dates.
- `MonthlyRecapBuilder` and `YearInReviewBuilder` decide sufficiency, moments and trips.
- `MemoryIntelligenceEngine` provides photo selection, duplicate collapse and diversity.
- `FactualTextPolicy` and `MonthNames` cover wording and month names.

The scrolling Monthly Recap and Our Year screens stay as they were. They gain a **Play** button that
opens the immersive recap.

## Chapters

A rich recap is built in this order. Any chapter whose facts are weak is left out, never padded.

| Chapter | Shown when |
| --- | --- |
| Opening | always: the period, memories, moments and places |
| First memory | the earliest dated memory, if the period has ≥ 2 active days |
| *Year:* the year in numbers, month by month | always for a year |
| Trip highlight | a trip in the period with ≥ 4 usable photos (at most 1 per month, 2 per year) |
| Place, again | one place with strictly the most moments: ≥ 2 moments on ≥ 2 different days, not already told by a trip |
| A day with more to remember | a period with ≥ 3 active days, whose busiest day has ≥ 6 memories, more than the next day and ≥ 2× the median; not already told |
| Two in the frame | ≥ 4 usable photos where on-device analysis found two or more faces (never *who*) |
| Favorites | ≥ 2 favorites in the period |
| In frames | ≥ 4 photos chosen by Memory Intelligence |
| Places | ≥ 2 named places |
| *Month:* the shape of the month | ≥ 3 moments; at most 6, chosen evenly through the month |
| Closing | always: counts, the share card, Make Collage / Create Story / Make a Memory Book |

Limits are 5–10 chapters for a month and 8–16 for a year. Trimming removes places first, then
favorites, people, the busy day, the timeline and the repeated place.

**A period is sparse** when it isn't sufficient for its existing recap, or (for a month) has fewer
than 8 memories. A sparse period gets one compact summary page and the closing:

- a month reads "September was a quiet one in Relive."
- a year reads "Your 2026 is just getting started."

## Insights (all factual)

`RecapInsights` contains:

- counts of memories (same rule as `StoryStatistics`), moments, active days, places (in order of
  first appearance), trips and favorites
- the months represented
- the most represented month (strict maximum, years only)
- the most represented place (strict maximum, ≥ 2 moments on ≥ 2 days)
- the earliest and latest capture dates
- the longest trip in days

When something is unknown it stays unknown:

- No place means no place chapter and no "0 places".
- With no strict winner there is no "most" claim.
- Undated, hidden and missing photos are excluded the way the existing builders exclude them.
- A period never includes memories from another month or year.

## Words: facts in, text out

Each chapter has `EditorialFacts`: structured names Relive already shows, dates and counts. The
facts never include photos, coordinates, notes, captions or identifiers. An
`EditorialTextProviding` turns those facts into `EditorialText` (eyebrow, title, detail).

- **Today:** `DeterministicEditorialTextProvider`. It is warm where that's safe ("September,
  together.", "Three days in Kaş.", "Bergama, again.", "That was your September.") and plain
  everywhere else.
- **A future AI:** it would implement the same protocol and be wrapped in
  `ValidatedEditorialTextProvider`. Its text is used only if:
  - the title isn't empty;
  - every part passes `FactualTextPolicy` (no feelings, no relationship claims);
  - every number it mentions is one the facts contain (`EditorialFacts.allowedNumbers`).

  Otherwise the deterministic text is used.
- **What an AI would receive:** the `EditorialFacts` case for one chapter, e.g.
  `trip(name: "Kaş", days: 3, memories: 18, dateLabel: "12–14 September")`.
- **What an AI would never be allowed to add:**
  - feelings or a judgment about the relationship ("your happiest month");
  - numbers that aren't in the facts, and rankings or comparisons;
  - places, people, names or events that aren't in the facts;
  - anything about photo contents.

## The experience

- **Layout:** full screen, one chapter per page. Each page scrolls vertically, so the largest text
  sizes and an iPhone SE never clip it.
- **Controls:**
  - Swipe, or use Next / Previous.
  - Nothing advances on its own.
  - The segmented progress bar is always visible (VoiceOver reads "Chapter 3 of 9").
  - Close is always one tap away.
- **Motion:** each page fades in gently. With Reduce Motion there is no fade and no paging
  animation.
- **VoiceOver:** each chapter's words are read as one header; photo grids are announced as "N
  photos".
- **Entry points:**
  - Made for You's monthly and annual suggestions ("Your September is ready").
  - The single Today card (the same opener).
  - **Play** on Monthly Recap and Our Year.
- **Creating from a recap:**
  - Make Collage, Create Story and Make a Memory Book close the recap, then open the existing
    editor with the period as source, so Memory Intelligence picks the photos.
  - Nothing is saved until the user saves.
  - Two full-screen covers can't stack, so `AppModel` opens the creation from the recap cover's
    `onDismiss`.
- **Sharing:** the closing card uses the existing `SummaryCardExport` (with "Made with Relive")
  and `ExportController.share`.
  - A successful share records the period's Made for You recap suggestion as made, so it steps
    away.
  - Opening one records it as opened, as before.

## Premium

No Premium rule changed. The full Monthly Recap and Our Year stay Premium (`.fullMonthlyRecap`,
`.fullYearInReview`). Creating from the full recap and its share card stay part of the full recap.
The one free creation still applies to collage, story and trend saves only.

**What changed is the shape of the free preview**, which is now the smallest coherent version of
the old one:

- the opening and the next two chapters (real value first; opening never shows a paywall);
- a calm Premium page, "The rest of September", with "4 more chapters — and a card to share —
  are part of Relive Premium." and See the Full Recap (or Relive Your Full Year);
- the closing chapter, whose share and create actions show the existing paywall. Closing the
  paywall returns to the recap.

A recap with no more than the opening plus two chapters (and every sparse, compact recap) holds
nothing extra, so it isn't gated.

## Analytics (local only)

These events go to the existing on-device `AnalyticsTracking`:

- `recap_opened` (kind, experience, rich, origin)
- `recap_chapter_viewed` (period kind, chapter kind, index)
- `recap_completed`
- `recap_creation_started` (creation kind)
- `recap_share_started`
- `recap_share_completed`

They record kinds and counts only, never places, titles, dates or identifiers.

## Diagnostics (DEBUG)

`RecapPlan.diagnosticsLine` is logged under `app.relive / intelligence` when a recap opens:

```
recap_plan period=2026-09 rich=true memories=43 chapters=9 chapterKinds=[opening,firstMemory,…] placesKnown=3 duplicatesRemoved=… similarCollapsed=…
```

## Performance

- Planning uses metadata only: dates, moments, scores, fingerprints and face counts. It never
  loads full-size images.
- The plan is computed once per presentation in `.task`, never in a view body. Each new
  presentation plans again, so changes to the library (new photos, hidden moments, favorites)
  can never show a stale recap.
- Pages load thumbnails through the existing image loader.

## Tests

**ReliveCore** (`RecapStoryPlannerTests.swift`, Linux and macOS):

- *Month acceptance* (September 2026: 43 memories, 6 moments, 7 active days, 3 places, 1 trip, 4
  favorites).
- *Year acceptance* (2026: 126 memories, 14 moments, 5 places, 2 trips, 8 months, 9 favorites).
- *Edge fixtures:* every word factual; sparse never padded; mixed years; bursts; no location;
  undated, hidden and missing photos; favorites; old years; deterministic output; three active
  months; compact year; diagnostics.
- *The AI contract:* a feeling claim falls back, a made-up number falls back, a faithful rephrase
  is kept, and facts carry no private data.

**Hosted** (`ReliveTests/RecapAppTests.swift`, plus the Made for You routing test):

- the free preview's shape and Premium's full shape;
- short and compact recaps aren't gated;
- opening never asks for Premium;
- create → close → the creation opens with the period as source, with nothing saved;
- sharing follows the existing rule without spending the free creation;
- recording a shared recap touches only that period's suggestion.

**UI** (`ReliveUITests/RecapUITests.swift`):

- The flow: free → Play → chapters → Premium page → paywall → close back to the recap → closing →
  Make Collage and Share → paywall → close back → Close.
- Relaunch as Premium: every chapter → Make Collage → the collage opens.
- Our Year, dark mode and the largest accessibility text size.
- CI runs this test again on an iPhone SE (3rd generation). Screenshots start with "R" (and "E" on
  the SE).
