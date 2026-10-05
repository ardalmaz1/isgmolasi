# Memory Engine

The Memory Engine turns the photos and videos a user selected into a **Story**:

```
Story → Chapter (trip, optional) → Moment → Asset
```

It lives in `Packages/ReliveCore` (Foundation only) so every heuristic is unit-tested on any
platform. Apple-specific work — reading PhotoKit, running Vision, reverse geocoding — is plugged
in by the app through three protocols: `AssetAnalyzing`, `PlaceNameResolving` and
`MomentNamingService`.

## Pipeline

| # | Stage | Type | What it does |
|---|-------|------|--------------|
| 1 | Metadata processing | `MetadataProcessor` | Drops invalid GPS (out of range, 0,0), treats far-future dates as unknown, separates undated assets, sorts chronologically. |
| 2 | Image analysis | `AssetAnalyzing` (app: `VisionAssetAnalyzer`) | On a 512 px thumbnail: face count + face capture quality, Vision feature print, aesthetics score + "utility" flag, perceptual hash, contrast, sharpness. Cached per asset; only new assets are analyzed. Up to 4 at a time at utility priority, always leaving one core to the interface. |
| 3 | Duplicate detection | `DuplicateDetector.duplicateGroups` | Finds copies across the whole selection (e.g. an original and its WhatsApp re-save). Copies leave clustering and are re-attached to their original's moment. |
| 4 | Temporal + location moments | `MomentClusterer` | See below. |
| 5 | Trips | `ChapterBuilder` | See below. |
| 6 | Gathering small moments | `MomentConsolidator` | In a month with ≥ 2 tiny clusters (≤ 2 photos) outside any trip, the tiny clusters become one "Moments from March" collection. |
| 7 | Similar-shot collapsing | `DuplicateDetector.similarGroups` | Within a moment, near-identical shots taken ≤ 5 min apart collapse behind "Show similar". The best shot stays; favorites always stay. |
| 8 | Place names | `PlaceNameResolving` (app: `GeocodingPlaceResolver`) | One reverse-geocode per moment/trip centre (deduplicated on a ~1 km grid, cached on disk). |
| 9 | Hero selection | `HeroSelector` | Weighted score, see below. |
| 10 | Naming | `MomentNamingService` (`LocalMomentNamingService`) | Factual titles only, see below. |

After a re-run (e.g. "Add Memories"), `MomentReconciler` maps new moments to previous ones by
asset overlap so notes, hidden state and cover choices stay attached.

## Temporal clustering heuristic

Assets are walked in capture order. For each gap between two consecutive assets, the first
matching rule decides:

1. **Gap ≤ 30 min → same moment.** A dinner, a walk, a party.
2. **Crossed into a new "logical day" and gap ≥ 3 h → new moment.** Logical days start at
   04:00, so a 00:40 photo belongs to the evening before, but sleeping splits days.
3. **Gap ≥ 8 h → new moment.**
4. **Both located, ≥ 25 km apart and ≥ 45 min passed → new moment.** You went somewhere else.
5. **Both located within 1.5 km → same moment.** A long afternoon at the same beach.
6. **Adaptive density rule.** Otherwise the gap splits if it is longer than
   `8 × median(neighbouring gaps)`, clamped to **[1 h, 8 h]**. Up to 8 gaps on each side are
   considered.

Rule 6 follows the idea behind PhotoTOC (Platt et al., 2003): a boundary is a gap that is long
*relative to the surrounding gaps*, not relative to a fixed constant. Someone who shoots dense
bursts gets split at a one-hour pause; someone who takes a photo every couple of hours keeps
their whole day together. Rules 1–5 keep results believable in the common cases.

Examples (from the tests):

| Photos | Result |
|--------|--------|
| 18:32, 18:46, 18:48, 19:02, 19:17 | one moment |
| Monday 18:32, Thursday 11:00 | two moments |
| Dec 31 22:40, 23:55, Jan 1 00:50 | one moment ("New Year's Eve") |
| 23:30, then 09:00 next day | two moments |
| 10:00, 12:30, 15:00, 17:30 (sparse shooter) | one moment |
| 20 photos 18:00–18:40, then 4 photos at 21:00 | two moments |
| Beach at 11:00–11:20, harbour 400 m away at 16:30 | one moment |

All thresholds live in `ClusteringConfiguration`.

### Moments are not months

Moments use a 04:00 "logical day" (a 00:40 photo belongs to the evening before) and can run past
midnight, so a moment's start date is never used to decide a photo's month or year. Monthly
Recap, Our Year and month/year creations group every photo by its **own** capture date
(`TemporalIndex`, see [DATA_INTEGRITY.md](DATA_INTEGRITY.md)); a New Year's Eve moment appears in
December with its December photos and in January with its January photos. Any gap of 8 hours
or more always splits, so photos from different months can never share a moment.

## Trips (chapters)

1. **Regions** — located moments are grouped by leader clustering with a 40 km radius (Kaş and
   Kekova share a region).
2. **Home** — a region is home-like when it holds ≥ 25 % of located moments across ≥ 3 distinct
   months. There can be several (long-distance couples).
3. **Trips** — consecutive moments in the same non-home region, ≤ 48 h apart, ≤ 21 days overall.
   Unlocated moments inside a run join it; trailing ones don't. A run with ≥ 2 moments over
   ≥ 2 logical days becomes a chapter.

No location data → no chapters. Moments still form from time alone.

## Duplicates and similar shots

Two signals per photo (`VisualFingerprint`):

- **dHash** — 64-bit difference hash of a 9×8 grayscale thumbnail, with a small dead-band so
  flat areas (skies) hash consistently. Robust to resizing and recompression.
- **Feature print** — Vision's image embedding, L2-normalized.

| Decision | Rule |
|----------|------|
| Duplicate copy (global) | The copy has ≤ 80 % of the original's pixels (every messaging-app re-save does), same aspect ratio (±4 %), **and** embedding distance ≤ 0.15 with hash distance ≤ 8. If the hashes carry no information (flat or low-contrast image), the embeddings alone must be ≤ 0.075. Without embeddings: hash distance ≤ 4. Same-size copies (AirDrop, "Duplicate") keep their capture time and are handled as similar shots inside their moment. |
| Similar shot (within a moment) | Taken ≤ 5 min after the burst's first shot, and embedding distance ≤ 0.35 to it (or hash distance ≤ 8 without embeddings). |

Grouping is **star-shaped**: every member must match the group's anchor directly (the best copy
to keep, or the burst's first shot). Transitive grouping (A≈B, B≈C ⇒ one group) chains loosely
related photos together; on the first end-to-end run with real Vision output it collapsed 78 of
85 photos into a handful of "duplicates". A perceptual hash is only trusted when the image has
contrast and the hash has at least 8 set and 8 unset bits.

Embeddings are only trusted if they vary. A zero, empty or non-finite feature print counts as
missing, and when a whole library's feature prints are essentially identical (Vision returned a
constant vector — seen in the CI simulator) the engine ignores embeddings for that run and sets
`MemoryEngineDiagnostics.embeddingsIgnored`. Debug builds log every duplicate pair with sizes,
dates and both distances (`Duplicate: copy … → kept …`) to support tuning on real libraries.

The copy kept is: favorite → has location → higher resolution → earlier. Nothing is deleted.
Thresholds are in `SimilarityConfiguration` and **should be tuned on real libraries** (see
"Tuning" below).

A copy attached to its original's moment keeps its own capture date, but as the same memory it
is never placed in a month or year of its own.

## Hero selection

`AssetScorer` computes a weighted average of normalized signals, then adds bonuses and
penalties:

| Signal | Default weight |
|--------|----------------|
| Face capture quality | 0.30 |
| Face count suitability (2 faces = 1.0, 1 = 0.7, 3–5 = 0.75, 0 = 0) | 0.15 |
| Sharpness (Laplacian variance) | 0.20 |
| Aesthetics (Vision) | 0.20 |
| Orientation fit for a 4:5 card | 0.10 |
| Resolution | 0.05 |
| Uniqueness (not one of many near-identical takes) | 0.05 |
| **Favorite** | **+0.50** |
| Utility image (receipt, document) | −0.60 |
| Screenshot | −0.60 |
| Video | −0.10 |

Missing signals count as neutral (0.5). A cover chosen by the user ("Use as Cover") always wins
while that photo exists. Weights live in `HeroScoringWeights`.

## Naming

Names describe *when* and *where*, never how it felt. The app cannot know that.

| Situation | Title |
|-----------|-------|
| Known place away from home | **Kaş** · August 2025 |
| At home (a region with ≥ 25 % of moments over ≥ 3 months) | **June Evening** · June 2025 — the place appears on the card instead |
| Inside a trip, same place as the trip | **Friday Evening** · August 8 |
| Inside a trip, somewhere else | **Kekova** · August 8 |
| No place, part of a day | **December Evening** |
| No place, a long weekend day | **A Saturday in August** |
| No place, several days over a weekend | **August Weekend** |
| Gathered small moments | **Moments from March** · 2024 |
| Dec 31 evening | **New Year's Eve** |
| No date | **Without a date** |

`MomentNamingService` is async and receives only factual context, so a future AI naming
service can slot in without changing the engine — and must follow the same rule.

## Found for You

`FoundForYouService` picks one older, good-looking moment that hasn't been shown recently:

- Never hidden moments, never ones marked "Don't show this again".
- Moments shown in the last 21 days rest.
- Prefers memories at least 60 days old (falls back to younger ones only if nothing older exists).
- Score = age (saturating at 2 years) + photo quality + anniversary bonus (same week in a past
  year) + favorite bonus − times already shown, plus a small deterministic per-day variation.
- Inside the chosen moment it prefers a strong photo that is **not** the cover — the timeline
  already shows the cover; rediscovery is the point.
- The choice is stable for the whole day.

## Tuning

Everything above is data: `ClusteringConfiguration`, `ChapterConfiguration`,
`ConsolidationConfiguration`, `SimilarityConfiguration`, `HeroScoringWeights`,
`FoundForYouConfiguration`. The most uncertain values are the feature-print thresholds, because
Vision's embedding distances vary between model revisions. The safest way to tune them is on a
real device with a few real libraries: log `featureDistance` for pairs a person marks as
"same photo" / "similar" / "different".
