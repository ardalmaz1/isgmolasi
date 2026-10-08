# Commercial v1 — progress checkpoint

Branch `claude/compassionate-goldberg-rsn0w6`. If you resume this task, read this first, then
run `git status` and `git log --oneline -10`.

## Phases

| Phase | State |
|---|---|
| 0 Inspect | Done |
| 1 Free vs Premium model | Done (`PremiumCapability`, `PremiumPolicy` in ReliveCore) |
| 2 First free creation | Done (`FreeCreationAllowance`, persisted in UserDefaults by `PremiumStore`) |
| 3 Earned paywall | Done (`PaywallView`, opened only from keep/full-recap actions) |
| 4 Products | Done (`relive.premium.annual`, `relive.premium.monthly`; localized StoreKit prices) |
| 5 Entitlement layer | Done (`PremiumStore` + `StoreKitClient`: `LiveStoreKitClient`, `FakeStoreKitClient`) |
| 6 Gating | Done in code: collage, story, trend, book (page + Save Full Book), Monthly Recap, Our Year |
| 7 Badging | Done (Premium badge on recap teasers, sparkles on Save Full Book) |
| 8 Entry context | Done (`PaywallEntryPoint`, `PaywallCopy`) |
| 9 Restore | Done (paywall, Us tab, Us → Relive Premium) |
| 10 Errors | Done (`StoreFailure`, retry state, pending/cancel/unverified) |
| 11 Future capabilities | Done (reserved capabilities) |
| 12 Analytics | Done (event names in ReliveCore) |
| 13 App Store UX | Done (disclosure, trial only if StoreKit reports eligibility) |
| 14 Accessibility | Done in code; needs a VoiceOver pass on device |
| 15 Persistence | Done |
| 16 Tests | Done: core +18, hosted +14, UI +1 (`CommercialUITests`) |
| 17 StoreKit config | Done (`StoreKit/Relive.storekit`, placeholder prices; select it in the scheme to use) |
| 18 Design polish | Done; screenshots M01–M09 reviewed from CI |
| 20 Final report | Done |

## Test results (CI run 37849218391, commit b919585)

- ReliveCore (Linux): 271 passed.
- Builds: Xcode 16.4 and Xcode 26 both succeeded.
- Hosted tests: 95 passed (14 new).
- UI tests: 7 passed (1 new), with screenshots M01–M09.

## Bugs found and fixed along the way

- Two of Relive's own type names (`SubscriptionPeriod`, `SubscriptionRenewalState`) clashed
  with StoreKit's. `StoreKitClient.swift` now writes every core type as `ReliveCore.…`.
- An accessibility identifier on the paywall's container overrode its buttons' own identifiers.

## Still required outside the code

- App Store Connect setup (see `docs/COMMERCIAL.md`).
- A privacy policy URL in `CommercialLinks.privacyPolicy`.
- A sandbox purchase pass on a physical device.

## Next action

Commercial v1 is complete. Next: a physical-device sandbox test of purchase, restore and
refunds, then App Store Connect configuration.
