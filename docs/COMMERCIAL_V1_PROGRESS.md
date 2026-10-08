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
| 16 Tests | Core done (18 new). Hosted and UI tests: in progress |
| 17 StoreKit config | Pending |
| 18 Design polish | Done in code; screenshots pending |
| 20 Final report | Pending |

## Test results so far

- ReliveCore (Linux): 271 passed.
- App sources parse; type-checking and simulator results come from CI.

## Next action

Add the hosted tests (`ReliveTests/PremiumAppTests.swift`) and the UI test
(`ReliveUITests/CommercialUITests.swift`), the StoreKit configuration file, and
`docs/COMMERCIAL.md`. Then get CI green.
