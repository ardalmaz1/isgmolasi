# Real-device validation — iPhone 13, TestFlight 0.4 (1)

A manual validation pass on a physical iPhone whose photo library has normal historical dates.
Its main purpose was to check the date pipeline after the earlier report from another iPhone,
where most 2025 photos appeared as September 2026 (see [DATA_INTEGRITY.md](DATA_INTEGRITY.md)).

## Device and build

| | |
|---|---|
| Device | iPhone 13 |
| Install | TestFlight |
| Version / build | 0.4 (1) |
| Source commit | Not recorded. 0.4 (1) was not bumped during the data-integrity pass, so the build number alone doesn't say whether that pass was included (see Notes). |
| Tested by | The product owner, by hand. Not automated. |

## Library sample

- 92 photos processed: 30 moments, 7 places.
- Several years and months, with visible examples from 2017, 2023, 2025 and 2026.
- Processing finished with no hang.

## Results

| Area | Result | Observed |
|---|---|---|
| Story timeline | PASS | Dates didn't collapse into one month or year. 2017 appeared as its own year, and distant periods stayed separate. The "2025 photos became September 2026" behaviour did not recur. |
| Monthly Recap | PASS | June, July and August 2025 appeared as separate months, as did August, September and October 2026. August 2025 had 27 memories in 5 moments; August 2026 had 14 memories in 2 moments. An August 2025 moment was dated August 1, 2025, and a photo in it showed August 1, 2025 at 21:23. No cross-year collapse. |
| Memory Book: one year, several months | PASS | 7 photos from August–October 2026. The cover read "Our 2026 · August – October 2026", with no false single-month title. Pages carried their own dates ("October Morning — October 8", "Moments from August — August 16–29", and other August pages with their own ranges). |
| Memory Book: mixed years | PASS | Photos from 2025 and 2026. The cover read "Our Memories · 2025 – 2026". Pages from 2025 had their own dates (e.g. June 9, May 1), and pages from 2026 had theirs (August ranges). No "Our 2026" or "September Together". |
| Story Maker: one period | PASS | An August 2025 selection showed factual Bergama / August 2025 content. |
| Story Maker: mixed periods | PASS | Content from 2023 to 2026. The opening card read "Our Memories · 2023–2026". The Bergama card was dated 14 August 2023 and the Fethiye card 7 August 2026. The closing card read 2023–2026. No fake single-month title, and no date borrowed across years. |
| Collage editor | PASS | Edit, replace and remove all work. |
| Collage drag reorder | PASS, needs polish | It works, but the gesture doesn't feel fully polished. A UX polish item, not a correctness issue. |
| Favorites | PASS | An item was added, and it was still a favorite after the app was fully closed and reopened. |
| Draft persistence | PASS | A collage was edited, the app was fully closed and reopened, and the edit was still there. The tester didn't see an explicit "Continue Editing" step, but the draft restored correctly (see Notes). |
| Export | PASS | The saved creation appeared in Photos as an image and looked correct. |
| Performance / stability | PASS | No meaningful stutter, freeze, processing hang or crash during normal use. |

## Conclusion on the earlier "September 2026" report

On this iPhone 13, Relive grouped, titled and dated photos from 2017 to 2026 correctly in every
surface tested. The earlier behaviour, where most 2025 photos appeared as September 2026, was not
reproduced.

This is **strong real-device evidence that the issue is specific to the library or device
metadata**, not a general bug in Relive's date pipeline. It fits the explanation in
[DATA_INTEGRITY.md](DATA_INTEGRITY.md) §1–2: the other iPhone's library had been transferred,
and its photos probably carry the transfer or save date as their Photos-library date. This is
not proven. Only an inspection of that library's own metadata can confirm it (below).

The canonical date policy is unchanged: PhotoKit's `creationDate` is the capture date unless the
product explicitly decides otherwise.

## Remaining items

1. **Transferred-library iPhone: metadata investigation still open.** Compare, for the affected
   photos:
   - PhotoKit's `creationDate`
   - the embedded EXIF/original capture date
   - whether the transfer gave them their transfer/save date

   The logs for this (`asset_metadata_imported`, `metadata_audit`, `embedded_date_check`) are
   **development-build only**. A TestFlight (Release) build doesn't produce them, so this needs a
   Debug build run from Xcode on that iPhone, with the console filtered on `metadata`.
2. **Collage drag reorder** works but could feel more polished (UX polish).
3. **Some Editorial Story Maker cards look sparse** (visual polish, not a data-integrity issue).
4. **Date policy:** no change needed. Keep PhotoKit `creationDate` unless the product decides
   otherwise.

## Notes

- **Build provenance.** The marketing version and build number stayed 0.4 (1) through the
  data-integrity pass, so it's unrecorded whether this TestFlight build included that pass (the
  `TemporalIndex` grouping, metadata repair and draft flushing). Either way, the date results
  above held on this library. Bumping the build number on every TestFlight upload, and recording
  the commit here, would make future reports traceable.
- **Drafts.** "Continue Editing" is a card at the top of the Create tab that appears only while a
  draft exists. It isn't a prompt shown at launch. Drafts can also be reopened from Drafts or My
  Creations. The tester didn't record which path reopened the draft. Only the outcome (the edit
  was preserved) was checked.
- Not covered in this pass: VoiceOver, Dynamic Type extremes, a library of several thousand
  photos, limited photo access, iCloud-only originals, and the floating tab bar on iOS 26.
