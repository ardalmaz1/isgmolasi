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

## Phase 2 (Made for You): in progress

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

**Core tests:** 323 passed on Linux.

## Next step

1. Get CI green.
2. Review the F screenshots.
3. Write the final report.

Phase 3 candidate: Monthly Recap 2.0 / Relive Wrapped built on plans and suggestions.
