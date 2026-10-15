# Editorial Intelligence (Intelligence v1, phase 5)

Relive may improve **how** a fact is said. It may never invent **what** happened.

Memory Intelligence, the Made for You engine, the recap planner and the movie planner decide
what is true and what is recommended. Editorial intelligence only puts those facts into a few
words. There is one editorial layer, shared by every surface. It is not a chatbot: there is no
chat, no prompt box and no "Powered by AI".

```
structured facts → provider (deterministic; Apple on-device model where it runs)
                 → candidates → EditorialValidator → accepted words
                 → otherwise Relive's own deterministic words
```

## Where it lives

| Piece | File |
|---|---|
| Context, request, result, fact classes, the user's choice | `ReliveCore/Intelligence/Editorial/EditorialModel.swift` |
| The validator (English and Turkish) | `ReliveCore/Intelligence/Editorial/EditorialValidator.swift` |
| Deterministic writer, pipeline (cache), router, events | `ReliveCore/Intelligence/Editorial/EditorialPipeline.swift` |
| What a model is told (facts only), parsing its reply | `ReliveCore/Intelligence/Editorial/EditorialPrompt.swift` |
| Feelings and rankings policy (shared with older titles) | `ReliveCore/Intelligence/FactualTitleBuilder.swift` (`FactualTextPolicy`) |
| Apple on-device provider | `Relive/Editorial/AppleOnDeviceEditorialProvider.swift` |
| The app's entry point (router, analytics, DEBUG line) | `Relive/Editorial/EditorialService.swift` |

## Facts

`EditorialContext` holds structured facts only:

- first and last capture day (only when every memory is dated);
- months;
- place names Relive already shows;
- the trip and moment names;
- counts (memories, moments, places, favorites, months, frames);
- a season, only when known;
- the period label and the current factual title;
- other phrases already on screen;
- the user's own text.

It never holds photos, asset identifiers, coordinates, notes or captions.

Every fact has a class (`EditorialContext.facts`):

- **A. verified**: read from the library. Capture dates, place names, counts, favorites, the
  user's own words.
- **B. derived**: deterministic from verified facts. Number of days, a single shared place.
- **C. interpretation**: feelings and judgements. Relive never states one as a fact.

User-authored text (`EditorialAuthorship.user`) is never checked, rewritten or sent to a model.

## Requests

There are seven request kinds: `title`, `subtitle`, `transition`, `chapterTitle`, `closingLine`,
`shortCaption` and `shareCardLine`.

There are seven surfaces: Made for You, Recap, Our Year, Movie, Book, Story and Collage.

Length limits (`EditorialRequest.maxCharacters`):

| Where | Limit |
|---|---|
| Any Movie text | 34 characters |
| Any Collage text | 36 characters |
| Titles and chapter titles | 44 characters |
| Subtitles and share-card lines | 60 characters |
| Transitions and closing lines | 48 characters |
| Short captions | 70 characters |

## The validator

`EditorialValidator` is the one gate for every surface. It first masks the phrases the context
supports (places, trip, moment, period, factual title, known phrases, the user's text), so these
can be repeated verbatim. It then rejects the remaining text when it contains:

- **numbers** not in the facts:
  - digits must be counts, years, the number of days or the period's own dates;
  - spelled numbers ("four", "dört") must be counts or lengths, never a day of the month. "Six
    days in Kaş" is rejected for a trip that began on the 6th.
- **dates**: a month the memories don't fall in, or any weekday.
- **places and names**: an unknown capitalized word.
  - After "in/at/to/from…", or before a Turkish case ending ("Antalya'da"), it counts as a place.
  - Otherwise it counts as a name.
  - Faces are never identities.
  - "You and …" / "sen ve …" with an unknown name is an identity claim.
- **relationship events**: anniversary, honeymoon, wedding, proposal, first date, balayı,
  yıldönümü…
- **feelings and rankings**:
  - English and Turkish feeling claims ("happiest", "unforgettable", "romantic", "mutlu",
    "unutulmaz", "romantik", "aşk"…);
  - superlatives, including Turkish "en …".
- **picture contents**: beach, sunset, dinner, snow, kiss, plaj, gün batımı… unless the
  context names them.
- **seasons and trips**: a season that isn't known; "trip/tatil" when the story knows no trip.
- **length**: over the surface limit.

Rejections are codes (`EditorialRejection`). The text is never logged.

Unknown data stays unknown:

- No dates: no month names and no day counts.
- No place: no "in …".
- Mixed years: no single-year title ("Our 2025" is never offered for 2025–2026).

## Relive's own words

`DeterministicEditorialWriter` is the offline fallback, the test oracle and the words shown
first. It renders the same facts in English and Turkish (`Words`, with Turkish vowel harmony and
case endings: "Kaş'ta dört gün."). Examples:

- "Four days in Kaş."
- "Kaş · August 2026"
- "31 memories from Kaş."
- "August, together."
- "Our 2026"
- "From March to May"
- "31 memories · 4 days · August 6–9, 2026"
- "That was Kaş."
- "Then Kekova."

Each template is used only when its facts exist. Its output is still validated.

## Variants and the user's choice

- A result has at most three safe variants (`EditorialPipeline.maximumVariants`). The first
  never changes, so nothing on screen jumps.
- `EditorialChoice` records what the user decided:
  - Relive's first choice;
  - another variant (by index, plus its words);
  - their own words;
  - no words.
- "Try another" rotates variants locally. There is no network and nothing is generated again.
- A chosen variant that is no longer on offer is re-checked against the current facts before it
  is shown.
- **The user's words always win.** They are kept exactly as written (trimmed), even when they
  say something Relive would never say ("Our favorite trip"). They are kept in the draft and
  survive "Make it for me".

## Apple on-device model

- **SDK.** CI inspects the Xcode 26 SDK (`On-device model SDK (FoundationModels)` step). The
  iPhoneSimulator 26.2 SDK in Xcode 26.3 contains:
  - `FoundationModels.SystemLanguageModel.default` with `availability` (`.available` /
    `.unavailable(.deviceNotEligible | .appleIntelligenceNotEnabled | .modelNotReady)`) and
    `supportsLocale(_:)`;
  - `LanguageModelSession(instructions:)`;
  - `respond(to:options:)` returning `Response<String>.content`;
  - `GenerationOptions(temperature:maximumResponseTokens:)`.
  - The Xcode 16.4 SDK has no FoundationModels.
- **Use.** `AppleOnDeviceEditorialProvider` uses exactly those APIs, inside
  `#if canImport(FoundationModels)` and `if #available(iOS 26.0, *)`. The deployment target stays
  iOS 18.0. CI checks that the framework is weak-linked, so the app still launches on iOS 18.
- **Availability.** The model is used only when `availability == .available` and it supports
  the current locale. Everywhere else, `isAvailable()` is false and Relive silently uses its
  deterministic words. That covers iOS 18–25, ineligible devices, Apple Intelligence turned off,
  the model still downloading, and an unsupported language.
- **What it is sent.** `EditorialPrompt` sends:
  - instructions (language, the rules);
  - the context's structured facts, minus the user's own text.
  It sends no photos, identifiers, coordinates, notes or captions. Everything stays on the
  device. There is no network, no account, no API key and no per-request cost.
- **What it may do.** It only proposes alternatives:
  - every line goes through `EditorialValidator`;
  - accepted lines become "Try another" variants after Relive's first choice;
  - rejected lines are counted (codes only) and never shown.
  - Results are cached per request, so a redraw never asks again.
- **Where it runs today.** Only for the Memory Movie opening title, when the editor opens. Made
  for You, Recap and Our Year use the deterministic words (stable and glanceable).
- **Verification so far.** The on-device path builds with the Xcode 26 SDK. CI runs on
  simulators, where `isAvailable()` is false. **It has not been run on a physical Apple
  Intelligence device.** The fake-model tests cover the merge, validation and fallback logic.

## Surfaces

| Surface | What changed |
|---|---|
| Made for You | Trip cards are phrased by the pipeline: "Three days in Kaş & Kekova." / "30 memories · August 2025". The engine still decides what is recommended and which creation; only the words changed. Other cards keep their factual titles. |
| Recap / Our Year | All recap text (`ValidatedEditorialTextProvider`) now passes the same `EditorialValidator`, against the recap facts as an `EditorialContext`. Chapter plans are unchanged. |
| Memory Movie | The opening title has up to three validated variants, plus Try another / Edit / Remove / Reset in the editor's **Title** section. The choice is kept in `MovieSettings.titleChoice` (optional, so Phase 4 drafts still open). The rest of the movie stays sparse: section labels and the closing period are unchanged. |
| Memory Book, Story, Collage | They keep their factual titles (`CreationTitle`, `FactualTitleBuilder`), which already pass `FactualTextPolicy`. A title choice for the Book needs a SwiftData field and is left for a later phase. No diary prose is generated. |

## Caching and performance

- `EditorialPipeline.shared` caches results by `EditorialRequest`, the facts and the kind. The
  screen is not part of the key. The cache holds up to 300 entries.
- Measured on the Linux CI container (`EditorialPerformanceTests`):
  - 400 uncached requests took about 0.26 s, roughly 0.6 ms each, validation included;
  - the same 400 from the cache took about 0.001 s.
- The movie planner reads the cache synchronously. A model's alternatives arrive later, in the
  background, without changing what is shown.

## Privacy, analytics and diagnostics

- **Local analytics events** (codes only):
  - `editorial_requested`
  - `editorial_candidate_accepted`
  - `editorial_candidate_rejected`
  - `editorial_fallback_used`
  - `editorial_variant_changed`
  - `editorial_user_edited`
- Their properties are surface, kind, provider, variant index, rejection code and action. They
  never include text, places, dates or names.
- **DEBUG lines** (`IntelligenceDiagnostics`):
  - `editorial_provider name=… status=…`
  - `editorial_request surface=… kind=… provider=… factCount=… variants=…`
  - `editorial_validation surface=… kind=… provider=… accepted=… reason=…`
  - `editorial_fallback … reason=unavailable|error`
- **No secrets.** `scripts/check-no-secrets.sh` (run in the Linux CI job) fails on API-key
  patterns, private keys and hosted AI endpoints (OpenAI, Anthropic, Gemini, Vertex, Firebase AI).
- **Network audit.** The only network code in the app is the trend catalog (`TrendCatalogStore`,
  an optional remote JSON) and a terms-of-use link. Editorial intelligence adds none. A hosted
  test counts URL loading during editorial work and expects zero.

## Premium

Nothing changed. There is no AI tier and no editorial paywall:

- every word, "Try another" and editing are free;
- keeping a movie is still Premium (`.memoryMovie`);
- the free creation is unchanged.

## Tests

- **Core** (`EditorialIntelligenceTests.swift`, `EditorialSurfaceTests.swift`):
  - the safety matrix: numbers, dates, places, names, identity, relationship events, feelings,
    rankings, visual claims, seasons, trips, length;
  - the user's words; Turkish wording and Turkish safety;
  - the writer, pipeline, cache and router with fake models (accepted, refused, unavailable,
    failing);
  - cross-surface consistency; mixed years;
  - the movie title variants and the user's choice (resolution, Try another, own words, removal,
    persistence, Phase 4 drafts);
  - Made for You wording; analytics events without text; the model prompt (facts only, no user
    text) and reply parsing; performance.
- **Hosted** (`ReliveTests/EditorialAppTests.swift`):
  - provider selection;
  - real availability on the simulator, with silent fallback;
  - failing and untruthful fake models;
  - no network;
  - the movie title (Try another / Edit / Remove / Reset never change the photos), with
    analytics without text;
  - the user's title surviving a relaunch and "Make it for me";
  - a model alternative offered without changing what is shown;
  - Premium unchanged.
- **UI** (`ReliveUITests/MovieUITests.swift`): movie → Title → Try another (another title; the
  VoiceOver label is "Try another title") → Edit → "Our favorite trip" → close → relaunch → the
  draft shows "Our favorite trip". Screenshots V10/V11 (iPhone 16), W10/W11 (iPhone SE).
