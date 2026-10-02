# Architecture — Relive (Prototype 0.1, v0.2 creation, v0.3 Memory Book and Trends)

## Goals that shaped it

1. Prove one hypothesis: *metadata + clustering + beautiful presentation* can turn 50–500 selected
   photos into a story that feels meaningful. Everything else is secondary.
2. Local-first and private: photos stay on the device, analysis happens on the device, no account.
3. A foundation that can grow into a real product without a rewrite.

## Layout

```
Relive.xcodeproj            Xcode 16+ project (synchronized folders — add files on disk, no project edits)
Config/Info.plist           Keys that can't be generated from build settings
Relive/                     iOS app target (SwiftUI)
  App/                      Entry point, dependency graph, root view
  State/                    @Observable models: AppModel, StoryStore, PhotoSelectionModel
  Persistence/              SwiftData models and StoryRepository
  Services/                 PhotoKit, image loading, Vision, geocoding, share cards, analytics
  DesignSystem/             Palette, typography, spacing, button styles
  Utilities/                Date formatting, UIKit presentation helpers
  Views/                    Onboarding, Main (tabs), Today, Story, Us, Components
  Creation/                 v0.2 creation: requests, models, rendering, export, Create tab
  Book/                     v0.3 Memory Book: page canvas, reader, editor, trip/month/year picker
  Trends/                   v0.3 Trending Now: compiled recipes, catalog store, trend screens
  Resources/                Asset catalog
Packages/ReliveCore/        Foundation-only Swift package: models + Memory Engine + tests
docs/                       This file, MEMORY_ENGINE.md, CREATION.md, MEMORY_BOOK.md, TRENDS.md
.github/workflows/ci.yml    Core tests on Linux and macOS, app build with Xcode
```

### Why a separate package

Everything that decides *what the story is* — clustering, duplicates, scoring, naming, Found for
You, reconciliation, statistics — is plain Swift in `ReliveCore`. It has no PhotoKit, Vision or
SwiftUI imports, so:

- it is fully unit-tested (Swift Testing) and runs anywhere, including Linux CI;
- each stage is a small value type with its own configuration, replaceable independently;
- a future server-side or macOS tool could reuse it unchanged.

The app injects platform work through protocols: `AssetAnalyzing` (Vision), `PlaceNameResolving`
(reverse geocoding), `MomentNamingService` (deterministic now; an AI implementation could come
later), `AnalyticsTracking` (logging now; a provider later).

## Minimum deployment target: iOS 18.0

- **SwiftData** had significant rough edges on iOS 17; iOS 18 is the first release we'd trust
  with user-authored notes.
- **Vision aesthetics** (`CalculateImageAestheticsScoresRequest`, iOS 18) gives a quality signal
  for cover selection and flags "utility" images (receipts, documents) so they never become covers.
- **SwiftUI** conveniences used throughout (`@Entry`, the `Tab` API, `@Observable`, `onChange`
  with initial values).
- As of late 2026, iOS 18+ covers the overwhelming majority of active iPhones, and any iPhone that
  runs iOS 18 has the Neural Engine Vision needs.

## Data flow

```
PhotosPicker / limited-library picker
        │  identifiers only
        ▼
PhotoKitLibraryService ──► MemoryAsset (value snapshot of metadata)
        │
        ▼
StoryStore.process() ──► MemoryEngine (ReliveCore, off the main actor)
        │                   ├─ VisionAssetAnalyzer (thumbnails from PhotoImageLoader)
        │                   └─ GeocodingPlaceResolver (one lookup per moment, cached)
        ▼
MomentReconciler ──► Story ──► SwiftDataStoryRepository
        │
        ▼
TimelineBuilder / StoryStatistics / FoundForYouService ──► SwiftUI views
```

- Views never see PhotoKit objects; they get `MemoryAsset`s and ask `PhotoImageLoader` for pixels
  by identifier.
- `StoryStore` is the single writer for story data. `AppModel` owns onboarding, navigation and the
  product signals (Found for You, validation question).
- Engine progress flows through an `AsyncStream` so the processing screen updates in order.

## Photo access

Relive asks for photo library access only when the user taps **Choose Our Photos**, after
explaining why.

- **Limited access (the path the prompt encourages):** the system's own picker defines exactly
  which photos Relive can see. Relive mirrors that selection. "Add Memories" reopens the same
  system picker.
- **Full access:** Relive still doesn't read the library. The user picks items in `PhotosPicker`
  and only those identifiers are stored.
- **Denied / restricted:** nothing is read; the user is pointed to Settings.
- `PHPhotoLibraryPreventAutomaticLimitedAccessAlert` stops iOS from re-prompting on every launch.

Only **references** (local identifiers) and metadata are stored. Pixels are decoded on demand
into an in-memory cache and never written to disk. When the app becomes active it re-checks which
references still resolve; deleted or de-selected photos disappear from the story and statistics
without breaking anything, and come back if access returns.

## Persistence (SwiftData)

| Model | Holds | Why this shape |
|-------|-------|----------------|
| `StoredProfile` | Partner name, optional own name, start date + precision, onboarding progress, validation answer, Found-for-You record | User-authored, one record |
| `StoredMomentState` | Note, hidden, don't-resurface, cover override, surfacing history — per moment | User-authored and irreplaceable, so modelled explicitly |
| `StoredAsset` | Identifier + JSON `MemoryAsset` (metadata and cached analysis) | Derived, rebuildable from the library |
| `StoredStorySnapshot` | JSON `Story` (versioned) | Derived, rebuildable by re-running the engine |
| `StoredCreatedAsset` (v0.2) | Identifiers of images Relive saved | So they're never imported back as memories |
| `StoredMemoryBook` (v0.3) | Book id + JSON `MemoryBook` definition (photo identifiers, style, cover, note) | User-authored; small; never holds image data |

All properties have defaults and there are no unique constraints, which keeps the schema
compatible with CloudKit-backed SwiftData if sync is added. `StoryRepository` is a protocol, so
views and stores don't depend on SwiftData directly.

## Concurrency

- UI state (`AppModel`, `StoryStore`, repository) is `@MainActor`.
- `MemoryEngine` is a `Sendable` struct; `buildStory` runs off the main actor and analyzes up to
  4 assets at a time in a task group, at utility priority and never on every core, so the
  interface stays responsive. It honours cancellation.
- `GeocodingPlaceResolver` is an actor (serial lookups, disk cache, failure back-off).
- `PhotoImageLoader` wraps thread-safe PhotoKit/`NSCache` APIs; requests are cancelled when views
  disappear.
- Processing requests extra background time so switching apps briefly doesn't lose the run.
- The core package builds in Swift 6 language mode. The app target uses Swift 5 mode with
  complete strict-concurrency checking, so any remaining issues show as warnings rather than
  blocking a build.

## Privacy summary

- No account, no server, no third-party SDKs.
- v0.3 adds an *optional* remote trend catalog (plain JSON over HTTPS, validated, never code) that
  is not configured, and an AI provider *protocol* with no implementation. Neither sends
  anything. See [TRENDS.md](TRENDS.md).
- Photos are analyzed on device from small thumbnails. Vision is used only for face *presence*
  and capture quality — never identity.
- The only network request in the pipeline is reverse geocoding: Apple's geocoder receives one
  coordinate per moment (not photos), and results are cached locally.
- Analysis never downloads originals from iCloud; if only a cloud original exists, analysis
  degrades gracefully. Display does allow iCloud downloads so the user sees their photos.
- Analytics events only go to the local unified log and carry counts and flags — never names,
  notes or places.

## Extending later (without rewrites)

- **AI naming** — implement `MomentNamingService`; it receives factual context only.
- **Sync / partner accounts** — `StoryRepository` is the seam; the SwiftData schema is
  CloudKit-compatible.
- **Analytics provider** — implement `AnalyticsTracking`.
- **Better clustering** — each stage is a separate type with its own config and tests.

## v0.2: creation

Collages, story cards and recaps follow the same split as the rest of the app: decisions in
ReliveCore (`Creation/` — layouts, Make it for me, captions, story sequences, recaps, Surprise
Memory; pure and tested on Linux), drawing and I/O in the app (`Relive/Creation/`). Canvases are
laid out in 1080-point design space and the preview and export draw the same view at different
scales. A single `CreationRequest` on `AppModel` opens the creation flow full screen from any
entry point (Create, Moment Detail, recaps, Surprise Memory). See [CREATION.md](CREATION.md).

Persistence additions are additive and migrate automatically: four optional `StoredProfile`
fields for today's Surprise Memory, and a `StoredCreatedAsset` entity listing images Relive saved
to the photo library so they are never imported back as memories.

## v0.3: Memory Book and Trends

Same split again. In ReliveCore:

- `Book/` — `MemoryBook` (the saved definition: source, photo identifiers, style, cover, note),
  `MemoryBookBuilder` (sources and light edits with limits) and `BookLayoutEngine` (deterministic
  pagination into cover, note, trip title, opener, photo and closing pages; style-independent
  pagination, style-specific geometry).
- `Trends/` — `TrendDefinition`/`TrendCatalog` (data), `TrendCatalogParser` (lossy, validated
  parsing), `TrendCatalogResolver` (highest valid revision, bundled as the floor),
  `TrendCatalogFilter` (availability for this app and day), `StarterTrendCatalog` (bundled JSON),
  and `AITrends` (`AITrendProvider` protocol, `AITrendCoordinator`, `CreationEntitlements`,
  `TrendPrivacyGate`). No provider is implemented.
- `CreationLibrary` gained the `.trip` source and trip facts.

In the app, `Relive/Book/` draws and edits books, and `Relive/Trends/` holds the compiled recipes
(`TrendRecipeRegistry`, `id@version`), `TrendCatalogStore` (injected through the environment
from `AppEnvironment`) and the Trending Now screens. Both reuse the v0.2 canvas, image-loading and
export infrastructure. `StoryStore` gained the saved books; `StoryRepository` gained
`loadBooks`/`saveBook`/`deleteBook`.

Persistence is additive (one new entity, `StoredMemoryBook`) and migrates automatically; a
hosted test opens a v0.2-shaped store with the v0.3 schema. See
[MEMORY_BOOK.md](MEMORY_BOOK.md) and [TRENDS.md](TRENDS.md).
