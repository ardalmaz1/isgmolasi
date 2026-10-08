# Commercial v1 — Relive Premium

> Memories are free. Creating more from them is Premium.

## What's free and what's Premium

| Free, always | Premium |
|---|---|
| Today, Story, Us; every memory, moment and place; dates, places, notes; hidden memories; favorites; adding memories | Unlimited collage, Story Maker and trend saves/shares (after the first free one) |
| Making, editing and previewing collages, stories, trends and Memory Books, in every design | Saving or sharing Memory Book pages, and **Save Full Book** |
| Reading a whole Memory Book, page by page | The full Monthly Recap: every highlight, its trips, a collage or story from the month, the shareable card |
| Monthly Recap list with counts; each recap's counts, first highlights and every moment | The full Our Year: every month, the closing, a story or collage of the year, the shareable card |
| Our Year's cover, counts, first memory and first month | Future: Made for You, Memory Movie, Relive AI, anniversary creations (capabilities already reserved) |
| **The first creation to save or share** (collage, story or trend) | |

Premium is never needed to see a memory, a moment, a place, a note or a favorite. None of these
is a `PremiumCapability`, so they can't be gated by mistake.

Every design is previewable and usable for the free creation. After that every keep action needs
Premium anyway, so there is no separate per-design gate. `PremiumCapability.premiumStyles`
is reserved for when the product decides some designs are Premium-only.

Exports are the same quality for everyone; the free creation is a real, full-quality output.

## The first free creation

- The first **successful** save or share of a collage, story or trend is free.
- Previews, editing and failed exports don't count. A share only counts if the share sheet
  completed.
- It is recorded once (`FreeCreationAllowance`) in UserDefaults
  (`relive.commercial.freeCreation`). It survives backgrounding, relaunching and Start Over.
  Deleting the app resets it.
- Memory Book exports and recap cards don't use it; they need Premium.

## When the paywall appears

Only when the user tries to keep something they have already seen, or opens the full recap:

| Entry point | Trigger | Context line |
|---|---|---|
| `collageExport` | Save/Share after the free creation | Create without limits |
| `storyExport` | Save/Share after the free creation | Keep every story |
| `trendExport` | Save/Share after the free creation | Create without limits |
| `memoryBook` | Save Page, Share Page, Save Full Book | Keep this book |
| `monthlyRecap` | "See the Full Recap", Share | See the whole month |
| `ourYear` | "Relive Your Full Year", Share | Relive your full year |
| `settings` | Us → Relive Premium → See Relive Premium | — |

There is no paywall at launch, after onboarding, or in Today, Story or Us. Closing it returns to
exactly where the user was, with nothing exported. If the user subscribes from the paywall, the
action they were taking (for example, Save Full Book) finishes when the paywall closes.

### Paywall content

- Header: "Keep making memories worth keeping".
- Message: "Your memories are always yours. Premium gives you everything Relive can create from
  them."
- Benefits: Unlimited Memory Books · Stories, Collages & future Movies · Monthly and yearly recaps ·
  Every premium design · Full-quality exports.
- Plans: Annual (selected, marked "Recommended") and Monthly. Both show the App Store's localized
  price and period.
- Button: "Start Free Trial" **only** if StoreKit reports an introductory free trial *and* the
  user is eligible. Otherwise "Continue with Annual" or "Continue with Monthly".
- Disclosure: plan, price and period, what the trial is (if any), automatic renewal, and how to
  cancel.
- Footer: Restore Purchases, Terms, Privacy.
- The close button is always visible.
- There's no countdown, timer, urgency or pre-checked upsell.

The optional photo at the top is a thumbnail from what the user was making. It's loaded on the
device like every other photo in Relive and never uploaded.

## Architecture

```
ReliveCore/Premium                           (Foundation only, tested on Linux)
  PremiumCapability, PremiumPolicy           what's gated; export decision
  FreeCreationAllowance                      the one free creation
  EntitlementResolver                        Premium from verified StoreKit data only
  PaywallEntryPoint, PaywallCopy, PaywallText  copy, plan lines, CTA, disclosure

Relive/Premium
  StoreKitClient (protocol)                  products, purchase, entitlements, sync, updates
    LiveStoreKitClient                       StoreKit 2
    FakeStoreKitClient                       tests and UI tests (-ReliveStoreKit free|premium|trial|unavailable)
  PremiumStore (@Observable, one per app)    status, products, purchase/restore state, allowance
  PremiumGate (one per screen)               asks before keeping; shows the paywall; finishes after purchase
  PaywallView, PremiumSettingsView, PremiumBadge, PremiumTeaser
```

- **Single source of truth.** `PremiumStore` is created once in `AppEnvironment` and injected
  with `.environment`. No screen talks to StoreKit.
- **Verified only.**
  - A transaction counts only if StoreKit verified it and it is unrevoked, not upgraded and not
    expired.
  - A verified status in Apple's billing grace period keeps Premium. Billing retry, expired,
    revoked and unverified never grant it, and the settings screen says why, calmly.
- **Live updates.**
  - `PremiumStore.start()` listens to `Transaction.updates` (finishing verified transactions) and
    re-checks on every return to the foreground.
  - A purchase on another device, an Ask to Buy approval, a renewal or a refund changes the UI
    while the app runs.
- **Cache.** The last known Premium value is kept only so badges and recaps don't flicker at
  launch (`showsPremium`). Every export waits for a fresh verified check (`exportDecision`).
- **Restore.** `AppStore.sync()`, then a re-check. It reports "active again", "no active
  subscription found", or the error. It never claims success it didn't have. It's on the
  paywall, in Us, and in Us → Relive Premium.
- **Errors.**
  - Covered: offline, StoreKit unavailable, products failing to load, purchase not allowed,
    product unavailable, cancelled, pending, and an unverified result.
  - Each has plain words and a way forward. Prices never load means a retry state, never made-up
    prices.
  - Nothing locks the archive.
- **Future features.** Add a `PremiumCapability` case and gate with `premium.hasAccess(to:)` or
  `gate.export(...)`. The StoreKit layer doesn't change.

## Analytics (local log only)

Events are emitted through `AnalyticsTracking`, which today logs them to the device's unified log
only:

- `paywall_viewed`, `paywall_closed`
- `premium_purchase_started`, `premium_purchase_completed`, `premium_purchase_cancelled`,
  `premium_purchase_pending`, `premium_purchase_failed`
- `premium_restore_started`, `premium_restore_completed`
- `free_export_used`, `premium_feature_tapped`

Properties are limited to entry point, feature/capability, product role, and result. They never
include photos, notes, names, captions or places.

## Testing without the App Store

- **Unit (Linux):** policy, free creation, entitlement resolution, and paywall wording.
- **Hosted tests:** `PremiumStore`, `PremiumGate` and `ExportController` with
  `FakeStoreKitClient`.
- **UI tests:**
  - Launch with `-ReliveStoreKit free|premium|trial|unavailable` (DEBUG builds only).
  - Existing UI tests run as `premium`, so their flows are unchanged.
  - `CommercialUITests` covers the free path, the paywall, the purchase and Premium.
- **Running from Xcode:**
  - `StoreKit/Relive.storekit` holds both products with **placeholder** prices ($39.99/year with
    a 1-week free trial, $4.99/month).
  - To use it, choose Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration →
    `Relive.storekit`. It isn't preselected, so CI and TestFlight are unaffected.
  - Without it, Debug builds talk to the sandbox.

## App Store Connect setup (still required)

1. **Agreements:** sign the Paid Applications agreement; add banking and tax details.
2. **Subscription group:** create one group, e.g. "Relive Premium". Both products must be in the
   same group so switching is an upgrade/downgrade, not a second subscription.
3. **Products** (auto-renewable subscriptions):
   - `relive.premium.annual` — duration 1 year, group level 1 (the highest service level).
   - `relive.premium.monthly` — duration 1 month, group level 2.
   - Set prices per storefront. The app shows whatever App Store Connect returns.
4. **Introductory offer** (optional): a free trial on the annual product, e.g. 1 week, for new
   subscribers. The app shows trial wording only when StoreKit reports this offer *and* the user
   is eligible. Without it, the button reads "Continue with Annual".
5. **Localization:** for each product and the group, give a display name and description (e.g.
   "Relive Premium Annual" — "Everything Relive creates from your memories."), in every language
   the app supports.
6. **Review information:** a screenshot of the paywall for each product (any simulator
   screenshot of `PaywallView`, e.g. `M02-paywall-collage`, works) and review notes. Example
   notes: "Premium unlocks saving/sharing creations after the first free one, full Monthly Recap,
   full Our Year and Memory Book export. Make a collage, save it once (free), then save again to
   see the paywall."
7. **App metadata:**
   - The privacy policy URL is required for apps with subscriptions.
   - Use Apple's standard EULA, or a custom one, as Terms of Use.
   - Mention the auto-renewing subscription in the description.
8. **In the code before submission:**
   - Set `CommercialLinks.privacyPolicy` to the published URL. Until then the paywall's Privacy
     link opens the in-app privacy summary.
   - Change `CommercialLinks.termsOfUse` if you use a custom EULA.
9. **App Privacy (nutrition label):** purchases are handled by Apple. Relive collects no data
   off-device, and the analytics above stay in the local log.
10. **Sandbox testing:** create Sandbox Apple Accounts, then test buy, cancel, Ask to Buy
    (pending), restore on a second device, refund (revocation), billing retry and grace period
    (enable Billing Grace Period in App Store Connect if wanted).

## Known limitations

- Purchases have not been made against the live App Store or sandbox in CI. They're verified
  with the fake client and the entitlement rules. A sandbox pass on a device is required.
- `manageSubscriptionsSheet` (Manage Subscription) only works against the real App Store or
  sandbox.
- Offer codes, promotional offers, win-back offers and Family Sharing aren't configured. The
  entitlement rules accept any verified transaction for the two product IDs, so a family-shared
  subscription would count if enabled.
- The free creation lives in UserDefaults: deleting and reinstalling the app gives a new one.
  That's a deliberate, low-stakes choice — no account and no server.
