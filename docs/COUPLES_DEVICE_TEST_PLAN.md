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
