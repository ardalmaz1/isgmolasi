# Intelligence v1 — progress checkpoint

Branch `claude/compassionate-goldberg-rsn0w6`. If you resume this task, read this first, then
run `git status` and `git log --oneline -10`.

## Phase 1 (Memory Intelligence Core): complete

**Core** (`Packages/ReliveCore/Sources/ReliveCore/Intelligence/`):

| File | Contents |
|---|---|
| `MemoryCandidate.swift` | Normalized signals per memory; `DayKey` |
| `MemoryRanker.swift` | `IntelligenceTarget`, `RankingWeights`, `MemoryRanker`, `SimilarityClusters`, `VisualDiversityEngine` |
| `PeriodDescriptor.swift` | Periods, labels, hemisphere-aware seasons |
| `FactualTitleBuilder.swift` | `FactualTitle`, `FactualTitleBuilder`, `FactualTextPolicy` |
| `MemorySequencePlanner.swift` | `MemorySequence`, `CreationKind`, `CreationRecommendation`, `CreationRecommender` |
| `MemoryIntelligenceEngine.swift` | `IntelligenceRequest`, `MemorySelectionPlan`, the engine, `IntelligenceDiagnostics` |

**Integrations:**

- `CreationLibrary.initialPhotos` (automatic sources)
- `StoryDesigner.photos` and its lead
- `BookLayoutEngine` default cover
- `CollageEditorModel.makeItForMe` lead order
- the DEBUG `IntelligenceLog` sink (`Relive/Services/MetadataDiagnostics.swift`, installed in
  `AppEnvironment.live()`)

**Tests:** `Packages/ReliveCore/Tests/ReliveCoreTests/MemoryIntelligenceTests.swift`, 32 tests
covering fixtures A–K, user intent, periods and titles, plans, integration, and creation minimums.

**Docs:** `docs/MEMORY_INTELLIGENCE.md`, plus additions to `docs/ARCHITECTURE.md` and the
README.

## Test results

- ReliveCore on Linux: 303 passed (271 before this phase; 32 new; no existing test changed).
- CI run 38473871505 on commit a98dde2 (all four jobs green):
  - builds with Xcode 16.4 and Xcode 26;
  - 95 hosted tests;
  - 7 UI tests.
- The first full CI run of the integration found one regression, now fixed: a collage from a
  look-alike moment had collapsed to one photo. Near-identical photos now fill in up to each
  creation's minimum.

## Phase 2 (Made for You): complete

**Core:**

- `Packages/ReliveCore/Sources/ReliveCore/Intelligence/MadeForYou.swift`:
  `MadeForYouEngine`, `MadeForYouSuggestion`, `SuggestionHistory`.
- Tests: `MadeForYouTests.swift` (20).

**App:**

- `Relive/Intelligence/MadeForYouStore.swift` and `MadeForYouViews.swift`.
- The Create section and the Today card; injected from `AppEnvironment`.

**Tests:**

- `ReliveTests/MadeForYouAppTests.swift` (9 hosted tests).
- `ReliveUITests/MadeForYouUITests.swift` (screenshots F01–F07).

**Docs:** `docs/MADE_FOR_YOU.md`.

## Test results

- CI run 38611262856 on fbce238 (all four jobs green):
  - 323 core tests;
  - builds with Xcode 16.4 and Xcode 26;
  - 104 hosted tests;
  - 8 UI tests.
- The sample library produced 3 suggestions: the Kaş trip (as a Memory Book), Spring 2025 and
  Winter 2025. Its 2025 book and year were suppressed by overlap.
- Fixed along the way:
  - a hosted test assumed a collage where the engine (correctly) offers a story;
  - a container accessibility identifier hid the cards' own identifiers;
  - the hero card's subtitle row was squeezed at accessibility text sizes (now stacked).

## Phase 3 (Monthly Recap 2.0 / Our Year 2.0): complete

**Core** (`Packages/ReliveCore/Sources/ReliveCore/Intelligence/Recap/`):

- `RecapStoryPlanner.swift`: `RecapPeriod`, `RecapInsights`, `RecapChapter`, `RecapPlan`, and
  the planner itself (adaptive chapters, compact fallback, DEBUG `diagnosticsLine`).
- `EditorialText.swift`: `EditorialFacts`, `EditorialTextProviding`, the deterministic provider,
  and `ValidatedEditorialTextProvider` (the factual contract for any future AI text).
- Tests: `RecapStoryPlannerTests.swift` (18). The suite now has 341 core tests.

**App:**

- `Relive/Recap/RecapExperienceView.swift` and `RecapPageView.swift`.
- `AppModel.openRecap / startCreationFromRecap / recapDismissed`; one full-screen cover in
  `MainTabView`.
- Made for You / Today recap suggestions open the immersive recap. Play buttons on Monthly
  Recap and Our Year. `MadeForYouStore.recordMade(source:)`.
- Analytics: `recap_chapter_viewed`, `recap_completed`, `recap_creation_started`,
  `recap_share_started`, `recap_share_completed`; `recap_opened` carries `experience`.

**Tests:**

- `ReliveTests/RecapAppTests.swift` (7) and the updated Made for You routing test.
- `ReliveUITests/RecapUITests.swift` (screenshots R*), also run on an iPhone SE in CI
  (screenshots E*).

**Docs:** `docs/RECAP_2.md`.

### Found and fixed along the way

- **Play did nothing (a pre-existing app bug).**
  - Cause: `AssetImageView` draws a fill-mode photo larger than its frame and only clipped the
    drawing, so the invisible overflow still took touches. A tall photo under Monthly Recap's
    Play button swallowed every tap. The DEBUG log confirmed it: no recap request at all.
  - Fix: photos now take touches only inside their frame and are not touch targets.
  - Impact: this affected any control next to a tall photo in a fill frame.
- **Thin recaps.** A month with enough memories but only an opening and a closing worth telling
  (24 near-identical photos of one evening) was a two-page "recap". Fewer than 5 true chapters
  now gives one compact page.
- **Planning thread.** Planning now runs off the main thread, and the header with Close shows
  while it does. It takes 26–31 ms on the sample library.
- **Duplicate identifier.** The closing card's Share and Monthly Recap's toolbar Share shared
  an identifier.
- **Screenshot review:**
  - the Premium page's 4:5 blurred photo pushed its action behind the footer (now 4:3);
  - photo chapters' 4:5 hero hid the smaller photos (now square).
  - at accessibility text sizes the hero filled the screen and pushed the words below the fold
    (heroes are now 16:9 at those sizes).
- **Test infrastructure:**
  - A hosted test that put the whole tab view in a window broke every later UI test's
    onboarding on the shared simulator. It has been removed; it had already shown that
    presentation works.
  - Commercial's tab-bar scrolling now uses short drags without momentum.

## Phase 4 (Memory Movie V1): complete

**Core** (`Packages/ReliveCore/Sources/ReliveCore/Movie/`):

- `MoviePlan.swift`: plan, scene, settings, motion, transition, framing, text, soundtrack
  (silent), eligibility.
- `MovieStoryPlanner.swift`: the edit, on top of Memory Intelligence.
- `MovieTimeline.swift`: frames over time and geometry, shared by the preview and the export.
- Movie is a real `CreationKind`/recommendation, and Made for You offers large varied trips as a
  film.
- `memoryMovie` is Premium and not part of the free creation; there is a `.memoryMovie` paywall
  entry ("Keep this movie"); local analytics events.
- `MovieState` in `SavedCreation` (drafts).
- Tests: `MovieStoryPlannerTests.swift` (24). Core total: 365.

**App** (`Relive/Movie/`):

- `MovieEditorModel`, `MovieEditorView`, `MoviePreviewView`.
- `MovieDrawing` (one Core Graphics frame drawer for preview and export).
- `MovieRenderer` (AVAssetWriter, H.264, 30 fps, 1080×1920 / 1920×1080).
- `MovieExportController` (progress, cancel, background, Save to Photos, Share).
- Create, Made for You / Today, Recap closing, My Creations and drafts are wired.

**Tests:**

- `ReliveTests/MovieAppTests.swift` (11 hosted tests, including real renders).
- `ReliveUITests/MovieUITests.swift` (screenshots V*, and W* on iPhone SE).

**Docs:** `docs/MEMORY_MOVIE.md`.

### Results

- CI run 38762667081 on 100f15a, all four jobs green:
  - 365 core tests;
  - Xcode 16.4 and Xcode 26 builds;
  - 122 hosted tests;
  - 10 UI tests on iPhone 16, plus the recap and movie UI tests again on iPhone SE.
- Export timing on the CI simulator (not physical-device figures):
  - hosted test, 16:9 1920×1080, 25.4 s movie, 14 scenes, solid stand-in photos: rendered in
    34.7 s, 3.6 MB;
  - UI test with the sample library, 9:16 1080×1920, 38.1 s movie, 14 scenes, 1,142 frames:
    rendered in 67.3 s, 31 MB.
- Screenshot review fixes:
  - larger movie captions;
  - opaque frames are drawn without an offscreen layer, to make export faster;
  - the movie UI test checks Made for You before exporting (exporting retires that suggestion,
    which is now asserted) and reviews dark mode and the largest text size with a trip.

## Phase 5 (AI Editorial Intelligence): complete

**Core** (`Packages/ReliveCore/Sources/ReliveCore/Intelligence/Editorial/`):

- `EditorialModel.swift`: the shared model:
  - surfaces, request kinds, languages, fact classes, authorship;
  - context, request (length limits), candidate, rejection codes, result;
  - `EditorialChoice`, the user's decision.
- `EditorialValidator.swift`: one validator for every surface, English and Turkish.
- `EditorialPipeline.swift`:
  - the deterministic writer (English and Turkish, with Turkish case endings);
  - the pipeline (cache, at most three variants, events);
  - the router (model alternatives, silent fallback).
- `EditorialPrompt.swift`: facts-only instructions and prompt, and reply parsing.
- `FactualTextPolicy` was extended (English and Turkish feelings and rankings).
- Recap text uses the shared validator.
- Made for You trip wording comes from the pipeline. Movie opening-title variants are stored in
  `MovieSettings.titleChoice`.
- New analytics events: `editorial_*`.
- Tests: `EditorialIntelligenceTests.swift`, `EditorialSurfaceTests.swift`. Core total: 396.

**App** (`Relive/Editorial/`):

- `AppleOnDeviceEditorialProvider`: FoundationModels behind `canImport` and `#available(iOS 26)`.
- `EditorialService`: the router, analytics forwarding, and a DEBUG `editorial_provider` line.
- Memory Movie editor: a **Title** section with Try another / Edit / Remove / Reset.

**Tests:**

- `ReliveTests/EditorialAppTests.swift` (hosted).
- `ReliveUITests/MovieUITests.swift`: title → Try another → own words → relaunch → kept.
  Screenshots V10/V11, and W10/W11 on iPhone SE.

**CI:**

- `scripts/check-no-secrets.sh`, run in the Linux job.
- FoundationModels SDK inspection and a weak-linking check in the Xcode jobs.

**Docs:** `docs/EDITORIAL_INTELLIGENCE.md`.

### Results

- CI run 38810719425 on c2208c4, all four jobs green:
  - 396 core tests;
  - Xcode 16.4 and Xcode 26 builds;
  - 130 hosted tests;
  - 12 UI tests on iPhone 16, plus the recap and movie UI tests again on iPhone SE.
- The FoundationModels API was confirmed in the Xcode 26.3 SDK (iPhoneSimulator 26.2). The app
  links it weakly (`LC_LOAD_WEAK_DYLIB`).
- On the CI simulator the provider reports `sdkWithoutFoundationModels`, because the simulator
  job builds with Xcode 16.4. Relive's own words are used.
- Editorial wording takes about 0.6 ms per uncached request and about 2 µs cached (Linux CI
  container).
- Screenshot review:
  - V10/V11 and W10/W11 show the title flow;
  - V8x/W8x show dark mode and the largest text size; at that size the title buttons wrap one
    per row;
  - F01 shows the Made for You card "Four days in Kas.".
- Fixed during review:
  - the UI test now clears the title field from its end;
  - the card's spoken label no longer doubles the full stop.

**Not done in this phase (documented):**

- Memory Book title choice. It needs a SwiftData field; Book, Story and Collage keep their
  factual titles.
- The on-device model has not been run on a physical Apple Intelligence device.

## First Experience V2 (activation): implemented

Not an intelligence phase: onboarding rebuilt on the existing engines. See
`docs/FIRST_EXPERIENCE_V2.md`.

**Core:**

- `Discovery/MemoryDiscovery.swift`: bounded, metadata-first possible moments; face count used
  only for ranking; kept-only import.
- `Discovery/FirstDiscovery.swift`: the First Discovery hierarchy (movie, recap, Made for You,
  moment, small story).
- `TimelineBuilder`: a "Before …" section for moments before the relationship start.
- `MemoryEngineProgress.facts`: moments, trips and places, reported once known.
- New `AnalyticsBucket` helper and First Experience analytics events.
- Tests: `DiscoveryTests.swift`. Core total: 415.

**App:**

- New onboarding steps: choose how to begin, discovery privacy, discovering and possible
  moments, a new manual path, and First Discovery (replaces the statistics reveal).
- `DiscoveryModel`, and `PhotoLibraryProviding.discoveryAssets(limit:)`.
- Start-date skip, `Together since` / `Since your first memory`, editing the date in Us.
- First-session recap protection.
- Privacy wording in onboarding and Us.

**Tests:**

- Hosted: `ReliveTests/FirstExperienceTests.swift`.
- UI: `ReliveUITests/FirstExperienceUITests.swift` (N*, and Q* on iPhone SE).
- Every other UI test's onboarding helper now takes the manual path.

## Next step

- Validate First Experience V2 on a real iPhone and library. Measure:
  - discovery timings (`discovery_timing`);
  - how often possible moments are right;
  - how often the first discovery is a Movie;
  - iCloud-only representatives;
  - the real permission and picker experience.

- Run the Memory Movie title on an iPhone with Apple Intelligence. Check the
  `editorial_provider` status, then compare the `editorial_validation` accept and reject codes.
  Tune the instructions if most lines are refused.

- Validate Memory Movie on a real iPhone: export time, memory, backgrounding and Photos saving.
- Tune the ranking, the suggestion weights, the recap chapter thresholds and the movie rhythm on
  a real library, using the DEBUG `intelligence` and `movie` lines (`intelligence_plan`,
  `made_for_you`, `recap_plan`, `movie_plan`, `movie_export_*`).
