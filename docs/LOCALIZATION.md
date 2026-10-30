# Localization

Yuvi ships in English first; v1.1 adds Turkish, then Spanish, Italian, German, French and
Portuguese. This file is the rule book for that work (who writes what, and how a string becomes
translatable). Read it before touching any user-facing text.

## Who does what

| Part | Owner | Why |
| --- | --- | --- |
| Moving app strings into the String Catalog (mechanical, ~1,000 strings) | Codex | No design decisions; rules below |
| Generated sentences in ReliveCore (moment titles, recap lines, counts, "a year ago today") | Claude | Grammar is code: Turkish suffixes, German articles, Spanish gender |
| Turkish translation | Claude, reviewed by Arda | Home market; tone of a printed album, never machine-sounding |
| ES / IT / DE / FR / PT | Codex first pass, Claude review on screenshots | |
| App Store page per language (name, subtitle, description, screenshots) | Claude | Search ranking comes from here |

## Where strings live

- **App:** `Relive/Resources/Localizable.xcstrings` (plus `InfoPlist.xcstrings` for permission
  texts). Source language English.
- **Nouns after numbers:** `Relive/Resources/Nouns.xcstrings` (see Counts).
- **ReliveCore:** generated words go through `EditorialLanguage` / `CoreWords`, which follow the
  app's own localization (`Locale.reliveDisplay` = `Bundle.main.preferredLocalizations`), not the
  device region. Under `swift test` that is English. The package has no string catalog.

## Adding or updating a language

Xcode does not fill the catalog on build. Round-trip through XLIFF:

1. `xcodebuild -exportLocalizations -project Relive.xcodeproj -localizationPath <dir> -exportLanguage tr`
2. Fill `<target>` for every unit (keep `%1$@`, `%lld` and their positions).
3. `xcodebuild -importLocalizations -project Relive.xcodeproj -localizationPath <dir>/tr.xcloc`

Unit and UI tests run in English: pass `-testLanguage en -testRegion en_US` (the simulators are
set to Turkish). `ScreenshotTourUITests` finds tabs by position, so it also runs in any language
(`-testLanguage tr -testRegion tr_TR`).

## Rules for app strings (Codex)

1. A string literal passed straight to SwiftUI (`Text("…")`, `Button("…")`, `Label("…", …)`,
   `Section("…")`, `NavigationLink("…")`, `Toggle("…")`, `.alert("…")`,
   `.confirmationDialog("…")`, `LabeledContent("…")`) is already localizable. Leave it.
2. A literal that reaches the screen through a `String` (a custom view's `title: String`, a
   computed `var text: String`, `QuietMessageView(title: "…", message: "…")`, an error's
   `errorDescription`, analytics excluded) becomes `String(localized: "…")`. Interpolations stay
   interpolations: `String(localized: "Waiting for \(name) to accept")`.
3. Never localize: analytics names and properties, accessibility identifiers, logger messages,
   UserDefaults keys, product IDs, file names, URLs, launch arguments, `Text(verbatim:)`.
4. Add a `comment:` only when the English is ambiguous out of context ("Keep" — keep a moment).
5. Don't reword English while moving it. A wording change is a separate commit.
6. Build and run `ReliveTests` after each folder; UI tests run in English and must still pass.

## Counts

`Counted.text(count, "photo", "photos")` looks both words up in the `Nouns` table and picks by
count. Turkish uses the singular after a number ("3 fotoğraf"), so its "photos" entry is
"fotoğraf". This covers every planned language without plural rules in code.

## Dates

`DateText` uses date templates, so month and weekday names already follow the device language.
Don't build dates by hand.

## Turkish style

- Address the couple in the plural ("anılarınız", "Fotoğraflarınızı seçin"), warm and plain,
  never formal-stiff and never chatty.
- Proper nouns take an apostrophe before suffixes: Kaş'ta, Bodrum'dan, Eylül'e
  (`TurkishSuffix` in ReliveCore).
- Buttons are verbs in the imperative: "Kaydet", "Paylaş", "Davet Et".
- Keep "Premium" and "Yuvi" as is.
