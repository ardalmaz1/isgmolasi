# Running a Prototype 0.1 validation session

Prototype 0.1 answers one question: **does an automatically organized story make people feel
"I forgot about this" or "we've made beautiful memories together"?**

## Setup

1. Install a Debug or TestFlight build on the participant's own iPhone (their real library is
   the whole point).
2. Let them go through onboarding without guidance. Note whether any screen makes them hesitate —
   especially the photo access step.
3. Suggest choosing 50–500 photos of the two of them; don't curate for them.

## What to watch

| Signal | Where it comes from |
|--------|--------------------|
| "Did you find something that made you smile?" — Yes / Not yet | Asked once in the app after ≥ 2 moments have been opened. Stored locally and logged as `validation_smile_yes` / `validation_smile_no`. |
| Moments opened, notes written, memories shared, memories hidden | Analytics events `moment_opened`, `note_added`, `memory_shared`, `memory_hidden`. |
| Processing time and story shape | `memory_processing_completed` (assets, moments, chapters, duplicates, analysis failures, seconds). |
| Spontaneous reactions | Observation — the words people say while scrolling the timeline matter more than any number. |

Things worth writing down during a session:

- Which moment they opened first, and why.
- Any moment that felt wrongly grouped (two separate evenings merged, one trip split).
- Any cover photo they'd have chosen differently (they can fix it with **Use as Cover**).
- Any title that felt off. Titles should read as facts, never as judgements.
- Whether they hid anything — and don't ask why.

## Reading the events

Events are written to the device's unified log only (no network). With the iPhone connected to a
Mac, open **Console.app**, select the device, and filter by subsystem `app.relive`, category
`analytics`. Events never contain names, notes or places.

## Resetting between sessions

**Us → Start Over** deletes Relive's data (story, notes, settings) without touching the photo
library. Photo access itself is managed in iOS Settings → Relive → Photos.
