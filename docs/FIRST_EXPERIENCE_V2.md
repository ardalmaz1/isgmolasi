# First Experience V2

Relive used to promise to "find your story" and then ask for 50–500 hand-picked photos. First
Experience V2 removes that contradiction. The couple gives permission, Relive suggests
**possible moments** from their library, they keep the ones that are theirs, and Relive makes
something from them.

This phase only changes activation and onboarding. It reuses the existing engines: Memory Engine
clustering and trips, Made for You, Recap, Movie and the on-device analyser. It is not new
intelligence.

## Flow

```
Welcome ─ "Your relationship, told through the photos you already have."
          "On this iPhone. No account. Nothing posted anywhere."          [Find Our Story]
Partner ─ "Who's your favorite person?"
Start   ─ "When did your story begin?"        [Continue]  [I'm not sure — skip]
Begin   ─ "How would you like to begin?"
            ▸ Let Relive find them   — "Relive looks for possible moments on this iPhone. You decide what to keep."
            ▸ Choose memories myself — "Start with a few photos. You can always add more."

Discovery path                                  Manual path
 "Relive looks. You decide." (what it does)      "Choose a few memories of the two of you."
 → Apple's Photos permission                     "About 20 is plenty to get started. Add more anytime."
 → "Looking for possible moments…" [Cancel]       → Apple's limited picker / photo picker
 → "Possible moments" — Keep / Not ours per      (5 photos is enough to begin;
   moment, tap to see its photos                  5–19 is never treated as a mistake)
 → Continue with N moments
                  ↘                        ↙
 Processing — real stages, plus facts once known: "12 moments found", "1 trip found", "3 places found"
 First Discovery — "We found something for you." + the strongest real result
                   [Watch Your Movie | See Your Recap | Open Your Book | Open This Memory]  [See Our Story]
 Our Story
```

`AppModel.OnboardingStep` is not persisted. A relaunch resumes from what is known:

- no partner name: Welcome;
- no start date and not skipped: Start date;
- no photos yet: How to begin;
- no story yet: Processing;
- otherwise: First Discovery.

Existing couples, who have `storyRevealedAt` set, never see onboarding again. Their story,
favorites, hidden memories, notes, creations, drafts, Premium state and Made for You history are
untouched. The only change they see is the factual pre-start rule described below.

## The two paths

| | Let Relive find them | Choose memories myself |
|---|---|---|
| Permission | Full Photos access (explained first; optional) | Limited access (Apple's picker), or the photo picker under full access |
| What Relive reads | Metadata of the newest 25,000 assets; ≤ 144 small local thumbnails | Only the photos chosen |
| User work | One decision per possible moment (≈10–36 taps) | One tap per photo (about 20 suggested; 5 to begin) |
| What enters the story | Only moments kept | Only photos chosen |

- **Limited access chosen in Apple's dialog during discovery:** Relive syncs the couple's
  selection and carries on along the manual path. If 5 or more photos were chosen, it goes
  straight to processing.
- **Full access is never required.** The manual path is a complete Relive experience.

## Discovery: privacy

What the couple is told before Apple's dialog:

- dates and places group photos into possible moments;
- Relive may count faces in a few photos but doesn't know who anyone is;
- this happens on the iPhone and photos aren't uploaded;
- they choose which moments belong, and only those are kept;
- there's no feed, no account and nothing is posted.

What actually happens:

| | |
|---|---|
| **Seen** | PhotoKit metadata: creation date, location, media type and subtypes, pixel size, favorite, duration. User library only: hidden assets and shared-album items are left out (screenshots are dropped by subtype; screen recordings are not specifically detected — the couple can mark such a moment Not ours). Bursts come as their one representative (PhotoKit's default). |
| **Analyzed** | At most 48 shortlisted moments × 3 representative thumbnails = **144** small local thumbnails (512 px), with the existing Vision analyzer. Discovery keeps only a **face count bucket** (0 / 1 / 2+), the utility flag and an aesthetic score. |
| **Originals** | Never loaded. |
| **iCloud** | Discovery requests images with `isNetworkAccessAllowed = false`, for both analysis and the possible-moment covers. Nothing is downloaded during discovery. If no local version exists, the moment is ranked from metadata alone and its cover is left as a placeholder. |
| **Coordinates** | Read locally for grouping. Only the **kept** moments go through processing, where (as before) one coordinate per moment may be sent to Apple's geocoder for a place name. |
| **Leaves the phone** | During discovery: nothing. After it: the existing geocoder lookups for kept moments. Photos kept only in iCloud may later be downloaded from the couple's own iCloud **to display them** in the story. |
| **Identity** | No face recognition, no identity matching, no face embeddings, no face geometry persisted. Apple Photos' People data isn't available to apps, and Vision offers detection only. Relive never says "this is you" or "this is the two of you". |

## Candidate algorithm (`ReliveCore/Discovery/MemoryDiscovery.swift`)

1. **Consider** the newest `maximumLibraryAssets = 25_000` dated assets (a newest-first fetch
   with a fetch limit).
2. **Filter:**
   - undated assets;
   - anything before the relationship start, when one was given;
   - screenshots, and images under 320 px on the long side (stickers, saved thumbnails);
   - anything dated more than a day in the future.
3. **Group** with the story engine's own `MomentClusterer` (moments) and `ChapterBuilder`
   (trips: away from home, at least 2 moments over at least 2 days). A trip is one possible
   moment.
4. **Rank by metadata only:**
   - log2 of the size;
   - +2.5 for a trip;
   - up to +1.5 for days spanned;
   - up to +2 for favorites;
   - +0.3 for having a location;
   - +0.2 for videos.

   A possible moment needs at least 3 photos.
5. **Shortlist** 48, with at most 12 per calendar year so one year doesn't dominate. Pick
   3 representatives per moment, spread in time, favorites first.
6. **Look at the representatives** (bounded, local thumbnails only):
   - 2+ faces: +2;
   - 1 face: +0.8;
   - 0 faces: −0.5;
   - unknown (no local thumbnail): ±0;
   - plus (mean aesthetics − 0.5), minus the share that are utility images.

   A moment whose analyzed representatives are *all* utility images (documents, receipts) is
   dropped.
7. **Show** up to 36, newest first, as "Possible moments". The wording never states certainty.
8. **Import** only kept moments, up to 1,000 photos. If the kept moments hold more than that,
   each contributes in proportion to its size, spread evenly across its time, and never zero.
   Nothing from a moment the couple didn't keep is imported.

### Bounds (final values)

| | |
|---|---|
| Metadata considered | 25,000 newest assets |
| Shortlist | 48 moments |
| Thumbnails analyzed | ≤ 144 (3 per shortlisted moment), 3 at a time |
| Possible moments shown | ≤ 36 (≤ 12 per year) |
| First story import | ≤ 1,000 photos |

### Performance

- **Linux CI container, core metadata stage only.** A synthetic library of 50,000 assets
  considered the newest 25,000. That made 4,998 moments, shortlisted 48, with 144
  representatives, in **0.29 s**. This is *not* a device measurement and doesn't include
  PhotoKit enumeration or Vision.
- **CI simulator, iPhone 16, the 112-asset sample library** (CI run 38953983519; *not* a device
  measurement):
  - `discovery_plan library=112 considered=112 eligible=112 moments=21 trips=1 shortlisted=9
    representatives=27`;
  - `discovery_timing scan=189ms shortlist=4ms thumbnails=15317ms analysed=27 unavailable=0
    candidates=9`;
  - as seen by the UI test, possible moments appeared about **15 s** after Continue (20 s on
    iPhone SE);
  - the couple kept 8 moments, and `discovery_import kept=8 imported=97`;
  - the First Discovery appeared about **37 s** after "Continue with 8 moments" (44 s on iPhone SE).
  - Thumbnail analysis dominates discovery. It is bounded at 144 thumbnails whatever the library
    size.
- **Not measured:** PhotoKit enumeration of a real 20k–50k library, Vision speed on a device,
  battery and heat.

## Temporary data

| Data | Where it lives | When it's discarded |
|---|---|---|
| Possible moments (identifiers, dates, counts, scores, face buckets) | Memory only, in `DiscoveryModel` (owned by the onboarding view) | On Continue, on cancel, on "Choose memories myself", and when onboarding ends. Never written to disk. |
| Representative analyses | Memory only, inside one discovery run | When the run ends |
| Possible-moment thumbnails | Requested without the image cache (`localOnly`) | The loader's cache is also cleared after Continue |
| Kept moments' photos | Imported as normal selected memories | Persisted like any selection (and only these) |

## Processing V2

The progress bar and stage messages are real, as before. The engine now also reports facts it
has actually established: moments and trips after grouping, and places as they're named. The
screen shows "12 moments found", "1 trip found" and "3 places found" only once each is known.
Rejected candidates never reach processing, so nothing about them can appear.

## First Discovery (`FirstDiscoveryResolver`)

The resolver reads Made for You's existing suggestions and the new story. It invents nothing.

1. **Movie:** Made for You's trip offered as a Memory Movie. "Four days in Kaş." /
   "31 memories · August 2026" / **Watch Your Movie**. This opens the existing editor, where the
   preview is free. There is no export and no paywall before it's viewed.
2. **Recap:** a Monthly Recap or Our Year suggestion. **See Your Recap** opens the existing
   recap.
3. **Another Made for You suggestion** (a book, story or collage). It opens the existing
   creation flow.
4. **Moment:** the moment with the most usable photos, when it has 4 or more. **Open This
   Memory** opens the existing moment in Story.
5. **Small story:** "Your story has started." with the best moment, however small.

**See Our Story** always follows. Opening the result ends onboarding (Story becomes the
destination) and opens the result over it. The suggestion is recorded as shown and opened in
Made for You's history, so Today and Create stay consistent with it.

## Premium: first-session protection

What changed:

- **The recap opened from First Discovery** (`RecapRequest.origin == "first_discovery"`) shows
  every chapter that one time, with no Premium page in the middle.
  - Sharing its card and creating from it are still Premium, as before.
  - Opening the same recap again later (Today, Create, Made for You) shows the usual preview.

What did not change:

- products and prices;
- the one free creation (movies are still outside it);
- Premium for saving or sharing movies and books.

No paywall appears during onboarding, and the Memory Movie preview is free.

## Relationship start

- **Optional.** "I'm not sure — skip" stores `relationshipStartSkipped` and no date. The earliest
  photo is **never** taken as the start.
- **Nothing preselected.** The month and year wheels start on "Month" and "Year", and the exact-day
  calendar counts only a day the couple taps. Continue stays disabled until a month and a year
  (or a tapped day) are chosen, so tapping through can never save an invented date such as "one
  year ago". Leaving the screen without choosing saves nothing; a relaunch asks again.
- **Without a date:**
  - no "Together since", no days-together count, no relationship anniversaries;
  - Story's header reads "Since your first memory · June 2019" (the earliest kept memory, used
    only to organize the timeline);
  - Us shows no "together since" or day count;
  - Edit lets the couple add a date later ("I know when it began").
- **With a date:** moments from before it go into their own first section, "Before March 2021"
  (`TimelineBuilder.beforeStartID`).
  - They are never silently deleted.
  - They're excluded from "Together since…" and from the header's moment count.
  - Days-together counts come only from the date the couple gave.
  - Discovery suggests only moments from the start on.
  - This factual rule applies to existing couples too.

Memory anniversaries such as "A year ago this week" describe a photo's own date, not the
relationship, and are unchanged.

## Accessibility

- Every new screen uses Dynamic Type text styles and wraps at the largest sizes.
- Reduce Motion: the First Discovery result appears without movement.
- Dark mode uses the system palette tokens.
- Possible moments are read as "Keep, August 6 – 9, 2026, 31 photos, 4 days" and "Not ours, …".
  The selection state is announced. "Show the photos of this moment" opens the full list.
- The progress screens combine their text into one spoken element.

## Analytics (local only)

| Event | Properties |
|---|---|
| `onboarding_started` | |
| `photo_start_choice` | `path` |
| `discovery_started` | |
| `discovery_completed` | `library` bucket, `candidates` bucket, `duration` bucket |
| `discovery_cancelled` | `duration` bucket |
| `candidate_moment_kept` / `candidate_moment_rejected` | `trip`, `photos` bucket |
| `manual_selection_completed` | `photos` bucket, `access` |
| `first_discovery_shown` | `result`, `path` |
| `first_discovery_opened` | `result`, `action` |
| `onboarding_completed` | `result`, `path` |

No identifiers, dates, places, names or captions are recorded.

## DEBUG diagnostics

The following lines are logged; none of them includes coordinates, identifiers, place names,
names, captions or faces:

- `discovery_plan library= considered= eligible= undated= beforeStart= noise= moments= trips= shortlisted= representatives=`
- `discovery_timing scan= shortlist= thumbnails= analysed= unavailable= candidates=`
- `discovery_import kept= imported=`

## Tests

- **Core** (`DiscoveryTests.swift`):
  - trips as one possible moment;
  - noise, undated and screenshots left out;
  - the start limit, and no start;
  - representatives;
  - bounds at 50,000 assets;
  - face count as ranking only;
  - utility moments dropped;
  - iCloud-unavailable thumbnails neutral;
  - only kept moments imported;
  - the proportional cap;
  - no identity fields;
  - the First Discovery hierarchy (movie, recap, moment, small story, empty);
  - the pre-start timeline (start day inclusive) and no start;
  - processing facts.
- **Hosted** (`FirstExperienceTests.swift`):
  - full-access discovery with bounded image work;
  - kept-only import and cleanup;
  - cancellation;
  - limited, denied and returning from Settings;
  - iCloud-only thumbnails;
  - the start limit;
  - routing (skip, choose, relaunch resume, existing users bypass, completion opens Story and
    the moment);
  - pre-start memories set apart and never deleted;
  - first-session recap protection only from First Discovery;
  - Premium unchanged;
  - free Movie preview.
- **UI** (`FirstExperienceUITests.swift`, iPhone 16 and iPhone SE):
  - the discovery path: Welcome → partner → skip → Let Relive find them → privacy → possible
    moments → keep / not ours → processing → First Discovery → open → close → Story (no
    "Together since") → dark and largest-type passes, including the manual screen;
  - the manual path in every other UI test's onboarding helper.

## Known limitations

- Place names come from Apple's geocoder, and their granularity varies. The same simulator trip
  was named "Kas" on one run and "Türkiye" on another, so a trip title can be broader than the
  town.

- Possible moments come from time and place. A trip with friends or family looks the same as one
  with the partner; the couple decides.
- Very large libraries: only the newest 25,000 assets are considered. Older memories can be added
  later with Add Memories.
- A possible moment whose photos are all in iCloud shows a placeholder cover during discovery.
- The UI test's sample library is synthetic. How often real libraries produce correct
  candidates or a Movie-worthy first discovery is unknown.

## Physical-device validation still needed

- PhotoKit enumeration time on a real 20k–50k library;
- Vision time for 144 thumbnails, plus battery and heat;
- iCloud-only behavior (how many representatives lack a local version);
- the real Apple permission dialogs and the limited picker's ergonomics;
- how often candidate moments are right;
- how often the first discovery is a strong Movie;
- real couples' reaction to the first WOW.
