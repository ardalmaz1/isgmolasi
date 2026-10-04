# Personal collection (v0.4)

Favorites, My Creations, Drafts and Create Home 2.0. Everything here is private and local:
nothing leaves the iPhone, there is no account, and nothing is shared with anyone.

| Piece | Model (ReliveCore) | Storage (app) | Screens |
|---|---|---|---|
| Favorites | `FavoriteKind`, `FavoriteRecord`, `FavoriteCollection` | `StoredFavorite` | heart buttons, Favorites |
| Collages and stories | `SavedCreation`, `CollageState`, `StoryState` | `StoredCreation` (JSON payload) | My Creations, editors |
| Drafts | `SavedCreation` with `status == .draft` | same record | Continue Editing, Drafts |
| Books | `MemoryBook` (unchanged model, v0.3) | `StoredMemoryBook` | My Creations, reader |

`KeptItem` (app) lists collages, stories and books side by side; books keep their own model and
storage, so no second persistence architecture was added for them.

## Favorites model

- Three kinds: a **memory** (a photo or video, by its Photos `localIdentifier`), a **moment**
  (its `MomentID`) and a **creation** (a collage, story or book, by its UUID).
- A `FavoriteRecord` is `(kind, identifier, favoritedAt)`. `FavoriteCollection` keeps one record
  per `(kind, identifier)`: adding twice is a no-op, duplicates in storage collapse to the
  earliest date, and `records` are ordered by `favoritedAt` (newest first), then kind, then
  identifier — deterministic for any number of favorites.
- **Independence.** A moment favorite and its photos' favorites are separate records. Favoriting a
  moment never favorites its photos; favoriting a photo never favorites its moment.
- **What favoriting never touches:** the photo, its metadata or EXIF, Apple Photos' own
  favorite flag (`MemoryAsset.isFavorite` stays as Photos reported it), clustering, duplicates,
  chronology. It is a separate list (`StoredFavorite`); hosted tests compare the story and every
  asset before and after.
- **Missing.** Favorites of memories or moments that aren't in the story right now (hidden,
  deleted, after Start Over) stay stored but are not shown or offered. They return when the same
  photos return: photo identifiers are Photos' own, and moment identifiers are stable
  (`StableIdentifier.uuid(kind, first member)`), so the same photos give the same moment.
- **Rapid taps** update the in-memory collection and write one small record per change; the
  final state always matches the last tap (tested with 41 toggles).

### One heart

`FavoriteButton` is the only control: in the full-screen photo viewer (the photo on screen), in a
moment's toolbar (the moment), in a book reader and a finished collage or story (the creation).
Grid context menus offer *Favorite / Remove from Favorites*. VoiceOver reads it as *"Favorite,
Selected"* / *"Favorite, Not selected"* (moments: *"Favorite moment"*). Grid thumbnails show a
small heart for Relive favorites only.

### Favorites as a creation source

`CreationSource.favorites` means **Relive favorites**: `CreationLibrary.favoritePhotos` — usable
favorited photos in visible moments, in the order they were taken. Collage, Story Maker and
Memory Book can start from it (Favorites → *Create from Favorites*, Create → Favorites, the book
source dialog). When there aren't enough, the flow says so: *"Add a few more favorites to make a
story."* — nothing is added to fill the gap.

Creation metadata still comes from the photos (the one rule, `CreationLibrary.facts`): a
favorites collage of August and September photos is described by those photos, never as
"Favorites".

**Selection preference.** In every *Make it for me* and automatic pick, a Relive favorite gets
`CreationLibrary.favoritePreference` (+0.2) on its quality score. This nudges, it doesn't
override: chronology, orientation, duplicates and the source's own photos still decide. Only a
creation whose source *is* Favorites uses favorites alone.

## Saved creation model

```
SavedCreation
├── id, version, kind (collage | story), status (draft | saved)
├── createdAt, updatedAt, savedAt?, exportedAt?
├── source: CreationSource          // a hint for the title, used only when every photo fits it
├── collage: CollageState?          // photoIDs (order), style, aspectRatio, showsTitle/Date/Place
├── story:   StoryState?            // the whole StoryDesign: cards, order, layouts, photos,
│                                   //   style, show/hide choices, variation, source
└── assetSnapshots: [MemoryAsset]   // metadata of its photos (no pixels, no analysis)
```

- **State, not pixels.** No image is stored. A creation is drawn again from the user's photos
  whenever it is shown or exported (previews use small thumbnails).
- **Words are never stored as truth.** Titles, dates and places are recomputed from the photos
  each time (`SavedCreation.facts(in:)`, `StoryDesign.refreshFacts`). A story's cards keep the
  facts they were designed with, but every edit refreshes them, and reopening never prints a
  fact the photos don't support.
- **Snapshots** make a creation self-describing: photos picked from the photo library, or a
  creation reopened after Start Over, still have their date, place and shape. Memories in the
  story always win over snapshots.
- **Books** stay `MemoryBook`. Since v0.4 `StoryStore.saveBook` snapshots every photo of a book
  too (`MemoryBook.captureSnapshots`), for the same reason.

## Draft lifecycle

```
            new editor (Relive's own first design — nothing is written)
                 │ first change by the user
                 ▼
   ┌──────────► draft ◄──────────┐   later changes update the same record
   │  (Continue Editing, Drafts)  │   (debounced 0.8 s; flushed on Close / background)
   │             │
   │   Save, Save to Photos, or a completed Share
   │             ▼
   │           saved  (My Creations; same id, same record — never a copy)
   │             │ reopened and edited → updated in place
   └── Delete (confirmation) removes the record; photos are untouched
```

- `CreationKeeper` (app) owns this for one editor. `changed()` schedules a write after
  `CreationKeeper.pause` (800 ms); further changes reset the timer, so dragging through styles
  writes once. `flush()` writes immediately — called when the editor closes and whenever the
  scene leaves `.active` (backgrounding, app switcher). Writes go through
  `StoryStore.saveCreation`, which snapshots photo metadata and persists the record.
- `markSaved()` (the toolbar *Save*) and `markExported()` (after Save to Photos, or a share the
  user completed) move the **same** record to `saved`; `savedAt` keeps the first time.
- After Delete, the keeper is told to `forget()` so a pending or later change can't write the
  record back.
- **Completing a draft never duplicates it**: there is only ever one record per creation id
  (hosted tests: draft → edits → Save leaves one record; the repository dedupes by id).
- Which writes happen on the main thread: the store and SwiftData's main context are main-actor
  bound, so the (debounced) write itself runs there. A record is a few kilobytes of JSON (state
  plus metadata of at most 12 collage photos or a story's photos); there is no image encoding or
  file IO in it. Rendering and JPEG encoding for exports stay off the main thread as before.

Analytics (local log only, kind of creation only): `draft_created`, `draft_resumed`,
`draft_deleted`, `creation_saved`, `creation_reopened`, `creation_deleted`.

## Create Home architecture

Order, top to bottom:

1. **Continue Editing** — only when drafts exist: the latest draft's preview, factual title,
   *"Story · Edited 12 minutes ago"* (refreshes each minute), **Continue**, and *See All Drafts*.
   Touch and hold for *Delete Draft*.
2. **Your Creations** — the eight most recent finished collages, stories and books with *See
   All*; when there are none: *"Things you make with Relive will appear here."* (no
   placeholders).
3. **Favorites** — up to four favorite photos, *"You have 8 favorites."* (a count, nothing more),
   **Create from Favorites** and *See All*. Empty: *"Favorite memories to keep them close and
   create from them later."*, once, with no button.
4. **Create Something** — Trending Now and the five tools (Memory Collage, Story Maker, Memory
   Book, Monthly Recap, Our Year).

Drafts and creations show even before there is a story (for example after Start Over); the
favorites and tools need memories. Personalization is factual only — counts and dates, never
rankings or feelings.

Navigation: `CollectionRoute` (`favorites`, `creations`, `drafts`, `book(UUID)`) is registered on
both the Create and Us stacks with `collectionDestinations()`, so the collection is reachable
from either without a new tab. Collages and stories reopen full screen in their editor through
`AppModel.open(_:)` → `CreationStart.resume(UUID)`; books open in the reader.

## Start Over

Start Over resets the relationship story and onboarding. It keeps what the couple made and chose.

| Data | After Start Over |
|---|---|
| Profile (names, start date), onboarding progress | removed — onboarding runs again |
| Selected memories (asset records) | removed from Relive (the Photos app is never touched) |
| Story: moments, trips | removed; rebuilt from the photos chosen again |
| Notes, hidden moments, chosen covers | removed |
| Favorites | **kept**; hidden until their memories/moments are back, then shown again |
| Books | **kept**, with metadata snapshots of every photo |
| Collages, stories | **kept** |
| Drafts | **kept**; photos not in the new story draw from snapshots; deleted ones show as missing |
| Export exclusion list (`StoredCreatedAsset`) | **kept** — Relive's own images can never become memories |

The confirmation says this in plain words. (Before v0.4, Start Over also deleted books; this
changed on purpose.) UI tests use a separate debug-only `eraseEverything()` for a truly empty
store.

## Missing assets

A photo is missing when the library no longer has it, or Relive can no longer see it (limited
access changed). `StoryStore.refreshAvailability()` checks story photos and every snapshot-only
photo of books and creations.

- **Never a crash, never a substitute.** Nothing is swapped in for a missing photo.
- **Collage:** keeps its place in the order, drawn as a quiet placeholder; a banner explains and
  offers *Remove Missing*; each photo can be replaced (from Relive or the photo library). Saving
  is disabled until none are missing.
- **Story:** a reopened or user-corrected story is never redesigned behind the user's back. Its
  missing photos are shown as missing, the banner offers *Remove Missing*
  (`StoryDesign.removingPhotos`: empty cards go, the opening falls back to the strongest
  remaining photo, facts are recomputed) and *Edit Card → Replace*. Only Relive's own untouched
  first design may be redesigned without the photo, as before.
- **Book:** missing photos drop out of the layout (v0.3 behaviour) with a banner.
- **Cards and Continue Editing** show placeholders and say *"1 photo is missing"*. Delete and
  edit always work.

## Migration

- v0.4 adds two SwiftData models (`StoredFavorite`, `StoredCreation`) and changes none, so a
  v0.3.1 store migrates automatically (lightweight). Nobody needs to reinstall.
- `PersistenceMigrationTests.testV031StoreOpensWithV04Schema` writes a v0.3.1-shaped store on disk
  (6 models), opens it with the v0.4 schema (8 models) and checks the profile, memories, notes,
  the exclusion list and a Film book come through unchanged, then stores favorites and creations
  and applies the Start Over rules.
- Existing books open as before; they gain snapshots the next time they are saved.
- `SavedCreation.version` (1) and `MemoryBook.version` leave room for later changes; unreadable
  records are logged and skipped rather than crashing.

## Export exclusion

Every image Relive saves to Photos goes through `ExportController.save`, which records the new
asset identifiers with the store (`recordCreatedAssets`) *before* anything else — whatever the
creation was made from: memories, the photo library, favorites, a reopened creation, or a draft.
Import and sync skip those identifiers. The saver is injectable (`CreationSaving`), so hosted
tests export a **reopened draft** (twice) and a **favorites story** through the real controller
and check the identifiers are recorded, persisted, and not imported when they become visible.

## Accessibility and performance

- VoiceOver: hearts announce *Selected / Not selected*; cards read *title, kind · photos ·
  period, N photos missing, Favorite*; drafts read *"Draft story, …, Edited 12 minutes ago"* with
  *Delete Draft* as an action; delete buttons are destructive and confirmed; Favorites segments
  and My Creations filters are standard segmented pickers.
- 44 pt targets for hearts, Save, More and section links; Dynamic Type everywhere outside the
  fixed-size artwork; Reduce Motion respected (no animation is required to understand a change).
- Previews draw the creation's canvas with 360 px thumbnails through the shared image cache
  (`PhotoImageLoader`: at most 400 images and 160 MB, cleared under memory pressure; keys are
  identifier + size, so they are deterministic). Grids are lazy.

## Limitations

- Not physically verified (see the README). Debounce timing, background flushing and the feel of
  the heart need a device check.
- Share and Save from My Creations happen inside the reopened editor (one tap away), not from the
  card's menu.
- Monthly Recaps and Our Year are not kept in My Creations (they are always made fresh from the
  story); Trend creations are not kept either.
- Favorites are per device; there is no sync (by design: no accounts or cloud).
- The autosave write runs on the main actor (small JSON, no images).
