# Couples Architecture — optional two-person Relive

Status: **proposal for product review. Nothing here is implemented.** Platform facts are marked
✅ (confirmed in Apple documentation), ⚠️ (documented but needs a device test), or ❓ (not
confirmed — must be tested before we rely on it).

## 1. Principles

1. Relive keeps working perfectly for one person. Everything below is opt-in.
2. **My Library** (on my iPhone) and **Our Relive** (what either of us chose to share) are
   separate layers. Connecting never shares a library.
3. Sharing is explicit, item by item, with a preview, and reversible where the platform allows.
4. Intelligence stays local. What crosses devices is a small, chosen representation — never
   fingerprints, face counts, or the library.
5. Apple-native: CloudKit. No third-party backend.

## 2. What the repository looks like today

| Fact | Consequence |
|---|---|
| One app target (`app.relive.prototype`), **no entitlements file**, no extensions | CloudKit, App Groups, push and a widget each need new capabilities, new targets and **signing changes on your Mac** (your team, your provisioning profiles). I must not change those unasked. |
| SwiftData, local only; schema written "CloudKit-compatible" | Good — but we should **not** mirror this store to iCloud: it holds the whole selection's metadata. The shared layer is a separate, small store. |
| `StoryRepository` protocol, `StoryStore` `@MainActor` | The shared layer becomes a sibling (`SharedRelationshipStore`), not a change to `StoryStore`. |
| `GeoCoordinate.placeLookupKey` (2-decimal grid ≈ 1 km) | Reusable as the coarse location for sharing. |
| `PlaceName` from on-device reverse geocoding | Shareable as a label ("Kaş, Antalya") without coordinates. |
| `MemoryAsset.location` = exact capture coordinate | Must never leave the device as is. |
| Analytics are local and identifier-free | Partner events must stay identifier-free too. |
| Minimum iOS 18 | `CKSyncEngine` (iOS 17+), interactive widgets (iOS 17+), App Intents all available. |

## 3. Layered architecture

```
LOCAL INTELLIGENCE (unchanged, on each iPhone)
  PhotoKit · Vision · Memory Engine · Moments · Places · Made for You · (future AI Director)
        │
        │  explicit user choice: "Share with Kübra" (preview → Send)
        ▼
SHARE COMPOSER (local)  ─ makes the shareable representation:
  1600-px HEIC/JPEG, EXIF/GPS stripped · capture date · place label · optional coarse cell ·
  optional note · sender
        │
        ▼
CLOUDKIT SHARED LAYER  (one custom zone "Relationship", owned by the inviter, zone-wide CKShare,
  exactly one other participant)
        │  CKSyncEngine (both devices) · database subscriptions → silent push
        ▼
LOCAL SHARED CACHE (each iPhone)  ─ SwiftData store "Shared.store" + image files, in the App
  Group container so the widget can read a safe snapshot
        │
        ▼
PARTNER EXPERIENCES  Today · Story · Our Places · Notes · Widget · (later) Made for You
```

Why this shape: it keeps the existing app untouched where it matters (the private store, the
engine) and adds one layer with one job — moving *chosen* things between two people.

## 4. CloudKit feasibility

| Requirement | CloudKit | Notes |
|---|---|---|
| Two participants | ✅ Shares support up to 100 participants; **we enforce exactly one** invitee in app logic (refuse a second acceptance, show "already connected"). | Apple has no "max participants" setting — the limit is ours. |
| Invitation | ✅ `CKShare` URL, sent via `UICloudSharingController` or our own `ShareLink` with the share URL. | Invitee must be addressed (participant lookup) or the share made "anyone with link" — use **addressed, private** shares. |
| Acceptance | ✅ `CKSharingSupported` in Info.plist; system delivers `CKShare.Metadata` to the scene delegate; app calls `accept`. | Works from Messages/Mail link tap. |
| Shared memories, notes, references | ✅ records in the shared zone | |
| Photos | ✅ `CKAsset` fields | Counted against the **owner's** iCloud quota (see §9). |
| Read state / reactions (later) | ✅ small records | |
| Deletion | ✅ delete records | Received copies already cached on the other phone stay until the sync engine applies the deletion (it will, on next fetch). |
| Revoke | ✅ owner removes participant or deletes the share; participant can leave. | |
| Reconnect / reinstall / new device | ✅ data lives in iCloud; `CKSyncEngine` re-fetches. | Local cache rebuilds; local intelligence does not depend on it. |
| Offline | ✅ `CKSyncEngine` queues pending changes. | |
| Conflicts | ✅ server-change-tag errors surfaced by the engine | Our records are mostly **append-only, author-owned** — conflicts are rare by design (§6). |
| Live updates | ✅ `CKDatabaseSubscription` on the shared/private DB, silent push (`content-available`). | Pushes are hints, coalesced; always fetch changes. Query subscriptions are not available in the shared DB. |

**Owner vs participant.** The inviter creates the zone in *their private database* and shares it
zone-wide. The partner sees it in *their shared database*. Both can write (permission
`readWrite`). Only the owner can delete the share. Decision for the product owner: what happens
to everything when the **owner** disconnects (see the privacy model).

⚠️ One public forum report describes a zone-wide share whose zone disappeared after acceptance
when the share was public (`publicPermission = .readWrite`, no participants). We use a private,
addressed share — but the invite/accept flow must be device-tested early (Phase B).

## 5. Record model (shared zone "Relationship")

| Record type | Fields | Written by | Notes |
|---|---|---|---|
| `Relationship` | `createdAt`, `schemaVersion`, `ownerDisplayName`, `participantDisplayName` | owner | one per zone; names as each person typed them, not Apple IDs |
| `Member` | `role` (owner/partner), `displayName`, `joinedAt`, `sharesLocations` (Bool) | each person, own record | the per-person switches the other side must respect |
| `SharedMemory` | `sender` (member ref), `createdAt`, `capturedAt` (date), `capturedDay` (Y-M-D), `placeLabel` (String?), `coarseCell` (String?, only if sender allows), `caption` (String?), `image` (CKAsset), `imagePixelSize`, `kind` (photo/moment), `momentGroup` (UUID?, groups several photos of one moment), `revoked` (Bool) | sender | never contains `localIdentifier`, fingerprints, faces |
| `Note` | `sender`, `createdAt`, `text` (≤ 280), `refMemory` (ref?), `refPlace` (String?), `deletedAt?` | sender | not a thread: no reply-to |
| `EventSummary` (Phase G) | `sender`, `start`, `end`, `placeLabel`, `coarseCell?`, `photoCount` | sender | opt-in; for "you both captured this" |
| `Seen` (optional) | `memory` ref, `seenAt` | receiver | only if read state is approved |

`CKShare` record: zone-wide (`CKRecordNameZoneWideShare`).

Private database (each person, not shared): nothing new — Relive's private data stays in the
local SwiftData store, not in iCloud.

### Ownership rule
Every record is edited only by its sender (except `Seen`). This removes most conflicts: the only
true conflict is "sender deletes while receiver marks seen" → deletion wins.

## 6. Sync, offline, retry, conflicts

- `CKSyncEngine` per database (owner: private DB zone; partner: shared DB). It persists its own
  state; we store that state blob in the shared cache.
- Writes are queued locally first (the item appears at once in "Our Relive" as *Sending…*), then
  sent. Failures: retry with the engine's back-off; after a permanent error (quota, account
  change) the item shows "Couldn't send — Try Again / Remove".
- Conflicts: server record wins for others' records; for own records, re-apply the local edit on
  top (`serverRecordChanged`).
- Account change (`CKAccountChanged`): pause the shared layer, clear the shared cache only after
  confirming the account really changed — never touch the private library data.

## 7. Invitation & connection flow

1. Us → "Connect with your partner" (new section; hidden until the user taps it).
2. Explain screen: what is shared (only what you choose), what never is, that it uses iCloud.
3. iCloud check: signed in? iCloud Drive / CloudKit available? If not → explain and stop (Relive
   keeps working alone).
4. Create zone + share → `UICloudSharingController` or a Relive "Send invitation" sheet with the
   share link (Messages / AirDrop / copy).
5. Partner taps the link → Relive opens (or App Store) → accept screen: "Arda ♥ you — connect?"
   → Accept → shared zone appears.
6. Both see "Connected with Kübra" in Us. First Today card: "You're connected. Share a memory
   when you find one."

Single-partner enforcement: a share with `publicPermission = .none` is meant to admit only the
addressed participant ⚠️ (to be confirmed on device with a forwarded link); Relive also refuses a
second `Member` record either way.

## 8. Shared memory representation & image transfer

`localIdentifier` is device-bound ✅; `PHCloudIdentifier` only maps within *the same* iCloud
Photos library ❓ (Apple says "any iCloud-synced device"; nothing suggests it works across two
Apple IDs). So **the image itself must travel**.

Default representation ("Relive quality"):

| | Value |
|---|---|
| Long side | 1600 px (sharp on any iPhone screen, ≈ 300–600 KB HEIC) |
| Format | HEIC (JPEG fallback) |
| Metadata | **all EXIF/GPS stripped**; capture date and place sent as fields we control |
| Live Photos / videos | not in V1 (stills only); videos later, opt-in, capped |
| Original quality | only on explicit "Send original" (Phase C+, owner decision) |

Received images live in the App Group container (`Shared/Images/<recordName>.heic`), are never
saved to Photos automatically; "Save to Photos" is an explicit action (uses the existing
`PhotoLibraryService` save path and is then recorded in `createdAssetIDs` so it never comes back
as a "memory" import).

## 9. iCloud storage — a real constraint ⚠️

Records and assets in a shared zone count against the **owner's** iCloud quota ✅ (Apple: shared
database records "are counted towards the originating owner's iCloud account storage quota").

- 1,000 shared photos × ~450 KB ≈ 450 MB on the inviter's iCloud. Many people have 5 GB free tier
  that is already full.
- If the owner's iCloud is full, writes into the shared zone fail — **for both people** ❓ (what
  the participant sees is not documented; must be tested).

Options (owner decision):
- **A.** Accept it, show clear errors, and keep image sizes modest (recommended for V1).
- **B.** Each person owns a zone for what *they* send (two shares, each owner pays for their own
  sends). Fairer, more complex (two shares to accept, two zones to sync).
- **C.** A backend with our own storage — contradicts "Apple-native, no account".

## 10. Widget

### What iOS actually allows ✅
- Widgets render SwiftUI from a **timeline**; they cannot run arbitrary code, play video, scroll,
  or take text input.
- Interactive widgets (iOS 17+): `Button(intent:)` / `Toggle` run an **App Intent** in the
  widget's process. An intent can do a small background action (e.g. "Send ❤️") but **cannot show
  a keyboard or a photo picker**.
- So "Note / Photo / Memory" buttons must **open Relive** to a composer (`openAppWhenRun`, or a
  `Link`/`widgetURL` deep link): `relive://compose/note`, `relive://compose/photo`,
  `relive://compose/memory`.
- Refresh: a budget of roughly 40–70 reloads/day for a frequently viewed widget ✅; reloads
  triggered by the app in the foreground or by the widget's own intent don't count ✅.
  `WidgetCenter.reloadTimelines` is best-effort.
- iOS 18 also offers widget push updates (APNs `widgets` push type) ⚠️ — requires our own push
  sender (server). Not available through CloudKit subscriptions. Out of scope for V1.

### Sync path (validated against the constraints)
```
CloudKit change → silent push (database subscription)
  → iOS may wake Relive in the background (not guaranteed: Low Power, force-quit, budget)
  → CKSyncEngine fetches → shared cache updated
  → WidgetSnapshot.json + one 600-px image written to the App Group
  → WidgetCenter.reloadTimelines(ofKind: "Partner")
Widget timeline provider reads only WidgetSnapshot.json (never the database)
```
If the background wake doesn't happen, the widget updates the next time Relive runs or at its
next scheduled timeline refresh. **The widget can be stale; we say "Shared 2 h ago" rather than
pretend it's live.**

### Privacy when locked ✅
- `.privacySensitive()` on the note text and photo → iOS redacts them when the user has chosen to
  hide sensitive content / when locked, depending on system settings.
- Or the widget extension's Data Protection entitlement (`NSFileProtectionComplete`) → placeholders
  until unlocked after restart.
- Relive setting: **"Show shared photos in widgets when locked"** (default **off** → photo and
  note redacted on the Lock Screen and when locked).

### Designs
- **Small:** latest from partner — photo (or note text on paper background), "From Kübra ·
  2 h ago". Tap → opens that item. No buttons (too small for three targets).
- **Medium:** header "Arda ♥ Kübra", latest item left, right column of three 44-pt buttons:
  Note · Photo · Memory (each deep-links to a composer). Empty state: "Nothing shared yet —
  share a memory".
- **Lock Screen (accessoryRectangular):** only "Kübra shared something" + time; never the photo.
  Optional, low priority.

## 11. Notifications

| Event | Delivery | Text (locked) |
|---|---|---|
| Memory shared | CloudKit database subscription push → app (background) posts a local notification after fetching | "Kübra shared a memory" (no caption, no image unless setting allows) |
| Note | same | "A note from Kübra" (text only if "Show previews" allows) |
| Invitation accepted | same | "Kübra joined your Relive" |
| Shared event found (Phase G) | local, once | "You both captured Kaş" |

⚠️ Background wake from a silent push is not guaranteed. Fallback for reliability: the
subscription's `notificationInfo` carries a **static visible alert** ("Something new in Our
Relive") so the receiver is always told, and the app enriches it with a Notification Service
Extension (`shouldSendMutableContent`) ❓ — that CloudKit sets `mutable-content` must be verified
on device. No reminder notifications, no "you haven't…" ever.

## 12. Our Places (shared map)

- Built only from `SharedMemory.placeLabel` + `coarseCell` (≈ 1 km grid from
  `placeLookupKey`), never exact coordinates.
- Each person's **own** local Places (exact, on device) stay private; on the map, my own pins
  may use my local precision, my partner's pins use their coarse cells.
- Pins are clustered by place label; tap → "Kaş · 34 shared memories · You and Kübra".
- Contributor shading: **You / Kübra / Both** — via a small legend, not per-pin badges.
- Home safety: before sharing a coarse cell, drop cells that match the sender's **most frequent
  location** (the engine already detects "home"-like everyday places) unless the user turns it on
  for that memory. ❓ precision of the existing home heuristic must be reviewed.
- MapKit annotations: cluster with `MKClusterAnnotation` / SwiftUI `Map` + `MapCircle` per
  cluster; cap at a few hundred annotations (one per place label, not per photo).

## 13. Two libraries, same event (Phase G)

Each device summarizes its own trips locally (the Memory Engine already builds chapters):
`EventSummary(start, end, placeLabel, coarseCell, photoCount)`. If **both** partners opted in,
summaries are exchanged; overlap = same place label (or neighbouring cells) and overlapping dates.
Then: "You both captured Kaş · Aug 3–6 — choose photos to add to Our Relive". Nothing is merged
automatically; no images, no fingerprints, no faces cross devices. Cost: O(trips A + trips B).

## 14. Today and Story

- Today hierarchy: Found for You (hero) → **From Kübra** (at most one card: the newest unseen
  shared memory, or a note) → Made for You → Continue → discoveries. Partner content never takes
  the hero, never more than one card, and disappears once seen (it stays in Our Relive).
- Story: shared memories from the partner appear as **a separate section per moment** only when
  they don't duplicate my own moment; if they fall into my existing moment (same day + place),
  they show under it as "+ 6 from Kübra" (one line, not per-photo badges). Duplicates: none to
  detect (we never have the partner's originals), but near-duplicates between my photo and a
  received 1600-px copy can be found locally with the existing fingerprint after the image
  arrives — local only.

## 15. Performance

- Nothing scales with library A × library B: only shared items (hundreds) and event summaries
  (tens) cross devices.
- Shared cache: images on disk (1600 px), thumbnails via the existing `PhotoImageLoader`-style
  memory cache; pagination by `createdAt`.
- Widget: one JSON + one ≤ 600-px image.
- Map: one annotation per place, not per photo.

## 16. Premium

Free: connecting, sending, receiving and viewing shared memories and notes, Our Places, the
widget. Premium (as today): exporting/saving creations; later, creations that **combine both
partners' contributions** (e.g. a two-perspective Memory Movie) could be Premium. Never: "Your
partner sent you a memory — pay to see it." One subscription covering both partners is a
product/StoreKit question (Family Sharing of the subscription is the Apple-native answer) —
owner decision.

## 17. AI Director compatibility

The Director will read: local intelligence (as today) + received shared items (images arrive as
files, so local Vision can analyze them on the receiver's phone). No fingerprints ever need to be
exchanged — each phone analyzes what it holds. Shared records carry dates/places, which is what
selection and titles need.

## 18. Phases (safest order)

| Phase | Scope | Affects | Risk | Needs device test |
|---|---|---|---|---|
| **A** (now) | Couple-name ♥ presentation; UI audit fixes | ReliveCore `CoupleName`, views, tests | Low | No |
| **B** | Capabilities (iCloud/CloudKit, App Group, push) — **on your Mac**; `SharedRelationshipStore`; zone + share; invite/accept; Us "Connect"; disconnect; iCloud-unavailable states | new target settings, new module `Shared/` | **High** (signing, CloudKit schema in production is append-only) | Yes — two Apple IDs |
| **C** | Share composer (preview → Send), `SharedMemory`, receive, Our Relive list, Save to Photos, delete/revoke | composer views, cache | Medium | Yes |
| **D** | Notes; notifications (subscriptions, local notifications, settings) | push entitlement | Medium | Yes |
| **E** | Widget extension (small/medium, deep-link composers, locked redaction setting) | new extension target, App Group | Medium | Yes |
| **F** | Our Places (coarse cells, map, legend, home safety) | MapKit view | Medium (privacy) | Yes |
| **G** | Event summaries & "you both captured this" | engine export, matching | Medium | Yes |

Complexity (rough, one engineer): B 1–2 weeks incl. device testing; C 1 week; D 1 week; E 1 week;
F 1 week; G 1 week.

CloudKit schema note: once deployed to the production environment, record types and fields can
be added but **not removed or renamed** — the Phase B schema must be reviewed before deploying.

## Sources

- [CKShare (Apple)](https://developer.apple.com/documentation/cloudkit/ckshare)
- [Shared database scope (Apple)](https://developer.apple.com/documentation/cloudkit/ckdatabase/scope/shared)
- [CKDatabaseSubscription (Apple)](https://developer.apple.com/documentation/cloudkit/ckdatabasesubscription)
- [CKRecordZoneSubscription (Apple)](https://developer.apple.com/documentation/cloudkit/ckrecordzonesubscription)
- [PHCloudIdentifier (Apple)](https://developer.apple.com/documentation/photos/phcloudidentifier)
- [Keeping a widget up to date (Apple)](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- [Apple Platform Security — widgets and data protection](https://support.apple.com/guide/security/secbb0a1f9b4/web)
- [WWDC16 CloudKit best practices (notes)](https://mackuba.eu/notes/wwdc16/cloudkit-best-practices/)
- [Forum: zone deleted after zone-wide share acceptance](https://developer.apple.com/forums/thread/822913)
- [Forum: CKShare storage ownership and quota](https://developer.apple.com/forums/thread/851999)

## 19. Phase B status — partner connection (implemented)

Simulator and unit tests only. **Nothing below is validated on physical devices yet**; the
two-iPhone procedure is in `COUPLES_DEVICE_TEST_PLAN.md` § Phase B.

### What is implemented

| Layer | Where | What |
|---|---|---|
| Rules and states | `ReliveCore/Partner/PartnerConnection.swift` | `PartnerConnectionState`, `CloudFailure`, `PartnerMessage` (calm words), `TwoPersonRule`, `PartnerConnectionRecord` (local memory), `RelationshipCloudFields` (the iCloud allowlist). Foundation only, tested on Linux. |
| Service boundary | `Relive/Partner/PartnerCloudService.swift` | Protocol; every method throws `CloudFailure`, never a CloudKit error. Views never import CloudKit. |
| CloudKit | `Relive/Partner/CloudKitPartnerService.swift` | The only file that talks to CloudKit (plus the delegates that receive invitations). |
| Model | `Relive/Partner/PartnerConnectionModel.swift` | `@Observable` state for Us; `PartnerInbox` buffers invitations that arrive before the model. |
| Local memory | `Relive/Partner/PartnerConnectionCache.swift` | `Application Support/Relive/PartnerConnection.json`, file protection until first unlock, excluded from backup. |
| Acceptance | `Relive/App/ReliveAppDelegate.swift` | App delegate (`UIApplicationDelegateAdaptor`) installs a scene delegate: `scene(_:willConnectTo:options:)` reads `connectionOptions.cloudKitShareMetadata` (cold launch); `windowScene(_:userDidAcceptCloudKitShareWith:)` (running or returning to foreground). Silent pushes: `application(_:didReceiveRemoteNotification:)`. |
| UI | `Relive/Partner/PartnerViews.swift` | Us → "Your partner" section, the explanation sheet, partner settings with the disconnect confirmation, one-off alerts. |
| Info.plist | `Config/Info.plist` | `CKSharingSupported = YES` (required for iOS to hand invitations to Relive). Entitlements unchanged. |

**Design choices (and where they differ from §5–§7 of this document):**

- **Direct CloudKit calls, not `CKSyncEngine`.** Phase B reads one share and writes one record; a
  sync engine adds state to persist for no benefit yet. Phase C (shared memories) should adopt
  `CKSyncEngine` for the shared database.
- **No names in iCloud, no `Member` records.** §5 proposed `ownerDisplayName` /
  `participantDisplayName`. Phase B keeps names local: each iPhone shows the couple name its user
  typed ("Arda ♥ Kübra"), and nothing about a person is written to iCloud. CloudKit identity
  (the share's participants) is used only for the two-person rule. If Phase C needs the partner's
  own spelling of the names, add it then, with its own allowlist entry.
- **No `ownerUserRecordID` field.** The share already knows its owner; the partner's iPhone keeps
  the zone's owner name locally (`zoneOwnerName`) to find the relationship again.
- **One zone per relationship** named `Relationship-<UUID>` in the owner's private database, shared
  as a **zone-wide share** (`CKShare(recordZoneID:)`, record name `CKRecordNameZoneWideShare`), so
  Phase C records added to the zone are shared automatically.

### CloudKit schema (Development environment)

| Record type | Fields | Indexes |
|---|---|---|
| `Relationship` | `relationshipID` (String), `createdAt` (Date/Time), `schemaVersion` (Int64, = 1) | none needed: fetched by record ID, never queried |
| `cloudkit.share` | system type | — |

Record name of `Relationship` = the relationship ID. In the Development environment CloudKit
creates the record type on the first save from a development-signed build ("just-in-time"
schema). Production never does this.

### Subscriptions

One `CKDatabaseSubscription`, ID `relive-relationship-changes`, `shouldSendContentAvailable = true`
and no alert, badge or sound — **silent only**:

- owner: on the private database; partner: on the shared database;
- saved when a relationship is created or joined (and harmlessly re-saved);
- the app registers for remote notifications only when a relationship exists. Silent pushes need
  no permission prompt, and Relive never asks for notification permission in Phase B;
- on a push Relive refreshes the connection (`PartnerConnectionModel.cloudDidChange`). It also
  refreshes whenever it becomes active, so a missed push only delays an update. Silent pushes are
  best-effort and throttled by iOS.
- `UIBackgroundModes = remote-notification` was already set by the product owner. Background
  Fetch is **not** needed and was not added.

### Lifecycle in CloudKit terms

| Action | Owner's iPhone | Partner's iPhone |
|---|---|---|
| Connect | zone + `Relationship` record + share saved atomically; Apple's `UICloudSharingController` sends the invitation | — |
| Accept | — | `CKContainer.accept(_:)` with the system's `CKShare.Metadata`; refused before calling if another person already accepted (`TwoPersonRule.mayAccept`) |
| Refresh | fetches the share: owner + 1 accepted → connected; partner removed or left → the relationship ends and its zone is deleted | fetches the share from the shared database; missing → ended |
| Owner disconnects | deletes the zone (and with it the share and the record) | access ends; on next refresh: "Your partner ended the connection." |
| Partner leaves | — | deletes the share record from its shared database (CloudKit removes the participant); nothing in the owner's zone is deleted by the partner |
| Owner stops sharing in Apple's screen | share deleted, zone left → Relive deletes the zone on the next refresh | as owner disconnect |

### Mocked in tests

`FakePartnerCloudService` (DEBUG only) replaces CloudKit in hosted tests and UI tests
(`-RelivePartnerFake noAccount|available|waiting|connected|partner`). Apple's sharing screen,
`CKContainer.accept`, subscriptions, pushes and real CloudKit errors are **not** exercised by CI —
only the CKError → `CloudFailure` mapping is.

### Needs physical devices and two Apple IDs

Everything that crosses iCloud: sending and accepting the invitation, cold/warm acceptance,
silent pushes, the two-person rule against a forwarded link, owner/partner disconnect as seen from
the other phone, account sign-out. See the device test plan.

### Development vs Production — release checklist

- Builds run from Xcode (development signing, `aps-environment = development`) use the CloudKit
  **Development** environment. **TestFlight and App Store builds use Production.**
- Before the first TestFlight build that uses partner connection: in CloudKit Console, open
  `iCloud.com.ardaalmaz.reliveapp` → *Deploy Schema Changes* to Production, after the
  Development schema contains `Relationship` (create it by connecting once from a development
  build). Without this, saving a `Relationship` record fails in TestFlight.
- Production record types and fields **can't be deleted or renamed** later — only added. Review
  the schema (three fields) before deploying.
- Never reset the Production environment. Resetting Development is safe and deletes test data.
- App Store distribution signing sets `aps-environment` to production; no manual change needed.

### Found and fixed: the story store was set to mirror to iCloud ⚠️

Adding the iCloud/CloudKit capability (commit `af9ba35`) silently changed SwiftData's default:
a `ModelConfiguration` without `cloudKitDatabase` uses `.automatic`, which mirrors the whole local
store (photo identifiers, analysis, hidden memories, notes) to the first iCloud container in the
entitlements. CI logs showed `NSCloudKitMirroringDelegate` starting (it failed only because the
simulator has no iCloud account). Phase B sets `cloudKitDatabase: .none`
(`SwiftDataStoryRepository.storeConfiguration`) and a hosted test checks it.

**Product-owner action:** if any build from `af9ba35` up to this fix ran on an iPhone signed in to
iCloud, open CloudKit Console → `iCloud.com.ardaalmaz.reliveapp` → **Development** → Private
Database (signed in as that Apple ID) and look for the zone `com.apple.coredata.cloudkit.zone`
and `CD_…` record types. If present, delete that zone (or reset the Development environment,
which deletes only development data) **before** deploying any schema to Production — otherwise
`CD_…` record types would be deployed permanently.

### Known limitations

- Account change: if a different Apple ID signs in, the owner's relationship is not visible and
  Relive reports the connection ended and forgets it locally; signing back in to the original
  account does not restore it automatically (the zone still exists in that account's iCloud).
  Signed-out (no account) keeps the connection remembered.
- The partner's name is the one each user typed; Relive doesn't learn it from iCloud.
- If the partner leaves while the owner's iPhone is offline for a long time, the owner sees
  "connected" until the next successful refresh.
- Dismissing Apple's sharing screen without changes is not reported by iOS; the state refreshes
  the next time Relive becomes active.
- Start Over keeps the partner connection (it erases the story, not the relationship).
- The bundle identifier changed to `com.ardaalmaz.reliveapp`: it is a new app to iOS, so data in
  earlier TestFlight installs (`app.relive.prototype`) does not carry over.
- Shared data counts against the **owner's** iCloud storage (Phase B writes one tiny record).
