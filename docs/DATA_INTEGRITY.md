# Data integrity — capture dates, months, years and places

> A beautifully designed wrong date is worse than showing no date.

This pass followed a physical-iPhone report: a 97-memory library the tester believes spans
April 2025 – October 2026 appeared as 93 memories in September 2026 (5 moments) and 4 in
October 2026. "Our 2026" was the only year, and a Memory Book from mixed photos read
"September Together · September 10 – 27, 2026".

## 1. Root-cause investigation

The metadata pipeline, traced end to end:

```
PHAsset ──(PhotoKitLibraryService.memoryAsset)──► MemoryAsset.creationDate / location
   │                                                   │  the only place a date is created
   ▼                                                   ▼
StoryStore.merge ──► SwiftData (JSON, exact Date) ──► reload
   ▼
MemoryEngine: MetadataProcessor.normalized → clustering → moments (start/end = their photos)
   ▼
Story timeline · Create pickers (moment groups, real start–end) · Monthly Recap · Our Year
Memory Book · Story Maker · Collage (CreationLibrary.facts — from the photos themselves)
```

What the code does and doesn't do, verified by reading every date use and by tests:

| Suspect | Finding |
|---|---|
| `Date()` / import / processing date as a fallback | None. `MemoryAsset` is built in exactly one place, from `PHAsset.creationDate`. |
| Test or default dates leaking | None in production code. |
| Decoding / migration defaults | `creationDate` is optional and decodes as itself; JSON round-trips `Date` exactly (tested on disk). |
| One photo's date copied to others / moment date for every photo | Not for stored metadata. Three *display* paths substituted a moment's date for a photo without one (Found for You, Story Maker groups, the store's Found-for-You restore) — removed. |
| Time zones / `startOfDay` / year normalization | Month and year are always taken in the device calendar from each photo's own date. The 04:00 "logical day" only shapes moments, never months or years. |
| Clustering merging distant months | Impossible: any gap ≥ 8 h always splits (tested with the same place and no photos in between). |
| Grouping | **Defect:** Monthly Recap and Our Year grouped photos by their *moment's* start date. A moment that runs past midnight put January photos in December and in the previous year, and "the first memory of the year" was the first *moment's* start. |
| Stale persisted metadata | **Defect:** stored metadata was a snapshot from import and was never refreshed for full-access users, so a date corrected in Photos (or synced later) never reached Relive. |
| Duplicate copies | A re-saved copy is attached to its original's moment by design; it is now never placed in a month or year on its own (it's the same memory). |

The acceptance library (below) run through the real engine with correct source dates already
produced the right months, years and creation titles before this pass — except across
midnight, which the new grouping fixes. A mixed Memory Book's date range is computed directly
from the photos' stored dates, so the device's "September 10 – 27, 2026" means those photos
were **stored** with September 2026 dates, and stored dates are exactly what PhotoKit reported
at import. The most likely explanation is that PhotoKit itself reports September 2026 for those
items — typical of images saved from messaging apps or the web, whose library date is the day
they were saved, not taken.

That can only be confirmed on the device, so development builds now log it (§6). If
`embedded_date_check` reports `differs > 0`, the photo library's own dates disagree with the
capture date inside the files. Relive follows the canonical rule below (PhotoKit's date)
and does not silently switch sources; whether to prefer the embedded date for such photos is a
product decision (see Limitations).

**Real-device follow-up.** On an iPhone 13 whose library has normal historical dates, the
behaviour did not recur, and every surface dated photos from 2017 to 2026 correctly. This is
strong real-device evidence that the issue is specific to the library or device metadata, not
proven. The transferred-library investigation is still open, and its logs need a Debug build
(TestFlight builds don't produce them). See [REAL_DEVICE_VALIDATION.md](REAL_DEVICE_VALIDATION.md).

## 2. The canonical rule

- `PHAsset.creationDate` is the capture date, read at import and kept in step with the library
  by the metadata repair. `MetadataProcessor.normalized` is the only trust rule: a date more
  than two days in the future or an invalid coordinate becomes **unknown**. Nothing is ever
  replaced with "now", the import date, the processing date, another photo's date, the start of
  a year, the relationship start date, or a default.
- Unknown stays unknown: an undated photo has no month, no year, no "N years ago", and appears
  only in the undated moment. A photo without a location never borrows a place.
- Every feature derives dates from that value: no feature reconstructs its own.

## 3. One grouping: `TemporalIndex`

`TemporalIndex` (ReliveCore) answers "which month and year does this memory belong to?" from
each memory's **own** capture date in the library calendar. Memories are the members of visible
moments that can still be shown, except duplicate copies — the same rule as the statistics.

- **Monthly Recap**: months are the months memories were taken in; a recap holds exactly those
  memories. Moments that cross into the month are narrowed to their photos from that month,
  dated by those photos.
- **Our Year**: years are the years memories were taken in; "Our 2025" holds only 2025 memories,
  sections are per month by photo date, and **the first memory of the year is literally the
  earliest memory taken that year** (`YearInReview.firstMemory`), named by its moment and dated
  by the photo.
- **Month and year creation sources** (collage, story, book from a month or year) use the same
  recaps, so they contain only photos taken in that period.
- **Creations from any photos** (`CreationLibrary.facts`) were already photo-based: one month →
  "September Together"; months of one year → "Our 2026" only when from several months; several
  years → no period title (a book's cover then reads "Our Memories · 2025 – 2026"). Book page
  footers are dated by that page's photos.

## 4. Repairing existing installs

`StoryStore.repairMetadata()` runs every time the app becomes active (not during onboarding):

1. One batched PhotoKit metadata fetch for every chosen memory (no images).
2. `MetadataRepair` (ReliveCore) compares each stored memory with the library's normalized
   metadata — date, location, kind, size, duration, traits, Photos favorite flag — and replaces
   what differs, keeping cached analysis.
3. Memories the library doesn't return (deleted, access removed) are left as stored; nothing is
   ever added, removed or duplicated.
4. If dates or locations changed, the story is rebuilt (cached analysis makes this fast) and
   `MomentReconciler` keeps moment identities, so notes, hidden moments, covers and favorites
   stay attached. Recaps, years and creation inputs are computed live from the result.
5. Running it again changes nothing (idempotent) and rebuilds nothing.

No reinstall or Start Over is needed. If PhotoKit reports the same dates Relive stored, the
repair changes nothing — Relive is then showing exactly what the library says (§1).

## 5. Acceptance scenario (tests)

| Month | Photos |
|---|---|
| April 12, 2025 | 8 |
| May 3, 2025 | 5 |
| September 10, 2025 | 12 |
| January 5, 2026 | 6 |
| September 18, 2026 | 9 |
| October 4, 2026 | 4 |

Exactly six month buckets, 44 memories, 25 in 2025 and 19 in 2026; first memory of 2025 is
April 12, of 2026 January 5; no 2025 photo in September 2026; a story or book of April 2025 +
September 2026 photos claims no single month or year. Undated photos stay unknown. Midnight
cases (New Year's Eve into January 1; 23:59 on the last of a month) land in their own month and
year in a UTC+3 calendar, which a careless UTC conversion would get wrong.

Tests: `DataIntegrityTests`, `MixedPeriodCreationTests`, `MetadataRepairTests` (ReliveCore,
Linux); `CaptureDateIntegrityTests`, `PersistenceAcrossRelaunchTests`, `CollageReorderTests`
(hosted, with an on-disk SwiftData store); `IntegrityUITests` (simulator).

## 6. Reading the device log

Development builds log under subsystem `app.relive`, category `metadata` (Console.app or the
Xcode console; filter on `metadata`). Identifiers are shortened; no contents, names or
coordinates are logged. The format (values here are illustrative, not from a real run):

```
asset_metadata_imported id=8F2C61A0 sourceDate=2025-04-12T14:03:11+03:00 persistedDate=2025-04-12T14:03:11+03:00 sourceLocationPresent=true
asset_metadata_repaired id=8F2C61A0 storedDate=… libraryDate=… date=true location=false other=false
metadata_audit assets=97 validDates=97 unknownDates=0 located=40 years=[2025:52,2026:45] months=[2025-04:8,…] repaired=0
asset_embedded_date_differs id=… libraryDate=2026-09-10T20:41:00+03:00 storedDate=… embeddedDate=2025-04-12T14:03:11+03:00 source=library
embedded_date_check checked=97 matches=4 differs=93 noEmbeddedDate=0 unreadable=0
creations_loaded records=3 drafts=2 saved=1
```

- `sourceDate` ≠ `persistedDate` would mean Relive changed a date (it shouldn't, except a
  future date becoming unknown).
- `metadata_audit` shows the years and months Relive will display.
- `embedded_date_check … differs=N` means the photo library's date disagrees with the date
  inside N image files.

## Limitations

- When PhotoKit's date and the file's embedded capture date disagree, Relive uses PhotoKit's
  date (the canonical rule) and logs the disagreement in development builds. Preferring the
  embedded date would need a product decision: it is closer to "when it was taken" for saved
  copies, but it would override date corrections made in Photos and requires reading each file.
- Duplicate copies stay attached to their original's moment (shown under "similar photos") and
  are not counted in any month or year.
- The repair runs on each activation; for very large selections the batched fetch is the cost
  (metadata only).
