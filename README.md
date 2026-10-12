# Scrollback

See exactly what you did on your iPhone and Mac, minute by minute. Ask "what was I doing 7–8pm yesterday?" or "when did I stop scrolling?" and get a straight answer.

## Where the data comes from

macOS already records which app is in front, for this Mac and for any iPhone that syncs Screen Time ("Share Across Devices"). That record lives in Apple's Biome store:

```
~/Library/Biome/streams/restricted/App.InFocus/local/          this Mac
~/Library/Biome/streams/restricted/App.InFocus/remote/<uuid>/  your iPhone
~/Library/Biome/sync/sync.db                                   which uuid is which device
```

Each file is a SEGB v2 segment of protobuf records: app bundle ID, start or end, timestamp, and how the app was opened (Home Screen, App Switcher, notification…). `Packages/ScrollbackCore` decodes these, pairs them into sessions, and copies them into its own SQLite store. Apple deletes Biome records after about three weeks, but Scrollback's copy keeps them indefinitely.

A **binge** is a run of social apps where each hop happens within 2 minutes and the whole run lasts at least 5 minutes.

## Pieces

| Part | What it does |
| --- | --- |
| `Packages/ScrollbackCore` | SEGB decoder, sessionizer, binge detection, SQLite store, Ask (Apple's on-device model with tool calls), encrypted LAN sync |
| `Apps/Mac` | Menu bar glance and full window. Reads Biome every 5 minutes and serves sessions to the iPhone |
| `Apps/iOS` | Same timeline and Ask. Pulls sessions from the Mac over your Wi-Fi |
| `scrollback` CLI | `swift run scrollback yesterday 19:00-20:00` or `swift run scrollback ask "when did I stop scrolling"` |

## Setup

1. `scripts/install-mac.sh` builds the Mac app into `/Applications`.
2. In System Settings → Privacy & Security → Full Disk Access, turn on Scrollback. Then press **Check again** in the app.
3. Plug in your iPhone and run `scripts/install-phone.sh`. The first time, trust the developer on the phone in Settings → General → VPN & Device Management, and allow local network access when asked.
4. Optional: `scripts/phone-autoinstall.sh` installs a launch agent that reinstalls the phone app whenever it's plugged in and the build is more than 5 days old. Free Apple developer accounts sign builds for only 7 days.

Ask needs Apple Intelligence turned on, on whichever device you use it.

## Sync security

The Mac and iPhone share a 32-byte key (`~/Library/Application Support/Scrollback/peer.key`, mode 0600), baked into the phone build at install time. Requests are HMAC-signed with a timestamp and can't be replayed. Responses are ChaChaPoly-encrypted and bound to the request. The server accepts four connections at a time and gives no response to unauthenticated requests.

## Known limits

- iPhone data appears once Apple syncs it to the Mac, usually within minutes but sometimes hours.
- Away from home Wi-Fi, the phone shows its last synced copy.
- Mac idle time with an app still in front counts as use. The iPhone's lock screen ends sessions correctly.
