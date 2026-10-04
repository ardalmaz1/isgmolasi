# Memory Book — Relive v0.3 (updated in v0.3.1)

A Memory Book turns a moment, a trip, a month, a year or a hand-picked set of photos into a book
the couple can read on their iPhone, page by page. Relive builds the whole book automatically
from what is really in the library and the story: real dates, real places, the names of moments
and trips, and the couple's own notes. It never invents milestones, feelings, "favourite"
claims or captions.

Code: `Packages/ReliveCore/Sources/ReliveCore/Book/` (model, builder, layout — Foundation only,
tested on Linux) and `Relive/Book/` (canvas, reader, editor, period picker — SwiftUI).

## 1. Book model

The structure is deliberately small: **Book → Section → Page → Slot**.

- `MemoryBook` (Codable, the only thing that is saved) is the book's *definition*:
  - `id`, `version` (format version, currently 1), `createdAt`, `updatedAt`
  - `source`: the `CreationSource` it was made from (see §2), kept so the book can be refreshed
  - `style`: Classic, Editorial or Film (§4)
  - `photoIDs`: the photos in reading order, as PhotoKit local identifiers. Never pixels.
  - `coverAssetID`: the user's cover choice, or nil for "the best photo"
  - `note`: the couple's own words for the first page, or nil
  - `includesMomentNotes`: whether notes written on moments are printed in the book
  - `photoLibraryAssets` (v0.3.1): metadata — date, location, size, never pixels — of photos
    chosen straight from the photo library, so the book can describe them after a restart.
    Books saved before v0.3.1 decode with an empty list.
- A **section** is a run of consecutive photos from one moment; in a one-moment book, each day
  is a section; photos from outside the story form sections by their own capture day. Sections
  carry only facts taken from their own photos: the moment's real name, the photos' date span
  (only when every photo has a date), place, note, and trip. A photo never inherits a
  neighbour's name or date (v0.3.1 fix).
- `BookPage` is one page: a kind (`cover`, `bookNote`, `momentNote`, `tripTitle`, `opener`,
  `photos`, `closing`), a photo template (`fullBleed`, `single`, `pair`, `feature`, `trio`,
  `quad`), photo slots with frames, the factual title/date/place, running head, the dates of
  *that page's own photos*, and folio.
- `BookLayout` is the paginated result: pages, the facts for the whole book, the photos that
  were used, the photos that are missing, and `spreads` (pages paired as a printed book would
  pair them — cover alone, then left/right). Spreads are computed but not yet shown; they exist
  for the PDF and print paths (§9, §10).

Pages are never stored. The layout is computed from the definition every time the book is
opened, so deleted photos drop out, notes edited elsewhere appear, and a better layout in a
later version improves old books without a migration.

`MemoryBookBuilder` makes a book from a source and supports the light edits:
`removePhoto`, `movePhoto(_:by:)`, `replacePhoto(_:with:)`, `setPhotos` (keeps the order of
photos that stay, appends new ones), `setCover`, `setNote`, and `refreshed(_:)` (rebuild from the
source after the library changed, keeping style, note and — when still present — cover).
Every edit enforces the limits: at least 6 photos, at most 40 (v0.3.1; was 4–60), no
duplicates.

## 2. Source types

| Source | Where it starts | Photos |
| --- | --- | --- |
| A Moment | Create → Start a Book → A Moment | The moment's usable photos, in time order |
| A Trip | … → A Trip (only shown when the story has trips) | Every moment of the trip chapter, interleaved fairly, in time order |
| A Month | … → A Month (months with photos) | The month's moments, like Monthly Recap |
| A Year | … → A Year (years with photos) | The year's moments, like Our Year |
| Favorites | … → Favorites (when at least 6 favorites exist) | Memories marked as favorites in Photos, in time order |
| Photos I Choose | … → Photos I Choose → From Relive | Exactly the chosen memories, in the order chosen |
| Photo Library | … → Photos I Choose → From Photo Library, or Our Year → Build from Photo Library | Any photos on the iPhone, with their own metadata; not added to the story |

All sources go through `CreationLibrary`, the same rules as v0.2 creation: hidden moments,
hidden photos and photos no longer in the library are never used. The trip and period pickers
list only what exists and show each row's photo count; rows below the minimum (6 photos) are
disabled with "Needs at least 6 photos". If a source still comes up short, the flow shows the
existing "Not enough photos" screen with a Choose Photos action — never an empty book.

Books are capped at 40 photos. A bigger source is reduced with the same selection v0.2 creation
uses for that source (the strongest photos, spread across the source's moments), then put back
in time order. Chosen photos keep the order they were chosen in.

## 3. Auto-layout

`BookLayoutEngine` is deterministic: the same definition and library always give the same
pages (tested). Order of the book:

1. **Cover** — the user's cover, or the best photo by the existing quality ranking; the factual
   title derived from the book's photos (see CREATION.md, "metadata follows the photo"): a
   moment or trip name, a shared place, "September Together" only when every photo is from
   September, "Our 2026" for several months of one year; for several years or unknown dates a
   neutral "Our Memories" with the real date range.
2. **Note page** — only if the couple wrote one.
3. For each section (when the book has more than one):
   - a **trip title page** the first time a trip appears inside a longer book (month, year or
     chosen photos), never for a book that *is* the trip;
   - an **opener** — the section's first photo with its real name, date and place, only when
     there is something true to say. A generic name already used earlier in the book ("September
     Evening" twice) gives way to the section's own date;
   - the moment's **note page**, if the couple wrote one and moment notes are included.
   A one-section book prints its moment note once, after the cover.
4. **Photo pages**, split by the photos themselves (v0.3.1; no fixed rhythm): in a section of
   five or more, its strongest photo gets a page of its own (placed where it leaves no lone photo
   beside it); two landscapes share a page; portraits gather in fours, or threes when the page
   before was a four; no single photo is left over when another split avoids it. Templates:
   - 1 photo: portrait/square → `fullBleed`; landscape → `single`, shown whole (no crop).
   - 2 photos of one orientation: `pair`, justified so both keep their shape.
   - a portrait and a landscape: `feature` — the portrait large, the landscape smaller beside
     it, aligned to the portrait's foot, with deliberate white space; neither cropped.
   - 3 photos: `trio`, an editorial arrangement chosen for the photos' orientations.
   - 4 photos: `quad`, a justified grid of up to 2 columns.
   Multi-photo templates reuse the v0.2 crop-minimising layout engine. Each page's footer shows
   the dates of its own photos (a range when they span days).
5. **Closing page** — the book's title, dates and place again. No invented sign-off.

Pagination does not depend on the style: changing the style changes only the geometry, never
which photo is on which page (tested). Chronology is preserved within and across sections
(tested for every source).

## 4. Styles

Styles change typography, spacing, paper and image treatment — never content.

| | Classic | Editorial | Film |
| --- | --- | --- | --- |
| Paper | Warm cream | Off-white | Near-black |
| Type | Serif titles and text | Serif titles, sans text | Monospaced, upper-case, amber |
| Margin / gutter (of page width) | 10% / 2.4% | 6.5% / 1.2% | 9% / 3% |
| One portrait photo | Inset on the paper | Edge to edge | Inset on the dark paper |

The metrics live in `BookStyleMetrics` (core, testable); the look in `BookTheme` (app). Pages
always render in their own paper colours (§8, Dark Mode).

## 5. Persistence

- SwiftData model `StoredMemoryBook { bookID, payload: Data, updatedAt }`, where `payload` is the
  JSON-encoded `MemoryBook`. A book is a few kilobytes: identifiers, a style, a note.
- **No photo data is stored** — not full-resolution, not thumbnails. Pages are drawn from
  PhotoKit every time.
- The model is additive: v0.2 stores open with the v0.3 schema by SwiftData's automatic
  lightweight migration. v0.3.1 adds no schema change: Photo Library metadata lives inside the
  book's JSON definition, which decodes older books unchanged. `PersistenceMigrationTests` writes a v0.2-shaped store to disk, opens it
  with the v0.3 schema and checks that the profile, surprise, assets, moment notes/hidden flags
  and created-asset list all survive, and that books can then be saved, updated and deleted.
- `StoryStore.books` is the list, newest change first. **v0.4: Start Over keeps books** (it
  used to delete them with the story). So a kept book can still describe and lay out its photos
  when they aren't in the new story, `saveBook` now snapshots the metadata of *every* photo in
  `photoLibraryAssets` (`MemoryBook.captureSnapshots`; no pixels, no analysis). Memories in the
  story always win over snapshots. The list of photos Relive created stays too, as before.
- v0.4: books appear in **My Creations** and **Your Creations** next to collages and stories
  (`KeptItem`; the book model and storage are unchanged), can be favorited from the reader's
  heart, and are deleted from Relive with confirmation (never from Photos). A v0.3.1 store opens
  with the v0.4 schema unchanged (`testV031StoreOpensWithV04Schema`).
- Missing photos: a photo deleted from the library, hidden in Relive, or no longer shared with
  Relive (limited access) is left out of the layout. Photo Library photos used by books are
  re-checked for availability like memories. The reader says how many were left out and
  offers Edit Book. If fewer than 4 photos remain, the book still opens with what is there.

## 6. Rendering

- `BookPageCanvas` draws one page at the 1080 × 1350 design size (4:5), the same canvas system as
  v0.2 creation: the reader shows it scaled down (`ScaledCanvas`), Save/Share Page renders it at
  2× — **2160 × 2700 px** — with photos loaded at the pixel size of their frame.
- The reader is a horizontal paging scroll view of pages (`LazyHStack`, `.paging`), the page
  number underneath, Share Page and Save Page below. Page turns are the system paging scroll:
  no simulated 3D page curl, nothing that needs disabling for Reduce Motion.
- **Save Page / Share Page** use the v0.2 `ExportController`: one export at a time, clear status
  text, and Save is disabled after a successful save until the page or the book changes, so the
  same page isn't saved twice by accident. Saved pages are recorded as created by Relive and
  never come back as memories.

## 7. Performance

- Pages are lazy: only pages near the visible one exist. Each page loads its photos when it
  appears, at a size derived from its frame (400–1600 px long side), and releases them when it
  disappears — a 60-photo book holds a handful of preview images at a time.
- Full-resolution images are requested only on export, one page at a time, at the frame's
  pixel size, without caching.
- The shared preview cache (`PhotoImageLoader`) now has a byte budget (160 MB, cost = pixels × 4)
  in addition to its count limit, and is emptied on memory warnings as before.
- Layout is pure computation in ReliveCore with no image access. The "large book" test samples
  a 360-photo year down to 40, lays it out in under a second (Linux CI), and checks every photo
  is placed exactly once.

## 8. Accessibility

- Every page is one VoiceOver element with a description built from its facts, e.g.
  "Cover. Kaş. 12 – 15 Jun 2025. 1 photo" or "Page 5 of 23. 3 photos. Kekova". Photo pages say
  how many photos; note pages read the note; the last page is "Last page".
- Page label, Share Page and Save Page are standard controls; the reader supports the swipe
  gesture and the VoiceOver scroll actions.
- The editor: style choices are buttons with selected state; each photo in the strip has
  accessibility actions (Move Earlier, Move Later, Replace, Remove, Use as Cover) so nothing
  depends on drag and drop or context menus.
- Dynamic Type applies to all app chrome. Page canvases are fixed-size artwork (like a printed
  page) and are scaled as a whole; their text is available through the page description.
- **Dark Mode**: the desk behind the pages darkens, the pages keep their paper (cream, white or
  black for Film) — a book doesn't change colour at night.
- **Reduce Motion**: page turns are plain scrolling; no extra animation is added.

## 9. Future PDF path (not implemented)

v0.3 deliberately does not export PDFs. The path when it's time:

1. Render each `BookPage` with `BookPageCanvas` into a PDF context (`ImageRenderer.render` gives
   a `CGContext` drawing callback; vector text, photos as embedded JPEG at print resolution).
2. Use `BookLayout.spreads` to order pages and add blank pages so spreads pair correctly.
3. Load photos at the print size of each frame (frame size in points × target DPI), one page at
   a time, writing pages incrementally to keep memory flat.
4. Write to a temporary file and hand it to the share sheet; never keep it.

Nothing in the model needs to change for this: the definition already holds everything a page
needs, and the canvas is already resolution-independent.

## 10. Future physical-book path (not implemented)

Digital → PDF → Physical. A printed book would add, on top of the PDF:

- a print profile per product (trim size, bleed, safe area, spine width by page count), which
  maps the 4:5 design page into the product's trim with bleed;
- a minimum resolution check per photo frame, with a clear warning before ordering;
- a cover spread (front, spine, back) built from the cover page and the closing page;
- a provider integration for upload and ordering, with explicit consent per order, since that
  is the first time photos would leave the iPhone.

There is no ordering, pricing or upload in v0.3.
