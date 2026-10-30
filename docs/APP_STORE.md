# App Store submission — Yuvi v1

Everything App Store Connect asks for, ready to paste. The app's internal names (bundle ID
`com.ardaalmaz.reliveapp`, iCloud container, product IDs `relive.premium.*`, the `ReliveCore`
module) stay as they are: users never see them, and changing them would mean new App Store
Connect, iCloud and subscription setup.

v1 = everything in the app today: the private story, creations, Monthly Recap / Our Year, Premium
and the partner connection (Phase B). Shared memories (Phase C onward) come after v1.

## Before submitting — checklist

| | Item | Who | Where |
|---|---|---|---|
| ☑ | App name "Yuvi: Our Story Together" accepted | Arda | App Store Connect → App Information |
| ☑ | Contact e-mail for privacy and support pages | Arda | helloyuviapp@gmail.com |
| ☑ | Privacy and support pages published (GitHub Pages), then `CommercialLinks.privacyPolicy` set | Claude | `https://ardalmaz1.github.io/yuvi/privacy/`, `/support/` |
| ☐ | CloudKit schema deployed to Production | Arda + Claude | `COUPLES_ARCHITECTURE.md` §19, release checklist |
| ☐ | Paid Applications agreement, banking, tax | Arda | App Store Connect → Business |
| ☐ | Subscription group and both products | Arda | `COMMERCIAL.md` → App Store Connect setup |
| ☐ | Sandbox purchase, restore, cancel on a device | Arda | `COMMERCIAL.md` → Sandbox testing |
| ☐ | Partner connection on two iPhones | Arda + Kübra | `COUPLES_DEVICE_TEST_PLAN.md` § Phase B |
| ☐ | Screenshots (6.9-inch) | Arda | see Screenshots below |
| ☑ | Version set to 1.0 (build 7) | Claude | `MARKETING_VERSION` |

## App Information

| Field | Value |
|---|---|
| Name (30) | Yuvi: Our Story Together |
| Subtitle (30) | Your love story, from photos |
| Primary category | Lifestyle |
| Secondary category | Photo & Video |
| Content rights | Does not contain third-party content |
| Age rating | 4+ — answer "None" / "No" to every question (no user-generated content is published; photos stay on the device; no web access, no chat) |
| Privacy Policy URL | https://ardalmaz1.github.io/yuvi/privacy/ |
| Support URL | https://ardalmaz1.github.io/yuvi/support/ |
| Copyright | 2026 Arda Almaz |

## Version text

**Promotional text (170)**

> Your relationship, told through the photos you already have. Private by design: everything is
> organized on your iPhone.

**Description (4000)**

> Your love story already lives in your camera roll. Yuvi brings it back.
>
> Choose the photos of the two of you, and Yuvi arranges them on your iPhone into a story you can
> scroll through: your moments, your trips, the places you keep returning to. Add your own notes,
> keep your favorites, and revisit what you've lived together.
>
> YOUR STORY, ORGANIZED FOR YOU
> • A timeline of your relationship, built from your own photos
> • Moments, trips and places found automatically, with honest, factual titles
> • Today brings back memories from this day in earlier years
> • Your notes and favorites, always free
>
> MAKE SOMETHING TOGETHER
> • Collages and stories ready to share
> • Memory Movie: a short film edited from your memories
> • Memory Book: your moments as a book you can page through
> • Monthly Recap and Our Year: a look back, chapter by chapter
> • Made for You: a few creations prepared from your real memories
>
> PRIVATE BY DESIGN
> • Your photos are organized on your iPhone and never uploaded
> • No account, no ads, no tracking
> • Yuvi never identifies people and never invents feelings — it only says what your photos show
>
> FOR THE TWO OF YOU
> Connect with your partner through iCloud. Nothing from your library is shared by connecting.
>
> YUVI PREMIUM
> Your memories, moments, places, notes and favorites are always free, and your first creation is
> on us. Premium unlocks saving and sharing every creation, the full Monthly Recap and Our Year,
> and Memory Book export. Premium is an auto-renewing subscription, billed yearly or monthly
> through your Apple Account. It renews unless cancelled at least 24 hours before the end of the
> current period; manage or cancel it in your Apple Account settings.
>
> Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
> Privacy Policy: https://ardalmaz1.github.io/yuvi/privacy/

**Keywords (100, no spaces after commas)**

```
couple,relationship,memories,anniversary,timeline,photo album,love,collage,recap,partner,us
```

## App Privacy (nutrition label)

- "Do you or your third-party partners collect data from this app?" → **No, we do not collect
  data from this app.**
- Why this is true: photos and everything derived from them stay on the device; product events
  stay in a local log; purchases are handled by Apple; the partner connection's one record lives
  in the user's own iCloud private database, which the developer cannot access.
- The bundled `Relive/Resources/PrivacyInfo.xcprivacy` declares the same: no tracking, no
  collected data, and reasons for the required-reason APIs (UserDefaults `CA92.1`, disk space
  `E174.1`, file metadata `C617.1`).

## App Review information

**Sign-in required:** No.

**Notes for the reviewer:**

> Yuvi needs no account. On first launch, enter two first names, optionally a date, then either
> "Let Yuvi find them" (full photo access) or choose at least 5 photos yourself. Yuvi builds the
> story on the device; nothing is uploaded.
>
> Premium: the first creation is free. Make a collage (Create → Memory Collage), save it once,
> then save a second one to see the paywall. Products: relive.premium.annual and
> relive.premium.monthly.
>
> Partner connection (Us → Connect Your Partner) uses iCloud sharing and needs a second iPhone
> with a different Apple Account to complete; without it, you can start the connection and see
> the "Invitation sent" state. Connecting shares no photos.

Attach a short screen recording of the partner connection between two iPhones if review asks.
Review devices may have few photos: if the first launch looks empty, the notes above explain the
5-photo minimum.

## Screenshots

Required: 6.9-inch iPhone (1320 × 2868), 3 to 10 images. The other iPhone sizes are generated
from them.

Suggested order:
1. Story timeline — "Your story, from your own photos"
2. Today with a memory from this day — "Memories come back on their own"
3. A Monthly Recap chapter — "A month, told chapter by chapter"
4. Memory Movie or a collage — "Make something together"
5. Us with the partner connection — "For the two of you"
6. The privacy explanation — "Organized on your iPhone. Never uploaded."

Real photos of a couple make the strongest screenshots. The simulator's sample library is
synthetic (illustrated test scenes, no real people), so use a device with real photos you're happy to show, or
licensed stock photos, then capture with the side button + volume up.
