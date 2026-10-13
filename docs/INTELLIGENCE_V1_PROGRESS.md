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

**Tests:** `Packages/ReliveCore/Tests/ReliveCoreTests/MemoryIntelligenceTests.swift`, 30 tests
covering fixtures A–K, user intent, periods and titles, plans, integration, and creation minimums (32 in all).

**Docs:** `docs/MEMORY_INTELLIGENCE.md`, plus additions to `docs/ARCHITECTURE.md` and the
README.

## Test results

- ReliveCore on Linux: 303 passed (271 before this phase; 32 new; no existing test changed).
- The app build, hosted tests and UI tests come from CI on the final commit (see the final
  report).

## Next step (Phase 2)

Build the first user-facing surface on the plan — "Made for You" or Monthly Recap 2.0 — using
`MemoryIntelligenceEngine.plan(for:target:)`, `recommendations` and `sequence.sections`. Then
tune `RankingWeights` on a real library, using the DEBUG `intelligence_plan` lines.
