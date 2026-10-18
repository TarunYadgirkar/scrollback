# Screen Time on a paid developer account

## Free team versus paid team

A free Personal Team can't use Screen Time's APIs, so every phone feature on it needs a workaround. A paid Apple Developer Program membership removes most of them:

| On a free team | Why | On a paid team |
| --- | --- | --- |
| iPhone data read on the Mac from Biome, then synced to the phone | No API on the phone | **The phone reports itself** through DeviceActivity, live |
| 10–17 hours of lag on iPhone data | Apple batches Biome sync to the Mac | Live card updates as you use the phone |
| Shortcuts automations to log app opens | No background hook | **Monitor extension** wakes at every 5 minutes of doomscroll-app use |
| Reinstall every 7 days, 3-app limit | Free provisioning | Profiles last 365 days; no app limit |
| No blocking | No ManagedSettings | Still none: Scrollback explains usage and leaves blocking to apps built for it |

The Family Controls capability (`com.apple.developer.family-controls`) is granted to development profiles on any paid team, so the app, both Screen Time extensions and the App Group sign without waiting for Apple.

## The shape

```
iPhone
├─ App ─────────── setup (Screen Time access, pick doomscroll apps)
│                  live card · binges · Ask · history
├─ Report ext ──── draws today's real usage: app names, hourly bars, pickups, longest sitting
│                  (Apple keeps this data inside the extension)
└─ Monitor ext ─── fires every 5 min of doomscroll-app use up to 4h, then every 15 up to 12h; writes a timestamp
                   to the shared App Group database → app rebuilds a live timeline

Mac
└─ App ─────────── Biome reader: Mac usage, plus detailed iPhone history (to the second,
                   with "opened from") once Apple syncs it · serves it to the phone
```

## Two kinds of iPhone data, and what each is for

- **Live (DeviceActivity):** today, right now. Two routes:
  - The report extension sees per-app totals, pickups and the longest continuous session in each hour. It can only *draw* them; Scrollback's own code never sees the numbers.
  - The monitor extension's milestones *are* visible to the app, at 5-minute resolution, for the apps you picked. They power live binge detection, Ask and the doomscroll notification.
- **Detailed (Biome via the Mac):** every open and close to the second, with how it was opened. It arrives hours late. It's the permanent record, and it replaces the live estimate once it covers a time range.

## Still a workaround, and staying

- **Reading Biome on the Mac.** DeviceActivity doesn't exist on macOS, so this stays the only source of Mac usage and of second-level iPhone history.
- **LAN sync from Mac to phone.** CloudKit carries the same history through the private iCloud database, so the phone gets it away from home too.

## The in-app data API, and why Scrollback doesn't use it

iOS 26.4 added `DeviceActivityData.activityData(filteredBy:using:)`, which hands the app itself real usage (bundle IDs, hourly). It needs a second tier, **Family Controls App And Website Usage** (`approvedWithDataAccess`):

- Only one app per phone can hold it, and while one does, **Apple's own Screen Time stops receiving usage data**.
- Once the capability is in the app, iOS offers full access or nothing.
- Outside the EU it only works in development builds. TestFlight and App Store builds fall back to plain access.

Scrollback stays on plain access so Apple's Screen Time keeps working next to it. The report extension plus monitor milestones cover live use without the data tier.

## Known platform limits (from Apple's docs and DTS forum replies)

- **Report extension:** finest granularity is an hour; read-only sandbox (no App Group writes, network or notifications).
- **Monitor extension:** 6 MB memory; at most 20 activities per app; schedule intervals of 15 minutes to a week.
- **Known bugs:** duplicate threshold callbacks, and thresholds firing with no usage while charging (DTS: known issue, iOS 26.2–26.4). Duplicates are already dropped; phantom milestones can still add a 5-minute block.
- **Distribution:** TestFlight and the App Store need Apple to approve Family Controls separately for the app *and each extension*. Turnaround reports range from days to over a month. Cable installs don't need it.
- **Usage data must stay on your devices** (Developer Program License 3.3.3(P)). The Mac↔phone sync is fine; a server wouldn't be.
