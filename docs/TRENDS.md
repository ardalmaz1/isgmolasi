# Relive Trends — v0.3 foundation

Trending Now is the top of the Create tab: a short, changing set of looks the couple can make
from their own photos — a black-and-white editorial portrait, a photo-booth strip, a magazine
cover. Below it, the permanent tools stay where they were (Memory Collage, Story Maker, Memory
Book, Monthly Recap, Our Year).

v0.3 builds the foundation: a data-driven catalog, compiled-in recipes, five working on-device
trends, and the architecture (not an integration) for AI trends.

Code: `Packages/ReliveCore/Sources/ReliveCore/Trends/` (catalog model, parser, validation,
filtering, AI abstraction, starter catalog — Foundation only, tested on Linux) and
`Relive/Trends/` (recipes, catalog store, screens).

## 1. Trend model

`TrendDefinition` is what a trend *is*, as data:

| Field | Meaning |
| --- | --- |
| `id` | Stable slug (`bw-editorial`). Never reused for a different trend. |
| `name`, `summary`, `detail` | Shown on the card and the detail screen (40 / 140 / 400 chars max). |
| `execution` | `local`, `template` or `ai` (§6). |
| `recipe` | `{ id, version }` — which compiled recipe makes it (§5). |
| `photos` | `{ minimum, maximum }`, 1…12. |
| `aspectRatios` | Output shapes (`portrait` 4:5, `story` 9:16, …). |
| `guidance` | Up to 4 "Best results" tips. |
| `badge` | Optional `new` or `trending` — one quiet word on the card, nothing more. |
| `priority` | Higher shows first; ties by name. |
| `isActive`, `availableFrom`, `availableUntil` | Switch off, schedule, expire. |
| `minimumAppVersion` | Hidden in older apps. |
| `privacy` | `onDevice` or `aiProvider` — must match `execution` (§8). |
| `tier` | `free` or `pro`. Data only in v0.3 — nothing is gated (§12). |
| `parameters` | Up to 16 plain string values for the recipe (unused by v0.3's recipes). Never code. |

Unknown fields are ignored and missing optional fields get safe defaults, so newer catalogs work
in older apps and the other way round.

## 2. Catalog model

`TrendCatalog { schemaVersion, revision, trends }`.

- `schemaVersion` is the *format*. This app reads version 1; a catalog with a higher version is
  rejected as a whole (`unsupportedSchema`) and the app keeps what it has.
- `revision` is the *content* version, increasing with every publish. The app always uses the
  highest revision it has that parsed — the bundled catalog is the floor.
- Parsing is lossy per entry: one malformed or invalid trend is dropped (and logged), the rest
  are kept. Duplicated ids keep the first. Payloads over 512 KB are rejected.

Validation (`TrendCatalogParser.validate`) checks slugs, text lengths, photo counts, aspect
ratios, guidance, parameter keys and sizes, date order, the version string, and that the privacy
promise matches the execution type.

Then `TrendCatalogFilter` decides, for this app on this day, each trend's availability:
`available`, `comingSoon` (an AI trend without a provider) or hidden (inactive, not yet
available, expired, requires a newer app, or a recipe this app doesn't have).

## 3. Local catalog

`StarterTrendCatalog` ships inside the app as JSON — the same format a server would send, read
by the same parser — so Trending Now works on first launch, offline and if the network or
server fails. v0.3's starter trends (all original Relive designs with generic names):

| Trend | Type | Photos | Output | Variations |
| --- | --- | --- | --- | --- |
| B&W Editorial | LOCAL | 1–2 | 4:5 | Noir, Soft |
| Film Couple | LOCAL | 1 | 4:5 | Warm, Faded, Cool |
| Photo Booth Strip | TEMPLATE | 3–4 | 9:16 | Black & White, Colour |
| Magazine Cover | TEMPLATE | 1 | 4:5 | White, Black, Red |
| Cinematic Poster | TEMPLATE | 1 | 9:16 | Colour, Mono |
| Golden Hour Portrait | AI | 2 | 4:5 | — shown as *Coming soon* |

## 4. Future remote catalog

`RemoteTrendCatalogProvider` is implemented but **not configured**: it only exists when
`ReliveTrendCatalogURL` is set in Info.plist, and it isn't, so v0.3 makes no network requests
for trends. When configured:

- HTTPS only (an `http` URL is refused); a 10-second timeout; status must be 200.
- The response is parsed and validated exactly like the bundled catalog. Only a valid catalog
  is cached (Application Support) and used. Anything else is logged and ignored.
- `TrendCatalogStore` starts with the best of bundled and cached, then refreshes when Create
  appears, and switches only to a higher revision.
- The catalog is static JSON: it can be served from any CDN; no backend logic is needed to
  start.

## 5. Recipe and version system

A trend and the code that makes it are separate:

- A **recipe** is Swift code compiled into the app (`TrendRecipe`): how to process each photo,
  the named variations, the output shape, the photo frames for export, and the canvas.
- It is identified as `id@version` (`photo-booth@1`). `TrendRecipeRegistry` lists the recipes
  this build has.
- A trend *refers* to a recipe. If the app doesn't have that exact `id@version`, the trend is
  hidden — never approximated.
- Changing a recipe's look in a way that would change existing results means a new version
  (`photo-booth@2`) next to the old one; the catalog moves trends over when apps that have it are
  common enough (`minimumAppVersion`).
- `parameters` are plain, validated strings carried with the trend (and passed to AI
  requests). v0.3's on-device recipes don't read any yet; they are the intended way for several
  trends to share one recipe later (e.g. a palette name), with the recipe falling back to its
  defaults for anything unexpected.

**A remote catalog can only choose among recipes already in the app.** It cannot download or
run code, scripts, shaders or templates-as-code. This is the main safety property of the system.

## 6. LOCAL, TEMPLATE and AI

| | LOCAL | TEMPLATE | AI |
| --- | --- | --- | --- |
| What happens | Image processing on the photo (Core Image: tone, colour, grain, vignette) | The photos placed in a designed layout with real facts (dates, place, names) | A generative model makes a new image |
| Where | On the iPhone | On the iPhone | At an AI provider |
| Privacy | `onDevice` | `onDevice` | `aiProvider` |
| v0.3 | Works | Works | Shown as *Coming soon*; cannot be started |

LOCAL and TEMPLATE trends share one flow: detail → Choose Photos (the existing picker, with
the trend's photo range) → studio (preview at screen size, variations, Share, Save to Photos).
Processing is deterministic — the same photo and variation give the same pixels (tested), so
"Try another" is the variation row, not randomness. Text on templates is factual only: a real
date, a real place, the couple's names *only if both are set*; never invented captions.

The **preview** on cards and the detail screen is the real recipe applied to the couple's own
photos (sized for the screen), not a stock image, so what they see is what they'll get.

**Export** reuses the v0.2 pipeline: photos are reloaded at the pixel size of their frame,
processed again at that size, and the canvas is rendered at 2× (2160 px wide: 2160 × 2700 for
4:5, 2160 × 3840 for 9:16). Saving goes through `ExportController`: one export at a time, and
Save is disabled after a successful save until the variation changes, so it can't be saved
twice by accident. Saved images are recorded as created by Relive and never resurface as
memories.

## 7. AI provider abstraction

Only protocols and a coordinator exist — **no provider, no SDK, no API key, no network code**:

- `AITrendProvider { name; generate(AITrendRequest) async throws -> AITrendResult }`.
- `AITrendRequest` carries only the trend id, recipe reference, the chosen photos as JPEG data,
  the output shape and the trend's parameters. No library, no story, no names, no location.
- `AITrendCoordinator(provider:entitlements:)` is the only path to a provider. Its checks, in
  order: it is an AI trend → a provider exists (`providerNotConfigured`) → the user agreed to the
  disclosure (`consentRequired`) → the photo count fits → entitlements allow it. Each is tested;
  in the app the coordinator is created with `provider: nil`.
- Results are image data; a future result screen would reuse the studio and export path.

A real provider would live in the app or behind a Relive backend proxy (preferred, so no
provider key ships in the app), be chosen after a privacy, quality and cost review, and be added
by passing it to the coordinator — nothing else changes.

## 8. Privacy boundary

- The boundary is explicit and testable: `TrendPrivacyGate.requiresDisclosure(trend)` is true
  for, and only for, trends processed by an AI provider (`execution == .ai` or
  `privacy == .aiProvider`), and validation rejects any catalog entry where the two disagree — a
  catalog cannot label an AI trend "on device".
- On-device trends show "Made on this iPhone. Your photos aren't uploaded." and never show the
  AI disclosure (tested).
- AI trends show **About AI creations** on the detail screen: the selected photos would be
  processed by an AI provider; only the photos selected for that creation would be sent; the
  rest of the library is not uploaded; and, today, that AI creations aren't available so nothing
  is sent.
- v0.3 uploads nothing. With no provider, the coordinator cannot send.
- Future: before the first AI creation, the disclosure becomes an explicit agreement (the
  coordinator already requires `userConsented`); photos would be downscaled and stripped of
  location metadata before sending; the provider's retention terms would be stated in the
  disclosure.

## 9. Future Trend Radar (not in the app)

Trend Radar is an internal, human-run process for spotting looks worth offering. It is **not**
part of the app and v0.3 builds none of it — no scraping, no crawler, no social-network
integration, no automatic publishing.

Sources would be human observation and public, licensed signals (e.g. what Relive users make
most, editorial trend reports, design press). Each candidate is written up as: the look, why it
fits Relive (couples, memories, warmth — not virality for its own sake), which recipe could make
it (existing or new), example inputs and outputs made from the team's own photos, and
originality notes (§13).

## 10. Human review lifecycle

Every trend moves through the same states. Only a person moves it forward.

| State | Meaning | Who |
| --- | --- | --- |
| Candidate | Idea logged with notes and references | Anyone on the team |
| Review | Checked for fit, originality, privacy, feasibility | Product + design |
| Approved | Accepted; recipe chosen or scheduled for a release | Product |
| Testing | In a test catalog (TestFlight / internal) with real photos of many kinds | QA + design |
| Live | In the published catalog | Product (publishes) |
| Archived | Switched off (`isActive: false`) or expired; id kept, never reused | Product |
| Rejected | Not pursued, with the reason | Review |

Review checks: works for many skin tones, lighting and photo qualities; output is beautiful
with ordinary photos; no misleading text; accessible description; no third-party marks; recipe
version available in the app versions it targets.

## 11. Future admin publishing concept

No admin dashboard is built in v0.3; the catalog is a JSON file. The intended path:

1. Trends are edited as JSON in a private repository, one file per trend, reviewed by pull
   request.
2. CI validates every change with the same `TrendCatalogParser` the app uses (the package is
   Foundation-only, so it runs on Linux), plus publishing rules: revision increases, ids are
   never reused, every app version still supported keeps at least one available trend, AI trends
   carry `aiProvider` privacy.
3. A publish step assembles the catalog, signs or checksums it, and uploads it to a CDN at the
   URL in `ReliveTrendCatalogURL`. A test URL serves the Testing catalog to internal builds.
4. Rollback is publishing a higher revision with the previous content; a takedown is
   `isActive: false` on the trend.

A web dashboard can sit on top of the same files later if the volume justifies it.

## 12. Future monetization integration point

There is no paywall, StoreKit or purchase in v0.3, and every trend is free to use.

The hook is `CreationEntitlements` (core): `decision(forTrend:)` and `decisionForMemoryBook()`
return `allowed`, `requiresPro` or `outOfCredits`. v0.3 uses `OpenAccess`, which allows
everything. The `tier` field marks trends that a future plan might include, without gating
anything today. AI generation is costly per image, so the design assumes **metered** AI
(credits or limits), not unlimited use; the coordinator already checks entitlements before any
provider call, so a credit system plugs in there.

## 13. Copyright and trademark considerations

- Trends are original Relive interpretations of broad styles (black-and-white portraiture,
  photo booths, magazine covers, film looks), named generically.
- No other company's templates, layouts, fonts, logos, filter names or brand names. The magazine
  masthead is "US"; no real publication is imitated. The poster credits use only the couple's
  own facts.
- Catalog text is reviewed for third-party marks before publishing (§10).
- AI trends must not reproduce identifiable artists' work or celebrities' likenesses; the review
  for any AI trend includes this.
- Relive uses only the user's own photos; outputs belong to the user.

## 14. Failure and fallback behaviour

| Situation | Behaviour |
| --- | --- |
| Offline, first launch | Bundled catalog. |
| Remote not configured (v0.3) | Bundled catalog; no request made. |
| Network error / non-200 / timeout | Keep the current catalog (cached or bundled). |
| Malformed JSON, too large | Rejected whole; keep current. |
| Newer schema | Rejected whole (`unsupportedSchema`); keep current. |
| One invalid trend | That trend dropped and logged; the rest used. |
| Older revision than we have | Ignored. |
| Trend needs a newer app / recipe not in this app | Hidden. |
| Trend inactive, scheduled or expired | Hidden. |
| AI trend, no provider | *Coming soon* card and detail with the disclosure; the button is disabled ("Not available yet"). No fake progress, no placeholder result. |
| Trend opened after it disappeared | "This trend isn't available" message. |
| Not enough photos in the library | Picker can't finish until the minimum is chosen. |
| A chosen photo was deleted | Studio says so; Save and Share are disabled. |
| Export fails | The v0.2 export status shows the reason; nothing is saved. |
| Photo access limited/denied | Same as the rest of Relive: only accessible photos are offered. |
