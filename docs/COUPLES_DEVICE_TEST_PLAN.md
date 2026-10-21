# Couples Device Test Plan

Couples features involve two people, two Apple IDs and two iPhones. **Simulator and unit tests are
not evidence** for any row below; a row is "validated" only when run on two physical devices and
recorded here with date, build and result.

## Setup

| | Device A ("Arda") | Device B ("Kübra") |
|---|---|---|
| Apple ID | test account A | test account B (different Apple ID) |
| iCloud | signed in, iCloud Drive on | signed in, iCloud Drive on |
| Photos | Full access, real-sized library (≥ 2,000) | Limited access, small library |
| Relive | TestFlight build, same version | same |
| CloudKit environment | Development first, then Production | same |

Record for every run: build number, commit, iOS version, network (Wi-Fi / cellular / offline),
app state of each device (foreground / background / force-quit).

## A. Connection

| # | Scenario | Expected |
|---|---|---|
| A1 | A invites via Messages; B taps link with Relive installed | Accept screen; after accept both show "Connected" |
| A2 | B taps link without Relive installed | App Store → install → open → accept still works |
| A3 | Link forwarded to a third Apple ID C | C cannot join; A/B unaffected |
| A4 | A invites while offline | Clear "Can't invite offline"; retry works |
| A5 | B signed out of iCloud | B sees explanation; no crash |
| A6 | A's iCloud full | Invite or first send reports the quota problem clearly |

## B. Sharing

| # | Scenario | Expected |
|---|---|---|
| B1 | A shares one photo (A foreground, B foreground) | B sees it within seconds; image 1600 px; no GPS in file |
| B2 | A shares; B's Relive force-quit | B gets a notification; content there on open |
| B3 | Both apps closed when A's share syncs | B's notification arrives (or arrives late) — record timing |
| B4 | A shares while offline | Queued, "Sending…"; delivered after reconnect |
| B5 | Undo within 5 s | Nothing reaches B |
| B6 | A removes a shared item | Gone from B after sync |
| B7 | B saves a received photo to Photos | Saved copy stays even after A removes it; never imported as B's memory |
| B8 | Shared photo deleted from A's Photos | Shared copy unaffected |
| B9 | Place included / excluded / location sharing off | B sees label only when included; never coordinates |

## C. Notes & notifications

| # | Scenario | Expected |
|---|---|---|
| C1 | A sends a note; B locked | Notification without text (default) |
| C2 | B enables note previews | Text shown per system "Show Previews" |
| C3 | 10 notes in a minute | Coalesced; no flood |
| C4 | No activity for a week | No reminder notifications at all |

## D. Widget

| # | Scenario | Expected |
|---|---|---|
| D1 | B has medium widget; A shares while B's app closed | Widget updates when the system allows; record delay |
| D2 | B locked, setting off | Photo/note redacted |
| D3 | Tap Note / Photo / Memory | Relive opens to the right composer |
| D4 | Offline for a day | Widget shows last item with its age, no error |

## E. Our Places & events

| # | Scenario | Expected |
|---|---|---|
| E1 | Both share Kaş photos | One Kaş pin, "You and Kübra" |
| E2 | Sender shares a photo taken at home | No cell shared unless explicitly allowed |
| E3 | Photos without location | Shared, absent from the map |
| E4 | Both captured the same trip (event summaries on) | "You both captured Kaş" once |

## F. Lifecycle

| # | Scenario | Expected |
|---|---|---|
| F1 | B reinstalls Relive | Shared items re-fetched; private story rebuilt as today |
| F2 | B moves to a new iPhone | Same as F1 |
| F3 | A (owner) disconnects | B loses access; B's cache cleared on next launch |
| F4 | B (partner) disconnects with "Remove what I shared" | B's items gone from A |
| F5 | Reconnect after F3 | New share; behaviour per product decision |
| F6 | A switches Apple ID | Shared layer paused; private data untouched |
| F7 | Network drops mid-upload | Resumes; no duplicates |

## G. Load

| # | Scenario | Expected |
|---|---|---|
| G1 | 500 shared items | Our Relive scrolls smoothly; memory stable |
| G2 | A has 20,000 photos, B 2,000 | No cross-library work; only shared items and summaries sync |

## Phase B — two-iPhone validation (partner connection)

Status: **not run yet.** CI covers the logic with a scripted iCloud only. Record each step as
pass/fail with date, build, commit and iOS version. Do not mark Phase B validated until all 17
steps pass on two physical iPhones with two different Apple IDs.

### Before you start

1. Both iPhones: iOS 18 or later; **different** Apple IDs signed in (Settings → [name] → iCloud);
   iCloud Drive on.
2. Install the **same build** on both, from Xcode (Development CloudKit environment) —
   recommended for the first run. For TestFlight (Production environment) the CloudKit schema
   must first be deployed to Production (see `COUPLES_ARCHITECTURE.md` §19, release checklist);
   otherwise step 6 fails.
3. Each iPhone has finished Relive's onboarding with its own names: Device A (Arda) partner name
   "Kübra", user name "Arda"; Device B (Kübra) partner name "Arda", user name "Kübra".
4. Optional, for diagnosis: Console.app on a Mac, filter subsystem `app.relive`, category
   `partner`.

| # | Device | Do | Expected |
|---|---|---|---|
| 1 | A and B | Settings → [name] shows an Apple ID; iCloud on | Both signed in, different accounts |
| 2 | A and B | Open Relive; browse Today, Story, Create, Us | Works exactly as before; no iCloud or notification prompt appears |
| 3 | A | Us tab, scroll to **Your partner** | "Connect Your Partner", footer "Free. Relive works just the same on your own." No Premium badge |
| 4 | A | Tap **Connect Your Partner** | Explanation sheet opens; nothing is sent yet |
| 5 | A | Read the sheet | Five points: works on your own; doesn't upload the library; analysis stays on this iPhone; only what you choose is shared later; no live location. "Continue", "Not Now" |
| 6 | A | Tap **Continue** | Sheet closes, "Checking iCloud…" then "Getting your invitation ready…", then Apple's sharing screen appears. Us shows "Invitation sent · Waiting for Kübra to accept" |
| 7 | A | In Apple's screen, send by Messages (or Copy Link and send) to Kübra's Apple ID | Message delivered. Closing the screen leaves "Invitation sent" |
| 8 | B | Open the link from Messages. Test both variants on separate runs: (a) Relive **not running** (force-quit first) — cold launch; (b) Relive open in the background — warm | iOS opens Relive. Alert "Connected" with "You’re connected. Each of you keeps your own memories…" |
| 9 | B | Look at Us → Your partner | "Connected with Arda" (B's own names; nothing renamed). The Us header still reads "Kübra ♥ Arda" as B entered it |
| 10 | A | Bring Relive to the foreground (or wait for the silent update) | "Connected with Kübra". Partner settings: Status "Connected", Last checked "now" |
| 11 | A and B | Force-quit Relive on both; reopen | Same connected state, shown immediately (before any network) |
| 12 | A and B | Open Us → Your partner → partner settings | Still "Connected"; Last checked updates after a moment |
| 13 | B | Turn on Airplane Mode; open Relive; go to Us | — |
| 14 | B | Observe | "Connected with Arda" with "Still connected · offline for now" — never "Connect Your Partner". The rest of Relive works offline |
| 15 | B | Turn Airplane Mode off; leave and reopen Relive | — |
| 16 | B | Observe | The offline note disappears; "Last checked" is recent |
| 17a | B | Partner settings → **Leave Connection**; read the confirmation; confirm | Text says sharing stops, the connection was started from Arda's iCloud and stays theirs, B's photos and memories don't change. B returns to "Connect Your Partner" |
| 17b | A | Bring Relive to the foreground | "Your partner ended the connection. Your own memories are unchanged." OK → "Connect Your Partner" |
| 17c | A, B | Reconnect (steps 4–10), then on A: partner settings → **Disconnect Partner**; confirm | A returns to solo at once. B, on next foreground: "Your partner ended the connection." |

### Extra checks (run after the 17 steps)

| # | Do | Expected |
|---|---|---|
| X1 | Forward A's invitation link to a third Apple ID (C) after B joined; C opens it | C sees "This Relive relationship already has two people." (or iOS refuses the link); A and B stay connected |
| X2 | On B while connected, open a second invitation from someone else | "You’re already connected with a partner. Disconnect first…" |
| X3 | Sign out of iCloud on B, open Relive → Us | "Sign in to iCloud…" message; Relive otherwise works. Sign back in → connected again |
| X4 | On A, Connect while in Airplane Mode | "Relive couldn’t reach iCloud. Try again." Nothing half-made remains after retrying online |
| X5 | Settings → Notifications | Relive has never asked for notification permission |
| X6 | On A, open the invitation link A sent | Nothing new happens; still "Invitation sent" / "Connected" |
