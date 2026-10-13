# Memory Intelligence (v1, phase 1)

> Choose less, but choose better. Never invent meaning. Never override the user.

Memory Intelligence answers one question: *given a group of Relive memories, what is a good,
factual creation plan?* Which photos are worth using, which are repetitive, which one leads,
what period they cover, in what order they go, what can truthfully be said about them, and what
they would make well.

It does **not** answer "what was your happiest day" or "which moment meant the most". Those are
the couple's to say.

## Existing signals it reuses (nothing duplicated)

| Signal | Where it comes from |
|---|---|
| Capture date, location, size, kind, traits, Photos favorite | `MemoryAsset` (PhotoKit snapshot; canonical date rules, see DATA_INTEGRITY.md) |
| Face count and quality, sharpness, aesthetics, utility (receipts, documents) | `AssetAnalysis` (Vision, on a small thumbnail, already cached) |
| Image quality as a single value (faces, sharpness, aesthetics, resolution, shape, Photos-favorite bonus, screenshot/utility/video penalties) | `AssetScorer` |
| Near-identical shots and re-saved copies | `DuplicateDetector` (perceptual hash + feature print, star grouping), moments' `similarAssetIDs` / `duplicateAssetIDs` |
| Moment, trip, place name, cover (user's or Relive's) | `Story`, `Chapter`, `HeroSelector.resolvedHero`, `MomentUserState` |
| Hidden moments, unavailable photos, usable photos | `CreationLibrary.isVisible / isAvailable / isUsable` |
| Favorites in Relive | `CreationLibrary.favoriteAssetIDs` |
| Month and year of a photo | the library calendar (`TemporalIndex`'s rules) |
| Period of a set, factual creation facts | `CreationMetadata`, `CreationLibrary.facts` |

## Signals intentionally *not* used

- **Recency.** An old memory is not a worse memory. A test shifts a whole trip by fourteen years
  and checks the same photos are chosen.
- **Emotion, sentiment, "meaning", identity.** No face recognition, smile detection or
  "importance" guesses.
- **New pixel analysis.** Nothing reads an original or full-size image to rank a library.
- **Anything off the device.**

## Architecture

`ReliveCore/Intelligence/` contains only Foundation code. It's deterministic, tested on Linux,
and independent of the UI, StoreKit and PhotoKit.

| Type | Responsibility |
|---|---|
| `MemoryCandidate` | The normalized signals of one memory, built from the story. Unknown stays nil. |
| `MemoryRanker` + `RankingWeights` | The internal *suitability* score. Never shown to anyone. |
| `SimilarityClusters` | Near-identical groups among the candidates (Relive's own similarity rules). |
| `VisualDiversityEngine` | One photo per group, then a diversity-aware greedy pick. |
| `PeriodDescriptor` | The period a set covers, and its labels. |
| `FactualTitleBuilder` + `FactualTextPolicy` | Titles from facts, and the rule that blocks feeling words. |
| `MemorySequencePlanner` → `MemorySequence` | Lead, chronological order, sections, transitions. |
| `CreationRecommender` → `CreationRecommendation` | What the set suits. |
| `MemoryIntelligenceEngine` → `MemorySelectionPlan` | Puts it together. The plan is Codable. |
| `IntelligenceDiagnostics` | An optional sink for the DEBUG log line. |

### The plan

`MemorySelectionPlan` contains:

- **The selection:** target, mode, status (ready or insufficient), `sourceCount`, `selected`,
  `lead` with its `leadReason`, and `alternates`.
- **What was left out:** `excludedDuplicates`, `collapsedSimilar` (each mapped to the photo that
  stands for it), `similarityClusterCount`, and `nearDuplicateSelections` (in the user's own
  selection, reported only).
- **What's true about it:** `period`, `title`, `sequence`, `recommendations`.
- **`limitations`:** missing, hidden, not usable, undated, unplaced, or near-identical photos
  repeated to reach a minimum.

It holds identifiers and facts only — no pixels, notes or coordinates.

## Ranking philosophy

Suitability is the existing `AssetScorer` quality plus a few small additions:

| Addition | Weight |
|---|---|
| Relive favorite | +0.35 |
| The moment cover the user chose | +0.30 |
| Relive's own moment cover | +0.10 |
| Known date | +0.02 |
| Known location | +0.02 |
| As a story lead only: a portrait photo | +0.10 |

`AssetScorer` already rewards the Photos-app favorite and penalizes screenshots, receipts and
videos.

The weights are data (`RankingWeights`), so they can be tuned without touching the logic. Ties
fall back to the order the photos were taken, then to identifier, so the same input always gives
the same output.

## Duplicates and near-duplicates

- **Re-saved copies are always excluded.** These are a moment's `duplicateAssetIDs`, plus photo-
  library picks compared against the other candidates with `DuplicateDetector.isDuplicate`. The
  better copy is kept by Relive's own rule.
- **Near-identical photos collapse to one representative.** That's a favorite (or the user's
  cover) if the group has one, otherwise the best by suitability. A favorite is never dropped
  for a similar shot that merely ranks a little higher.
- **A required photo stands for its group.** The moment's cover is required. If it is only
  Relive's own choice and the group has a favorite, the favorite stands instead.
- **A group contributes a second photo only to reach the target's minimum.** For example, a
  story needs three photos and the moment is one burst. When that happens it's recorded as a
  `repeatedSimilar` limitation.
- **Creation minimums are honored.** `CreationLibrary.initialPhotos` asks for enough photos for
  a collage or story (3), and books ask for 6. A source the pickers offer is therefore never
  turned into "not enough photos" by de-duplication. Simulator CI caught this case: a moment
  whose featured photos still looked alike.

## Diversity

After collapsing, photos are picked greedily. Each pick is the best suitability minus a small
cost for every already-chosen photo it repeats:

| Repeats an already-chosen photo's… | Cost per photo |
|---|---|
| moment | 0.12 |
| day | 0.06 |
| place | 0.03 |
| orientation, beyond the other orientations' count | 0.03 |
| framing (people vs. scene, from face counts), beyond the other's count | 0.04 |

- Because the cost applies equally to everything that repeats a trait, a genuinely homogeneous
  set (one evening of portraits) is not artificially diversified. It is simply ranked by quality.
- Required photos (the cover) are always included.

## Periods

`PeriodDescriptor` uses each memory's own capture date in the library calendar. These are the
same rules as `TemporalIndex`, so a 00:10 New Year's photo belongs to January.

| Memories | Period | Example label |
|---|---|---|
| all on one day | day | "June 8, 2026" |
| within one month, at most 6 days apart | days | "June 8–10, 2026" |
| within one month, further apart | month | "August 2026" |
| several months of one year | months | "August – October 2026" |
| several years | years | "2025 – 2026" |
| no dates at all | unknown | no label |

- `commonPlace` is set only when every memory has the same known place.
- `isComplete` is true only when every memory is dated. A partial period is never a title.
- Seasons ("Summer 2026") are produced only when the caller says which hemisphere the couple
  lives in. Relive never assumes one.

## Factual titles

| What's true of every memory | Title |
|---|---|
| The user wrote one | The user's words |
| One moment | The moment's name · its period ("Kaş · June 8, 2026") |
| One trip | The trip's name · its period |
| One place | "Bergama · August 2025" |
| One month | "Moments from August · August 2026" |
| Several months of one year | "Our 2026 · August – October 2026" |
| Several years | "Our Memories · 2025 – 2026" |
| One day without a name | The date |
| Some dates missing, or none | "Our Memories" (no dates claimed) |

`FactualTextPolicy` lists the words Relive never generates: "happiest", "best", "favorite",
"unforgettable", "never forget", "perfect", "magical", "true love" and so on. Every generated
fixture title is checked against it. User-written text is the user's and is never checked.

## Sequences

- The lead opens. Everything else follows **in the order it was taken**. Time is never scrambled
  for looks.
- Photos are grouped into sections: consecutive photos of one moment, or of one day outside the
  story.
- Each section's transition is the largest change from the previous one: new year, month, day,
  place or moment.
- The closer is simply the last photo in time.

## Recommendations

| Creation | Suggested when |
|---|---|
| Collage | 2+ distinct photos; first choice for 2–6 |
| Story | 3+ photos with a sequence: several days or moments, or 5+ photos (or a short 3–4 photo sitting) |
| Book | 6+ (`BookLimits.minimumPhotos`) over 2+ moments or days |
| Monthly Recap | every photo dated within one month, and 4+ of them (the recap's own minimum) |
| Our Year | one year, 2+ months, 8+ memories, 2+ moments (Our Year's own rules) |
| `movieFuture` | a trip with 15+ photos over 3+ days; `isAvailable: false` because Movie isn't built |

A recommendation is never a requirement. The user can always make something else.

## Where it's used

| Creation | What changed |
|---|---|
| **Collage** | Its initial photos (from a moment, trip, month, year or favorites) are the engine's selection. "Make it for me" keeps the user's photos and uses the shared lead ranking only for order. The style and shape choice still lays out every option with the photos' real shapes. |
| **Story Maker** | Its photos come from the same plan. Its lead (and the next leads for variations) comes from the engine's story ranking. Titles still come from `CreationLibrary.facts`, the same factual rules the title builder follows, so existing story text is unchanged. |
| **Memory Book** | The cover is the user's cover, or else the engine's lead. Its initial photos come from the engine. Pagination and page layout are unchanged. |
| **Monthly Recap, Our Year** | The screens are unchanged. Creations started from them use the engine. |

## User intent

- **Chosen photos (`.photos`, mode `userSelected`)** are kept, in the user's order. Nothing is
  swapped, and near-duplicates are only reported.
- **The user's cover choices win:** a book cover, a moment cover.
- **A favorite is a strong positive signal.**
- **"Make it for me" stays an explicit action.** Nothing re-runs on its own, and manual edits
  (order, layout, photos, cover) are not overwritten. The editors only call the engine when a
  creation starts or when the user presses "Make it for me".

## Missing and unknown data

- **An undated photo stays undated.** It is counted (`undatedCount`, an `undated` limitation)
  and never given another photo's date.
- **A photo without a location stays unplaced.** It never inherits a place.
- **Missing, unknown, hidden or unusable photos are left out** and recorded as limitations.
- **Too few distinct photos** gives an `insufficient(available:required:)` status. There is no
  fallback content.

## Performance

| Step | Cost |
|---|---|
| Building candidates | One pass over the story's moments: O(story assets + n log n) |
| Similarity | Candidates sorted by time and compared only within the 5-minute similar-shot window, so close to linear (undated photos are compared with each other) |
| Duplicates | Already computed for the story. Photo-library picks: O(picks × n) |
| Greedy selection | O(k × n) for k chosen; skipped when everything fits |

- No original or full-size image is read, and there are no network calls.
- Plans are computed synchronously where a creation starts (on the main actor, as the previous
  pickers were). They read metadata only, which takes milliseconds at 100–500 memories.
- A test plans 500 memories (50 moments, with bursts) for three targets well under the 3-second
  bound on Linux CI.

## Privacy

- Everything runs on the device, with no network or AI API and no uploads.
- The plan holds identifiers and facts only.
- The DEBUG line holds counts and reasons only: no identifiers, file names, places, coordinates
  or notes.
- Analytics are unchanged.

## Debug explainability

Development builds log one line per plan (subsystem `app.relive`, category `intelligence`):

```
intelligence_plan target=general6 mode=automatic source=92 selected=6 duplicatesRemoved=2 similarCollapsed=14
  similarityClusters=9 sections=4 period=2025-2026 leadReason=favorite recommendations=[book,story,collage]
  limitations=[undated:1]
```

Quick lookups (a single cover) don't log.

## Future seams

- **AI captions:** `FactualTitle.basis` says why a title is true. A future captioner would
  receive the plan's facts (period, places, sequence sections), never pixels, and its output
  must pass `FactualTextPolicy` before it can be shown. On-device first; any remote model would
  need explicit consent per creation (as the AI trends already require).
- **Memory Movie:** `MemorySequence` (lead, chronological sections, transitions, closer) is the
  shot list. `CreationKind.movieFuture` already tells the UI when a set would suit one.
- **Made for You, Monthly Recap 2.0, Wrapped:** plan the month, year or trip with
  `.general(limit:)` and use `recommendations` and `sequence.sections` for the slides.

## Known limitations

- Similarity uses the existing fingerprints. Photos analyzed before fingerprints existed, or
  whose analysis failed, can't be clustered (they're treated as distinct).
- "Close-up vs. wide" is approximated by people vs. scene (face count). There is no scene
  classification.
- Diversity weights are hand-tuned and need checking on real libraries.
- Story card text still uses the existing facts. `FactualTitleBuilder` is used by plans and is
  ready for the Made for You and Recap 2.0 screens.
