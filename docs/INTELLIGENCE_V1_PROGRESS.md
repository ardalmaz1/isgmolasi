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
- **Test infrastructure:**
  - A hosted test that put the whole tab view in a window broke every later UI test's
    onboarding on the shared simulator. It has been removed; it had already shown that
    presentation works.
  - Commercial's tab-bar scrolling now uses short drags without momentum.

## Next step

Tune the ranking, the suggestion weights and the recap chapter thresholds on a real library,
using the DEBUG `intelligence` lines (`intelligence_plan`, `made_for_you`, `recap_plan`).
