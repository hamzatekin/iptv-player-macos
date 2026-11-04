# IPTV Player for macOS

A native macOS app for watching live TV from an Xtream Codes IPTV account. SwiftUI for the
interface, [mpv](https://mpv.io) (through [MPVKit](https://github.com/mpvkit/MPVKit)) for playback.
A personal project: live TV only, no movies or series.

## Features

- Sign in once; the login is kept in the Keychain. The account button in the toolbar shows and edits it
- Channel list by category, with search and favorites. "HD", "FHD" and "4K" copies of a channel
  are merged into one channel with a quality menu
- Now and next from the provider's guide
- Full screen (double-click the video) and an always-on-top mini player
- Reconnects by itself when a stream drops
- Previous channel (⌘L), audio track and subtitle choice, stream info (⌘I) and a sleep timer
- Media keys and Control Center: play/pause works, and the previous and next keys change channel
- Plain-English playback errors: when a channel won't play, the app checks the account, the
  stream server and the network, then says why (offline, ISP block, connection already in use,
  expired account, channel off air)

## Requirements

- macOS 15 or later
- Xcode 26 or later (the app icon is an Icon Composer document), and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build and run

```sh
make run    # generates the Xcode project, builds, launches the app and follows its log
make test   # tests for the core package (no network)
```

The first build downloads MPVKit. For debug runs, an optional `.env` file (gitignored) can hold
`IPTV_SERVER`, `IPTV_USERNAME` and `IPTV_PASSWORD`, used until a login is saved in the app.

To keep the saved login across rebuilds, sign builds with an Apple Development certificate (free):
in Xcode, Settings > Accounts > + > Apple ID, then Manage Certificates > + > Apple Development.
`make build` finds it in the Keychain. Ad-hoc builds lose the saved login on every rebuild.

## Layout

- `App/`: the macOS app (views, app state, the mpv player)
- `Packages/IPTVCore/`: the logic, with tests (Xtream API client, channel grouping, stores,
  playback diagnosis)

`CLAUDE.md` has the details: how it works, facts about the provider, and the rules for changing it.
