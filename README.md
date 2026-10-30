# IPTV Player for macOS

A native macOS app for watching live TV from an Xtream Codes IPTV account. SwiftUI for the
interface, [mpv](https://mpv.io) (through [MPVKit](https://github.com/mpvkit/MPVKit)) for playback.
A personal project: live TV only, no movies or series.

## Features

- Sign in once; the login is kept in the Keychain
- Channel list by category, with search and favorites. "HD", "FHD" and "4K" copies of a channel
  are merged into one channel with a quality menu
- Now and next from the provider's guide
- Full screen (double-click the video) and an always-on-top mini player
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
`IPTV_SERVER`, `IPTV_USERNAME` and `IPTV_PASSWORD`, so you skip the sign-in screen.

## Layout

- `App/`: the macOS app (views, app state, the mpv player)
- `Packages/IPTVCore/`: the logic, with tests (Xtream API client, channel grouping, stores,
  playback diagnosis)

`CLAUDE.md` has the details: how it works, facts about the provider, and the rules for changing it.
