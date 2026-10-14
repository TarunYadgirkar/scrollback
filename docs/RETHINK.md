# Scrollback with a paid developer account

## What changed

The free Personal Team couldn't use Screen Time's APIs, so every phone feature was a workaround:

| Before (free team) | Why | Now (paid team) |
| --- | --- | --- |
| iPhone data read on the Mac from Biome, then synced to the phone | No API on the phone | **The phone reports itself** through DeviceActivity, live |
| 10–17 hours of lag on iPhone data | Apple batches Biome sync to the Mac | Live card updates as you use the phone |
| Shortcuts automations to log app opens | No background hook | **Monitor extension** wakes at every 5 minutes of doomscroll-app use |
| Reinstall every 7 days, 3-app limit | Free provisioning | Profiles last 365 days; no app limit |
| Opal for blocking | No ManagedSettings | Scrollback can shield apps itself (not built yet) |

Verified on this Mac on 2026-10-14: Xcode issued a 365-day profile for team `5AKJYZ7USP` containing `com.apple.developer.family-controls`, and the app, both extensions and the App Group all sign.

## The new shape

```
iPhone
├─ App ─────────── setup (Screen Time access, pick doomscroll apps)
│                  live card · binges · Ask · history
├─ Report ext ──── draws today's real usage: app names, hourly bars, pickups, longest sitting
│                  (Apple keeps this data inside the extension)
└─ Monitor ext ─── fires at 5, 10, 15 … 240 min of doomscroll-app use, writes a timestamp
                   to the shared App Group database → app rebuilds a live timeline

Mac
└─ App ─────────── Biome reader: Mac usage, plus detailed iPhone history (to the second,
                   with "opened from") once Apple syncs it · serves it to the phone
```

## Two kinds of iPhone data, and what each is for

- **Live (DeviceActivity):** today, right now. Two routes:
  - The report extension sees per-app totals, pickups and the longest continuous session in each hour. It can only *draw* them; Scrollback's own code never sees the numbers.
  - The monitor extension's milestones *are* visible to the app, at 5-minute resolution, for the apps you picked. They power live binge detection, Ask, and (later) notifications.
- **Detailed (Biome via the Mac):** every open and close to the second, with how it was opened. It arrives hours late. It's the permanent record, and it replaces the live estimate once it covers a time range.

## Still a workaround, and staying

- **Reading Biome on the Mac.** DeviceActivity doesn't exist on macOS, so this stays the only source of Mac usage and of second-level iPhone history.
- **LAN sync from Mac to phone.** CloudKit would let the phone get history away from home. It's worth doing next, but the LAN path works today.

## The in-app data API, and its catch

iOS 26.4 added `DeviceActivityData.activityData(filteredBy:using:)`, which hands the app itself real usage (bundle IDs, hourly). It needs a second tier, **Family Controls App And Website Usage** (`approvedWithDataAccess`):

- Only one app per phone can hold it, and while one does, **Apple's own Screen Time stops receiving usage data**.
- Once the capability is in the app, iOS offers full access or nothing.
- Outside the EU it only works in development builds. TestFlight and App Store builds fall back to plain access.

Scrollback doesn't request it. The report extension plus monitor milestones cover live use without breaking Screen Time. The probe in the app (`probe.txt`) records what plain access returns; expect an error.

## Known platform limits (from Apple's docs and DTS forum replies)

- **Report extension:** finest granularity is an hour; read-only sandbox (no App Group writes, network or notifications).
- **Monitor extension:** 6 MB memory; at most 20 activities per app; schedule intervals of 15 minutes to a week.
- **Known bugs:** duplicate threshold callbacks, and thresholds firing with no usage while charging (DTS: known issue, iOS 26.2–26.4). Duplicates are already dropped; phantom milestones can still add a 5-minute block.
- **Distribution:** TestFlight and the App Store need Apple to approve Family Controls separately for the app *and each extension*. Turnaround reports range from days to over a month. Cable installs don't need it.
- **Usage data must stay on your devices** (Developer Program License 3.3.3(P)). The Mac↔phone sync is fine; a server wouldn't be.

## Next, in order

1. Run on the phone: grant access, pick apps, check the live card and `probe.txt`.
2. Shield doomscroll apps on a schedule, with a custom block screen and "5 more minutes" (replaces Opal).
3. A local notification at 20 minutes of continuous doomscrolling (from the monitor extension).
4. Widgets from the App Group data.
5. CloudKit for Mac↔phone history.
6. TestFlight, once Apple approves Family Controls for distribution.
