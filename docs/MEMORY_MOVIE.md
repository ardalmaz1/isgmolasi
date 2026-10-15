# Memory Movie V1

Intelligence v1, Phase 4. Relive turns a real period (a moment, a trip, a month, a year, a recap
or a Made for You suggestion) into a short, automatically edited film of still photos. The aim is
"Relive made a little film from our memories", not a slideshow maker.

Everything stays on the iPhone: no upload, no cloud rendering, no AI, no music service and no
remote analytics.

## Architecture

```
Memory Library → Memory Intelligence (MemorySelectionPlan) → MovieStoryPlanner (MoviePlan)
              → MovieTimeline / MovieGeometry → MovieFrameDrawer → preview (SwiftUI) | export (AVAssetWriter)
```

| Layer | File | Role |
| --- | --- | --- |
| Core | `ReliveCore/Movie/MoviePlan.swift` | `MoviePlan`, `MovieScene`, `MovieSettings` (aspect, length, style, text, variation), `MovieMotion`, `MovieTransition`, `MovieFraming`, `MovieText`, `MovieSoundtrack`, `MovieEligibility` |
| Core | `ReliveCore/Movie/MovieStoryPlanner.swift` | The edit, on top of Memory Intelligence |
| Core | `ReliveCore/Movie/MovieTimeline.swift` | What is on screen at any time; where each photo is drawn |
| App | `Relive/Movie/MovieEditorModel.swift` | Relive's cut plus the user's overrides; drafts |
| App | `Relive/Movie/MovieDrawing.swift` | `MovieFrameDrawer` (one frame, Core Graphics), captions, scene image loading |
| App | `Relive/Movie/MoviePreviewView.swift` | Live preview |
| App | `Relive/Movie/MovieRenderer.swift` | AVFoundation export |
| App | `Relive/Movie/MovieExportController.swift` | Progress, cancel, background, Save to Photos, Share |
| App | `Relive/Movie/MovieEditorView.swift` | The editor |

**Not a second memory engine.** Photo choice, duplicate collapse, diversity, chronology, the
period, the factual title, favorites and covers all come from `MemoryIntelligenceEngine`. The
movie planner only adds what is specific to film:

- framing
- motion
- rhythm
- transitions
- a few words

The core is Foundation-only, deterministic, Codable and Linux-tested. It has no AVFoundation and
no pixels.

## MoviePlan

- **Plan:** a source, a status (`ready`, or `insufficient(available, required)`), settings, the
  `FactualTitle`, the period label, the scenes, whether the cut is the user's own, the
  limitations, and counts (source, duplicates removed, similar collapsed). The soundtrack is
  always `.silent`.
- **Scene:** one photo with:
  - a role (opening, body, section opener, closing)
  - a duration
  - motion and framing (with a focus point)
  - the photo's own aspect ratio
  - the transition into it and its length
  - optional factual text
  - its section index
- **Running time:** crossfades overlap the neighbouring scene; cuts and fades through black
  don't.

## Eligibility

| | Rule |
| --- | --- |
| Make a movie | at least **5** distinct, usable photos (`MovieEligibility.minimumPhotos`) |
| Hand-picked | 5–30 photos, kept as chosen |
| Suggest a movie | a trip story: ≥ 15 distinct photos over ≥ 3 days; or any set: ≥ 10 distinct photos, ≥ 3 moments, ≥ 2 days |

"Distinct" means after Memory Intelligence has removed re-saved copies and collapsed
near-identical shots. So a burst of near-identical selfies never qualifies, and fifteen
near-identical photos are one photo.

When a movie can't be made, the editor says so plainly ("A movie needs at least 5 different
photos…"). Nothing is padded.

## Scene selection and story

**Automatic sources** (moment, trip, month, year, favorites):

- Memory Intelligence chooses up to the length's cap: 9 for Short, 15 for Standard, 22 for
  Long. It balances moments, days, shapes, favorites and covers.
- The lead opens. The rest follow in the order they were taken.
- Variations ("Make it for me" again) open on another strong photo and use the next style. The
  photos are the same memories.

**Hand-picked photos and edited cuts** keep their photos and order exactly. Photos that can't be
shown are left out and reported (never replaced).

**Sections:** consecutive photos of one moment form a section. In order of importance, a
section's change is a new year, a new month, a new place, a new day, or a new moment. For
example, a trip's next stop is a new place even though it is also a new day.

**Story shape:**
- the opening is the title shot;
- section openers stay a little longer;
- the closing is the last photo under the closing words.

A 5-photo moment is simply title, three photos, closing. A year has many sections.

**Rhythm** (seconds, before the style's rhythm factor):

| Scene | Time |
| --- | --- |
| Opening | 3.9 s |
| Closing | 3.8 s |
| Section opener | base + 0.5 s |
| Body | base (Short 2.4 s, Standard 2.8 s, Long 2.9 s) |
| Supporting (3rd+ in a section) | base − 0.3 s |
| Favorite or cover | + 0.3 s |

Every scene stays between 1.8 s and 4.6 s. A cut longer than the length's maximum is shortened
evenly (never below 1.8 s). A short source stays short.

## Framing (smart cropping)

A photo **fills** the frame when that hides at most 30% of it. Otherwise it is shown **whole**,
over a softened, darkened copy of itself (`fit`). For example:

- a 3:4 portrait fills a 9:16 movie (25% cropped);
- a 4:3 landscape is shown whole in a 9:16 movie;
- in 16:9 it is the other way round.

When filling, the focus point (0.5, 0.42) keeps the upper middle in view, where faces usually
are. Nothing is ever invented: there is no generative fill, and the background is the photo
itself, blurred.

## Motion

The available motions are still, zoom in, zoom out, pan left/right/up/down.

- **Strength:** zoom is at most 7%. Pans travel 60% of the photo's spare edge, never past it
  (the photo always covers the frame).
- **Variety:** no motion repeats on two scenes in a row (still may).
- **Faces:** photos with people are never panned. They get a gentle zoom out, still, or zoom in.
- **Whole photos:** "fit" photos only zoom gently (4%).
- **Opening and closing:** the opening pulls back (still in Editorial). The closing settles
  (still in Editorial and Film).
- **Deterministic:** the same plan always has the same motion.

The exported movie keeps its gentle motion even with Reduce Motion on, because it is the user's
own media. The editor UI respects Reduce Motion: no animated changes, and nothing plays by itself.

## Transitions

| Into | Transition |
| --- | --- |
| The opening | fade in from black (0.8 s) |
| A new year, month or place | fade through black (1.0 s; 1.2 s Editorial) |
| A new day or moment | crossfade (0.9 s) |
| Within a moment | crossfade (0.6 s; 0.8 s Editorial); Film cuts every other photo |
| The closing | crossfade (1.0 s) |
| The end | fade to black (1.0 s) |

No transition takes more than 45% of either neighbouring scene. There are no spins, wipes or 3D
effects.

## Text

All text comes from the factual title system:

- **Opening:** the period (e.g. "AUGUST 2025") over the title ("Kaş & Kekova").
- **Section labels:** a few factual labels at new places, months and years ("Kekova",
  "Kaş · August 2025"). They appear only in films with three or more sections, and at most one
  per four photos (four at most).
- **Closing:** the period over "Made with Relive".

Nothing claims a feeling. Every word passes `FactualTextPolicy` (tested). The Titles toggle
removes all of it. Words sit in the lower part of the frame over a soft shade.

## Styles

All four styles share the same plan and the same facts.

| Style | Typography | Rhythm and motion | Look |
| --- | --- | --- | --- |
| Classic | serif title, centred low | crossfades, gentle motion | neutral |
| Editorial | small-caps sans, left aligned | slower (×1.1), more stillness | neutral |
| Film | monospaced, like a date stamp | pans and some hard cuts | warm wash and a soft vignette |
| Warm | rounded, centred | zooms only | light warm wash |

## Editor

- **Preview and Make it for me:** play and pause the preview; "Make it for me" gives a new cut.
- **Settings:** style; shape (9:16 Tall, the default, or 16:9 Wide); length (Short, Standard or
  Long); Titles on or off.
- **Scene strip:** tap a scene to move it earlier or later, make it the opening, replace it
  (with another photo from the same source) or remove it. A movie keeps at least 5 photos.
- **Keeping it:** Save Video, and Share in the toolbar.

**User overrides:**
- Any edit to the photos makes the cut the user's own (`isUserCut`).
- Style, shape, length and titles never change which photos are used. Length re-chooses photos
  only for Relive's own cut.
- Only an explicit "Make it for me" replaces a user's cut.

**Drafts** use the existing `CreationKeeper`, like collages and stories. A draft keeps
`MovieState`: the photo identifiers in order, the cover, the settings and `isUserCut`. It never
keeps frames or video. It survives relaunch and appears under Continue Editing and in My
Creations. Photos that disappeared are left out and reported.

## Preview

The preview draws `MovieTimeline.frame(at:)` with the same `MovieFrameDrawer` as the export, so
crop, motion, transitions, words and timing match. Only the size differs:

- photos are loaded once at 0.42× export scale and cached;
- frames are drawn at screen size (2× at most), up to 30 times a second.

The preview never renders a video.

## Renderer and export settings

| Setting | Value |
| --- | --- |
| Container | MPEG-4 (`.mp4`) |
| Codec | H.264, High profile (auto level) |
| Resolution | 1080 × 1920 (9:16) · 1920 × 1080 (16:9) |
| Frame rate | 30 fps |
| Bit rate | ~10 Mbit/s average, key frame every 2 s |
| Audio | none (silent) |

- **Pipeline:** `AVAssetWriter` with a pixel-buffer adaptor. Each frame is drawn with Core
  Graphics into a 32BGRA buffer, off the main thread.
- **Memory:** only the photos on screen and the next scene's are decoded, each at the size it is
  drawn (capped at 1.6× the frame's long side). A scene's pixels are released as soon as it has
  played. A "fit" scene's softened copy is computed once at 15% size.
- **Space:** checked before rendering; it fails early with "There isn't enough free space…".
- **Cancel and failure:** Cancel stops between frames and deletes the partial file. Failures
  delete it too; nothing half-written is kept.
- **Progress:** "Creating your movie… 42%", then "Saving to Photos…".
- **Backgrounding:** rendering continues for the time iOS allows (a background task). If that
  runs out, it stops cleanly and says "Making the movie stopped when Relive left the screen.
  Please try again."
- **Repeated taps:** while one export runs, more taps are ignored (one export at a time).

**Save to Photos:**
- uses the add-only Photos permission;
- adds the video with `PHAssetCreationRequest`;
- records its identifier as Relive's own (`recordCreatedAssets`), so it is never imported as a
  memory. Videos also never count as creation photos.

**Share:** the native share sheet with the movie file. Temporary files are removed after saving,
after sharing, and on failure.

## Premium

Commercial v1 rules are unchanged.

- **Free:** making, previewing, editing and keeping a draft.
- **Premium:** Save Video and Share go through `PremiumGate` with `.memoryMovie` and the
  paywall line "Keep this movie". Closing the paywall returns to the editor exactly as it was.
  After a purchase, the pending save or share continues on its own (existing gate behaviour).
- **Free creation:** `memoryMovie` is not covered by the one free creation, which still applies
  to collage, story and trend only.

A free movie export could be a strong first taste. But it is the most expensive creation, and
changing the allowance is a product decision, so it was not changed. The paywall's benefit line
now reads "Stories, Collages & Memory Movies".

## Made for You, Recap and Create

- **Made for You:** a large, varied trip is offered as a film ("A trip · Kaş · August 2025 ·
  31 memories · 4 days · Memory Movie").
  - Opening it records it as opened and starts the editor; previewing doesn't retire it.
  - A successful export records it as made (`recordMade(source:creation:)`). Only that source's
    movie suggestion is affected.
  - Today's single card can be this movie.
- **Recap:** the closing chapter of Monthly Recap 2.0 and Our Year 2.0 offers "Make a Movie".
  It uses the same period and the same Memory Intelligence selection, under the recap's existing
  Premium rule for creating from the full recap.
- **Create:** Memory Movie sits in Create Something, after Memory Book. Its source chooser
  offers Choose a Moment, a Trip, a Month, a Year, or Photos (from Relive or the photo library).

## Analytics (local)

Events:
- `movie_started`, `movie_previewed`
- `movie_style_changed`, `movie_regenerated`
- `movie_export_started`, `movie_export_completed`, `movie_export_failed`
- `movie_shared`

Properties are source kind, style, aspect, length, origin, result, and render seconds. There are
never identifiers, titles, places or dates.

## Debug diagnostics (DEBUG only)

```
movie_plan source=trip sourceCount=31 selected=15 duration=38.4 aspect=9:16 style=classic length=standard scenes=15 sections=5 duplicatesRemoved=0 similarCollapsed=3 fit=6 userCut=false
movie_export_started scenes=15 duration=38.4 resolution=1080x1920
movie_export_completed seconds=… fileSizeMB=… frames=…
```

## Music

V1 is silent. Relive ships no music, downloads none, and has no Spotify or Apple Music
integration.

`MovieSoundtrack` (only `.silent` today) is the seam for later:
- properly licensed bundled tracks;
- royalty-free packs;
- a user-authorised workflow, if that ever becomes legally and technically appropriate.

Adding one means an audio input to the renderer; the plan and the edit stay the same.

## Original videos

V1 is photo-only. Videos are already not "usable" creation photos, and Memory Intelligence never
selects them.

A future `MovieScene` kind could carry a short clip: an in/out range and muted audio by default.
The renderer would draw its frames with `AVAssetReader` in place of a still. This was left out
on purpose so V1 stays reliable.

## Performance

- **Planning** is metadata-only and runs in milliseconds.
- **Export (hosted test):** `MovieRendererTests.testAWideMovieAndTheExportedNumbers` renders a
  full 1920 × 1080 Short movie and prints `MOVIE_EXPORT_PERF`. Simulator numbers are recorded in
  `INTELLIGENCE_V1_PROGRESS.md`. They are not physical-device figures.

## Tests

**Core (Linux and macOS), 24 tests:**
- *Fixtures A–J:* small moment, burst, four-day trip, mixed orientation, 150-memory year,
  favorites, hand-picked, hidden/missing/duplicate, mixed years, insufficient.
- *Plan rules:* determinism, no repeats, restrained transitions and motion, facts unchanged by
  style or shape, every word factual, variations, diagnostics.
- *Timeline:* fades, overlaps, captions, a filled photo always covers the frame, load sizes.
- *Premium and drafts:* the movie is Premium and not the free creation; drafts encode and older
  creations still decode.

**Hosted (`ReliveTests/MovieAppTests.swift`):**
- *Editor and drafts:* the override rules, and a draft surviving a relaunch.
- *Premium:* preview is free and keeping is Premium.
- *Renders:* a real small render (playable, size, duration, one video track, a decodable frame,
  progress) and a full-size 16:9 render at 30 fps.
- *Failures:* cancellation and a missing photo leave no file.
- *Export:* one export per double tap, recorded as Relive's own, with temporary files removed.

**UI (`ReliveUITests/MovieUITests.swift`):**
- Create → Memory Movie → trip → preview → style and shape → move and remove scenes.
- Save → paywall → close (edit preserved) → Share → paywall → close.
- Relaunch as Premium → draft → save.
- Made for You → movie; dark mode; the largest text size.
- The same test runs again on an iPhone SE.
