# Couples Privacy Model

Status: proposal for product review; not implemented. Companion to
[COUPLES_ARCHITECTURE.md](COUPLES_ARCHITECTURE.md). ✅ confirmed in Apple docs, ⚠️ needs a device
test, ❓ unconfirmed.

**The promise:** Relive never shares your library. It shares only what you choose, one item at a
time, after you've seen what will be sent. It never shares where you are.

## 1. Data classes

### Local only — never leaves this iPhone

| Data | Where today |
|---|---|
| The Photos library and the selection | PhotoKit, `StoredAsset` |
| PhotoKit local identifiers | `MemoryAsset.localIdentifier` |
| Vision analysis: fingerprints, face counts, sharpness, aesthetics, utility flag | `AssetAnalysis` |
| Moments, trips, places built by the engine | `StoredStorySnapshot` |
| Exact capture coordinates | `MemoryAsset.location` |
| Hidden memories, "Don't show this again", "Don't Suggest" | `StoredMomentState`, `StoredSuggestionExclusion` |
| Notes on moments (the existing private notes) | `StoredMomentState.note` |
| Favorites, drafts, creations, books | local stores |
| Made for You history, recap/movie plans, editorial choices | local |
| Analytics events (codes and counts only) | local log |

Connecting a partner changes none of this.

### Shared only when explicitly chosen

| Data | When | Form |
|---|---|---|
| A photo | "Share with Kübra" → preview → Send | 1600-px copy, **EXIF/GPS stripped** |
| Its capture date | with the photo | day + time, as a field |
| Its place | with the photo, if "Include place" is on for that send | label ("Kaş, Antalya") |
| Its coarse location | only if the sender has "Share photo locations" on | ≈ 1 km cell, never the coordinate; home-like cells withheld by default |
| A caption / note | typed by the sender | text ≤ 280 |
| A creation reference | "Share this collage/movie" | the rendered image/video file the sender chooses, not its source photos |
| Display name | at connection | the name each person typed |
| Event summaries (Phase G) | only if **both** turned on "Find trips we both captured" | place label, date range, photo count |

### Never shared — no setting can turn these on

Complete library · hidden memories · Don't-Suggest memories · Vision fingerprints · face
analysis · any biometric data · private AI metadata · the device's current or live location ·
background location · contacts · analytics.

## 2. Location

- PhotoKit gives each asset a `CLLocation` (coordinate, altitude, accuracy) when the camera
  recorded one ✅; Relive already reads it only from the selection.
- Relive **does not** request Location Services permission and will not: Our Places uses photo
  metadata only.
- Shared: label (from on-device reverse geocoding, already cached) and, optionally, a ≈ 1 km cell
  (`GeoCoordinate.placeLookupKey`, 2 decimals). Never the full coordinate.
- Setting **"Share photo locations with Kübra"** (default off). Copy:
  *"This shares the places attached to memories you choose to share. It doesn't share your live
  location."*
- Home safety ❓: cells that match the sender's everyday places are withheld unless chosen for that
  memory. The existing home heuristic needs review before relying on it.

## 3. Disconnect, delete, leave — what really happens

CloudKit facts ✅: the owner can remove a participant or delete the share; a participant can leave.
After that, the removed person's CloudKit access to the zone ends and their devices stop syncing.
What is already **cached on their phone** stays until their app deletes it — CloudKit cannot reach
into another device. Relive must therefore delete its own local cache when it detects it lost
access.

| Action | Who | Effect on the sender's side | Effect on the other phone |
|---|---|---|---|
| **Remove from Our Relive** (one item) | its sender | record marked revoked, then deleted | removed on next sync ✅ — unless that phone saved it to Photos (that copy is theirs) |
| **Delete shared memory** | its sender | as above | as above |
| **Hide from my view** | receiver | — | hidden locally only |
| **Stop sharing locations** | each | future sends carry no cell; **existing** cells are removed from my shared records | removed on next sync |
| **Disconnect** (owner) | inviter | share deleted → zone no longer shared; owner keeps their own sent items locally as a private archive (decision) | access ends; Relive clears the shared cache on next launch/sync ⚠️ |
| **Disconnect** (partner) | invitee | partner leaves the share | partner's cache cleared; **items the partner sent stay in the owner's zone** unless deleted first (decision: offer "Also remove what I shared") |
| **Relationship ends** | either | = disconnect + optional "Remove everything I shared" (deletes own records before leaving) | as above |
| **Block future access** | either | disconnect + refuse new invitations from that person (local block list) | — |
| **Reinstall** | — | private library rebuilt as today; shared data re-fetched from iCloud | — |
| **New iPhone** | — | same as reinstall | — |
| **Reconnect** | — | new invitation, new share; old shared items come back only if the owner's zone still holds them | — |

Owner-side asymmetry ❗ (product decision): the zone and its data live on the **owner's** iCloud.
If the invitee wants their own contributions removed, they must delete them *before* leaving (we
offer it). Alternative architecture B (each person owns a zone for what they send) removes this
asymmetry at the cost of complexity.

## 4. Accidental sharing

- Every share goes through a **preview** showing exactly the photo, the caption, and whether the
  place is included ("Kaş, Antalya · place included — Remove").
- **Undo Send**: items are queued locally and uploaded after **5 s** with an "Undo" toast; after
  upload, "Remove from Our Relive" is still available (with the caveat that the partner may have
  seen it).
- No multi-select "share all" in V1. Moments: sharing a moment previews its photos; the sender can
  untick any.
- Hidden and Don't-Suggest memories never appear in share pickers or suggestions.
- Shared items carry a quiet "Shared with Kübra" line in the viewer (not a badge on every
  thumbnail).

## 5. Widgets and notifications on a locked phone

- Default: photo and note text **redacted** when locked (`privacySensitive`); setting "Show shared
  photos in widgets when locked" (off by default).
- Notification text without content: "Kübra shared a memory"; previews follow the system's "Show
  Previews" setting plus a Relive setting "Include note text in notifications" (off).

## 6. iCloud states

| State | Relive behaviour |
|---|---|
| Not signed in / iCloud Drive off | Connection unavailable, explained; single-person Relive unaffected |
| iCloud full (owner) ⚠️ | Sends fail with "Kübra's/your iCloud is full"; nothing is lost locally |
| Account switched | Shared layer paused; shared cache cleared after confirmation; private data untouched |
| Restricted (Screen Time / MDM) | Same as not signed in |

## 7. What the partner can and cannot see

Can: what you sent (images, dates, place labels, captions, notes), your display name, whether you
share locations.
Cannot: your library, your other memories, your hidden or Don't-Suggest items, your creations
you didn't send, when you open the app (no presence, no "online"), your location.

Read state ("Seen") is **optional** and off by default (owner decision) — it can create pressure.
