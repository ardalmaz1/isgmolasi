# Made for You (Intelligence v1, phase 2)

> "Relive noticed this in our story." Quality over quantity, facts over fiction, the couple in
> control.

Made for You finds a few groups of real memories worth turning into something and prepares
them. It is not a feed. It shows a handful of suggestions at most, often fewer, and nothing at
all when nothing is good enough.

## Architecture

```
ReliveCore/Intelligence/MadeForYou.swift          (Foundation only, Linux-tested)
  MadeForYouEngine        library + now + history (+ hemisphere) → [MadeForYouSuggestion]
  MadeForYouSuggestion    id, kind, eyebrow, title, subtitle, creation, source, cover, photos
  SuggestionHistory       shown days, opened, dismissed, created — Codable

Relive/Intelligence/
  MadeForYouStore         @Observable, one per app: cache, refresh triggers, history in UserDefaults
  MadeForYouViews         Create section (hero + rows), Today card, creation label, opener
```

- **Built on plans.** Every suggestion is built on a Memory Intelligence plan
  (`MemoryIntelligenceEngine`), which supplies its cover, photos, period and facts. There is no
  second selection algorithm. Months and years reuse `MonthlyRecapBuilder`,
  `YearInReviewBuilder` and `TemporalIndex`. Anniversaries reuse `SurpriseMemoryService`'s
  capture-date anchors.
- **Opening a suggestion uses the existing screens.**
  - Monthly Recap and Our Year open their existing screens.
  - Collage, story and book open the existing editors with the plan's source, so their photos
    are Memory Intelligence's.
  - Nothing is saved on open (a book is kept the way any new book already is), and nothing
    asks for Premium.

## Suggestion kinds and eligibility

| Kind | When | Eyebrow · title · subtitle | Opens |
|---|---|---|---|
| `anniversary` | A moment taken a whole number of years ago, this day or within 3 days. It needs at least 3 usable photos, or a favorite with at least 2. Only the best one is offered. | "A year ago today" · moment name · "8 memories · October 14, 2025" | Collage (≤6 photos) or Story |
| `throwback` | The same, six months ago | "6 months ago this week" · … | Collage or Story |
| `monthRecap` | This month or last month: the recap is sufficient, with 8+ memories in 2+ moments | "Your month" · "Your September" (or "September 2025") · "34 memories · 4 moments" | Monthly Recap |
| `yearRecap` | This year once Our Year is eligible; last year too in January–February | "Your year so far" · "Our 2026" · "120 memories · 7 months" | Our Year |
| `memoryBook` | Last year, when eligible and with 20+ memories | "Ready to create" · "Our 2025" · "Memory Book · N memories" | Memory Book |
| `trip` | A trip the story already knows (a chapter) with 8+ usable photos. Never invented from photos alone. | "A trip" · "Kaş · August 2025" · "31 memories · 4 days" | Book, Story or Collage, whichever the plan recommends first |
| `place` | One known place with 3+ moments and 8+ photos across 2+ different years | "Through the years" · "Bergama through the years" · "2023 – 2026 · 9 memories" | Story of the plan's photos |
| `season` | A finished season (this year or last) with 12+ photos over 2+ months and 3+ moments, **only with a known hemisphere** | "From your story" · "Summer 2025" · "28 memories · 3 places" | Memory Book of the plan's photos |

- **Hemisphere.** It is used when it's given. Otherwise it is taken from the photos themselves,
  and only if at least half of the year's photos have a location and every located one is on
  the same side of the equator. When that isn't the case there is no season — Relive never
  guesses. Southern summer is January–February (so it never spans a new year), matching
  `PeriodDescriptor`.
- **Excluded memories.** Hidden moments, unavailable photos, undated photos (for every
  date-based kind) and duplicate copies never take part.
- **Old memories.** They are as eligible as recent ones. A 14-year anniversary is offered like
  a 1-year one.

## Quality (internal, never shown)

```
quality = 0.5
        + size          (log₂ of usable memories ÷ 5, at most 1 — 32 memories reach it)
        + diversity     (0.1 per extra moment + 0.05 per extra day, at most 0.5)
        + favorites     (0.1 each, at most 0.3)
        + period        (+0.2 if every memory is dated, −0.5 if not)
        + 0.3 × average photo quality
        − 0.5 × duplicate ratio   (near-identical and re-saved photos ÷ all considered)
        − (1 − share of dated memories)
```

- Anniversaries add 0.3 on the exact day and 0.2 when a favorite is involved.
- Anything below **1.0** is not suggested: empty space is better than a weak card.
- Today shows a suggestion only when it reaches **1.6** and is an anniversary, a throwback, a
  month, a year or a trip.

## Ranking and overlap suppression

`rank = priority(kind) + quality − rotation penalty`

| Kind | Priority |
|---|---|
| anniversary | 3.0 |
| throwback | 2.4 |
| month | 2.2 |
| trip | 2.0 |
| year | 1.8 |
| place | 1.5 |
| season | 1.4 |
| book | 1.3 |

- This follows the brief's order: anniversaries, then a strong recent month, a trip, the year,
  a place, then a creation.
- Ties are broken by identifier, so the order is deterministic.
- **Overlap suppression:** going down the ranking, a suggestion is skipped if it shares more
  than **50%** of the smaller suggestion's memories with one already kept. For example, a trip
  in September and "Your September" are mostly the same memories, so only the stronger appears.
- At most **4** are shown: one hero and up to three rows.

## History and dismissal

`SuggestionHistory` is kept on the device (UserDefaults, `relive.madeForYou.history`). There is
no account and no server.

| Event | Effect |
|---|---|
| Shown | Counted once per day |
| Opened | Recorded; an opened suggestion never steps back for rotation |
| "Not now" | Hidden for 90 days. It's in a context menu and a VoiceOver action, with no confirmation and no penalty to anything else. |
| Made | Detected when a kept creation or book has the same source and was created after the suggestion was first shown. Hidden for 180 days. |
| Shown on 5+ days without being opened | Steps back in the ranking (−1.0), so others get a turn. It is never hidden for this. |

- **Stable identities:** `anniversary:<moment>:<this year>-<years>`, `month:2026-9`,
  `year:2026`, `book:year:2025`, `trip:<first moment of the trip>`, `place:<place key>`,
  `season:<year>-<season>-<hemisphere>`.
- Moment identities survive story rebuilds (`MomentReconciler`). Chapter identities aren't
  relied on.

## Create and Today

- **Create.** The order is: the header, then **Made for You** (one hero card, then up to three
  rows), then Continue Editing, Your Creations, Favorites and Create Something.
  - The hero card has a real 4:3 cover, the eyebrow, a serif title, a factual subtitle and a
    small label for what it makes (Collage, Story, Memory Book, Monthly Recap, Our Year).
  - There are no scores, streaks, gradients or badges.
- **Today.** At most one Made for You card, only when strong enough. It never repeats the
  Surprise Memory's moment. With no strong suggestion, there is nothing.

## Premium

- Discovery, previews and opening a suggestion are free and never show the paywall.
- The existing rules apply when keeping things:
  - the first collage, story or trend export is free;
  - books and recap share cards need Premium;
  - the full Monthly Recap and Our Year beyond their free previews need Premium.

## Performance and cache

- Discovery uses metadata, moments, trips, recaps and plans only. No images are rendered or
  loaded. Covers load only when a card is on screen, through the existing thumbnail loader.
- `MadeForYouStore.refresh` recomputes only when its signature changes. The signature covers:
  the story's generation date and size, the photo count, favorites, hidden moments, unavailable
  photos, the number of kept creations, the day, and the history. Views call it on appear and
  when the story, favorites, hidden moments or kept creations change.
- With no story — or while onboarding is still building it — there are no suggestions, and
  there is no modal.

## Privacy

All discovery is on the device: no network, no AI, no uploads. Suggestion identifiers contain
moment UUIDs and place names but never leave the device. No analytics include suggestion
contents.

## Accessibility

- Each card is one VoiceOver element: "eyebrow. title. subtitle. creation".
- It has a hint ("Opens it, ready to look at and edit") and a **Not now** action.
- Text uses Dynamic Type styles. The UI test reviews the section at an accessibility text size
  and in dark mode.

## Future integration

- **Memory Movie:** `CreationKind.movieFuture` exists. A large trip's plan already recommends it
  (unavailable). A Movie suggestion would reuse the plan's `sequence` (lead, sections,
  transitions) as its shot list.
- **AI:** any generated wording (e.g. a caption under a suggestion) must be built from the
  plan's facts and pass `FactualTextPolicy`. Discovery itself stays deterministic and
  on-device.

## Known limitations

- Weights and thresholds are hand-tuned and need checking on a real library.
- Seasons appear only when photo locations settle the hemisphere. There is no settings switch
  for it yet.
- "Made" detection relies on the kept creation's source. A creation started from the same photos
  by another route also counts.
- There is no small-screen (iPhone SE) screenshot in CI. Review is on iPhone 16, in light,
  dark, and accessibility text sizes.
