# Task: translate an iOS app's UI strings

App: "Yuvi", a private couples' photo-memory app (moments, trips, monthly recaps, books, collages, short movies). Warm, plain, factual tone. Never invent claims.

Input: `src.txt` — one string per line, `index<TAB>English`. A literal `\n` means a newline; keep it as `\n`.

Output: for each language write a file with EXACTLY the same indices, one per line, `index<TAB>translation`, no extra lines:
- `es.txt` Spanish (neutral, Latin-America-friendly)
- `it.txt` Italian, `de.txt` German, `fr.txt` French, `pt-BR.txt` Brazilian Portuguese

Style:
- Address the user the way each platform's Apple UI does: es "tú", it "tu", de "du", fr "vous", pt-BR "você".
- Buttons are short imperatives in title/sentence case as Apple does in that language.
- Keep unchanged: "Yuvi", "Premium", "Yuvi Premium", "iCloud", "iPhone", "App Store", "Apple", emoji, "✓", "yuvi".
- Placeholders MUST be preserved exactly and the same count: `%@`, `%lld`, `%1$@`, `%2$lld`, `%%` etc. You may reorder positional ones (`%1$@`) but never drop or add. Unnumbered ones must stay in the same order.
- Single letters N/E/S/W are compass points; translate to that language's letter.
- "US" (index 605) is the tab title "Us" in caps (the couple), not the country.
- Indices 712–718 ("are %lld", "are only %lld", "is 1", "is only 1") fill the `%2$@` slot of index 44/51/57 ("…and there %2$@ here."). Translate those sentences so the slot takes just the number phrase, and translate the fragments accordingly (e.g. es sentence "…y aquí hay %2$@." with fragments "%lld" / "solo %lld" / "1" / "solo 1").
- Lowercase single nouns near the end (book, collage, movie, story, moment, trip, a month, your partner) are inserted into other sentences; translate as plain lowercase nouns.
- "Our %@" / "Our Year" are product names of recaps; translate naturally ("Nuestro año").

Do not run builds, do not use git. Only write the five files. When done, verify every file has the same number of lines as src.txt.
