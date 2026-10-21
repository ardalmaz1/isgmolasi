# Couples Product Review

A review of Relive as it is today (TestFlight build ≈ `beb79ef`) and of the proposed partner layer,
from two independent people in one relationship, then as a couple. Not based on gender
stereotypes: the two users differ in habits, privacy boundaries and engagement, which is what
actually varies between partners.

- **User A — "the archivist"**: takes ~20,000 photos, Full Photos access, opens apps daily,
  enjoys making things (movies, books), comfortable with settings, cautious about cloud services.
- **User B — "the occasional visitor"**: ~2,000 photos, chose Limited access, opens Relive weekly,
  rarely creates, cares about privacy of specific photos, uses Home Screen widgets a lot.

## 1. User A

| Question | Answer |
|---|---|
| Delightful | First Discovery finding "Four days in Kaş" unprompted; Memory Movie from a trip; the archive finally browsable (Memories / Moments / Places); Made for You when it's a real trip |
| Confusing | Two "Save" on the collage editor; the difference between keeping in Relive and saving to Photos; "Kept in Relive" wording; Story style row wrapping |
| Unnecessary | Trend recipes feel secondary to the core story; Surprise Memory and Found for You overlap in purpose |
| Opens tomorrow because | A recap is ready; a new trip became a moment; partner shared something (after couples) |
| Would stop because | Movie picks private photos (now mitigated by Don't Suggest); slow with 20k photos if processing were re-run often; paywall at the wrong moment |
| Privacy concern | "Does connecting my partner upload my 20,000 photos?" — must be answered on the connect screen |
| Would show partner | A Memory Movie of their trip |
| Emotionally meaningful | Seeing a forgotten afternoon resurfaced with its place and date |
| Artificial engagement | Anything asking for daily opening |

## 2. User B

| Question | Answer |
|---|---|
| Delightful | The widget showing a photo A sent; a short note; not having to sort photos themselves |
| Confusing | Limited access: "why are only some photos here?" — Us explains it, onboarding could too; the Create tab's many tools |
| Unnecessary | Our Year / Monthly Recap prompts when they rarely open the app (they're fine to find, not to be pushed) |
| Opens tomorrow because | A notification "Arda shared a memory"; the widget changed |
| Would stop because | Feeling of obligation (unanswered notes, streak-like pressure); a photo of them shared without their agreement showing on a lock screen |
| Privacy concern | Being on someone else's lock screen/widget; location of their home |
| Would show partner | Nothing proactively — they react to what A shares |
| Emotionally meaningful | "Bunu görünce seni düşündüm." with an old photo |
| Artificial engagement | Read receipts; "Kübra hasn't seen your memory" |

## 3. As a couple — scenarios

| Scenario | Today | Gap | Priority |
|---|---|---|---|
| Install together | Each builds their own private story | No way to connect | P1 |
| Only A cares | Works for A alone | Connection must never be required | — (by design) |
| A invites B | — | Invitation must explain "nothing is shared until you choose" | P0 |
| B accepts | — | Accepting must not request Full Photos access | P0 |
| First shared memory | — | Preview + undo; receiver sees it once, quietly | P0 |
| First note | — | Note ≠ chat; no reply thread | P1 |
| First widget | — | Redacted when locked by default | P0 |
| First shared trip | — | Event summaries opt-in for both | P2 |
| 20,000 vs 2,000 photos | Local processing scales per device | Nothing crosses that scales with libraries | P0 (architecture) |
| Full vs Limited | Works | Shared items appear for B regardless of B's access level | P1 |
| Daily vs weekly use | — | Notifications must be event-based, never cadence-based | P0 |
| iCloud unavailable | — | Clear state; single-person Relive unaffected | P0 |
| New iPhone / reinstall | Private story rebuilds from Photos | Shared items must re-download | P1 |
| Photo deleted from Photos | Memory disappears locally | Shared copy independent | P1 |
| Shared photo deleted by sender | — | Removed on receiver after sync | P0 |
| Accidental send | — | 5-s undo + remove later | P0 |
| Location sharing off | — | Sends without place | P0 |
| Disconnect | — | Exact, honest explanation of what each side keeps | P0 |
| Relationship ends | — | "Remove everything I shared" + block | P0 |
| Owner's iCloud full | — | Clear error; fairness question (who pays storage) | P1 |

## 4. Findings by priority

### P0 — blocks a safe launch of couples features
1. **Exact-location leakage**: shared files must have EXIF/GPS stripped; only labels/cells as fields.
2. **Lock-screen exposure**: widget and notifications redact by default.
3. **Accidental sharing**: preview + undo + remove.
4. **Honest disconnect**: describe precisely what stays on each phone (CloudKit cannot delete the
   partner's cache remotely; Relive deletes it on their phone when it loses access).
5. **Owner-storage asymmetry** (shared data lives on the inviter's iCloud): decide A/B
   (architecture §9) before Phase C.
6. **No library upload**: architecture guarantees only chosen items cross devices.
7. **Signing/capabilities on the owner's Mac** (iCloud, push, App Group, widget extension) —
   cannot be done from CI.

### P1 — important for couples V1
Invitation & acceptance; shared memories; notes; Today "From Kübra" card; widget (small/medium);
notifications for shares and notes; Save to Photos; reinstall/new-device recovery; clear iCloud
error states; couple-name ♥ presentation.

### P2 — valuable later
Our Places map; "You both captured this" (event summaries); shared moments in Story; reactions;
read state (if wanted); combined creations (two-perspective Memory Movie); Lock Screen widget;
original-quality sending; videos.

### P3 — avoid
Chat threads, typing indicators, online status; streaks, scores, health meters; daily questions,
quizzes, games; live location; public profiles, feeds, followers; automatic full-library sync;
"you haven't…" notifications; read receipts by default.

## 5. Competitor and UX patterns

| Product / pattern | What users value | What annoys / risks | For Relive |
|---|---|---|---|
| **Locket** (photo-to-widget) | Instant, intimate presence on a partner's Home Screen | Sent photos can't be taken back; broad content license in its terms (2022 reports); contacts upload for invites | Take the widget idea; reject irreversibility and contacts upload |
| **Paired** (daily questions) | Prompts that start conversations | Streak pressure (users ask to skip questions "without ruining our streak"), paywalls, unclear whether one subscription covers both | No streaks, no daily obligation; decide two-person billing clearly |
| **Between** (couples messenger) | Private two-person space | Becomes a second chat app competing with WhatsApp | Notes, not chat |
| **Apple Shared Albums / iCloud Shared Photo Library** | Zero setup, native, both contribute | Libraries merge (Shared Library) — too much for many couples; Shared Albums compress and are clunky | Item-level sharing without merging; Relive's curation on top |
| **Photo widgets (Photos "Featured")** | Surprise from one's own library | Random, sometimes unwanted photos on Home Screen | Partner-chosen content only; redaction |

Useful patterns: presence through *content* (not status); widgets as the main touchpoint for low
-engagement partners; native share sheets for invitations.
Gimmicks to avoid: streak counters, "love meters", quizzes, countdown timers designed to bring you
back.

## 6. Natural retention

Genuine reasons to return, best first:
1. **Partner shared something** — the strongest, and it's created by a person, not the app.
2. An **old memory resurfaced** with place and date (Found for You, on this day).
3. **New photos became a moment / trip** (after adding memories).
4. **A recap or Made for You** that is actually good (a real trip, a full month).
5. Widget showing something meaningful (passive — no open needed).
6. An unfinished creation (drafts) — low value as a push; show in-app only.

Notification policy: only events caused by the partner or a once-per-month recap; never cadence
reminders; at most one Relive notification per day by default; quiet hours respected by iOS Focus.

## 7. Premium implications

Keep free: connect, send, receive, view, notes, widget, Our Places. Premium unchanged for exports.
Possible later Premium: creations combining both partners' contributions. Two-person billing:
Family Sharing for the subscription is the Apple-native route (owner decision). Never gate
something a partner sent.

## 8. What not to build (and why)

| Temptation | Why not |
|---|---|
| Full chat | WhatsApp already exists; chat buries memories |
| Live location | Turns love into monitoring; Relive must never answer "where is she now" |
| Relationship scores / health meters | Reduce a relationship to a number; create anxiety |
| Streaks | Obligation, guilt, and abandonment when broken |
| Public profiles, feeds, followers | Relive is two people, not an audience |
| Random quizzes / games | Off-mission; novelty without memory |
| Partner surveillance (read receipts, last seen) | Pressure; misread silences |
| Automatic full-library sharing | Privacy breach for one partner's other life (friends, family, work) |
| Automatic exact location | Home addresses, other people's homes |
| Constant push notifications | The fastest way to be deleted |

## Sources

- [Locket Widget review (joindeleteme)](https://joindeleteme.com/is-site-safe/is-locket-widget-safe/)
- [Locket app widgets (9to5Mac, 2022)](https://9to5mac.com/2022/01/13/locket-app-iphone-widgets/)
- [How the Locket app works (Deseret News, 2022)](https://www.deseret.com/2022/1/27/22902015/how-the-locket-app-works-family/)
- [Paired reviews analysis (Kimola)](https://kimola.com/reports/unlock-insights-paired-app-customer-feedback-analysis-google-play-en-144872)
- [Couples apps ranked 2026 (Unstar)](https://unstar.app/blog/paired-lasting-love-nudge-evergreen-cupla-couples-apps-ranked-2026)
- Competitor claims come from third-party reviews and press; they are indicative, not verified.
