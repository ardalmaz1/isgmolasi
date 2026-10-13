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

## Next step (Phase 2)

Build the first user-facing surface on the plan — "Made for You" or Monthly Recap 2.0 — using
`MemoryIntelligenceEngine.plan(for:target:)`, `recommendations` and `sequence.sections`. Then
tune `RankingWeights` on a real library, using the DEBUG `intelligence_plan` lines.
