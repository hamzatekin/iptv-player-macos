# IPTV Player

A personal macOS app for watching live TV from one Xtream Codes account. Live TV only: movies and
series are out of scope. Mac only for now.

## Layout

```
project.yml              XcodeGen spec. The .xcodeproj is generated and gitignored: never edit it.
Makefile                 make build | make test | make run
App/                     SwiftUI app target (Swift 5 language mode)
  IPTVPlayerApp.swift    @main, scenes
  AppIcon.icon           App icon, an Icon Composer document (open it in Xcode's Icon Composer)
  Player/                MPVPlayer (the one mpv instance), MPVVideoView, PlayerView
  Model/                 AppModel (app state), AppSettings (user agent)
  Views/                 SwiftUI screens
Packages/IPTVCore/       Swift package, no UI (Swift 6 language mode)
  Sources/IPTVCore/      Models, XtreamClient, ChannelGrouping, Stores (cache, favorites, Keychain),
                         PlaybackDiagnosis + ProviderProblem + Reachability (why a stream failed), LogRedaction
  Tests/IPTVCoreTests/   Swift Testing tests, JSON fixtures in Fixtures/
```

## Commands

- `make test`: core package tests (`swift test`). Fast, no network.
- `make build`: generates the Xcode project and builds the app. First build downloads MPVKit.
- `make run`: builds, launches the app fresh (`open -F`) and follows its log in `$TMPDIR/iptvplayer-run.log`.
  Reads `.env` (gitignored) for `IPTV_SERVER`, `IPTV_USERNAME`, `IPTV_PASSWORD`, and `IPTV_MPV_LOG`
  (mpv log level, e.g. `v`). Debug builds also read `IPTV_DEBUG_PLAY_URL`: a stream to play at launch
  (e.g. Apple's public HLS test stream), for checking player changes without the provider's one
  connection. Don't launch the binary directly: after a force quit, window
  restoration can bring back zero windows.

## How it works

1. On launch the app loads the login from the Keychain (debug builds: `.env` variables win).
2. It shows the cached catalog from disk at once, and refreshes it from the server when older than 24h.
3. `ChannelGrouping` merges streams like "TRT 1 HD" and "TRT 1 FHD" into one channel with variants,
   and hides heading rows like "∞∞∞ TURK ULUSAL ∞∞∞".
4. Playing a channel hands `XtreamClient.liveStreamURL` to `MPVPlayer.play`, which replaces the
   current stream. mpv renders into `MPVVideoView`'s Metal layer through MoltenVK.
5. Now/next comes from `get_short_epg`, only for channels with an EPG id.
6. When mpv fails (it only says "loading failed"), `PlaybackDiagnosis.run` asks why: account info,
   one request to the stream URL that refuses the redirect and stops at the headers, and a bare TCP
   connect to the stream server. The resulting `ProviderProblem` is shown in the player. API errors
   use `ProviderProblem(error:)` too. Texts live in `App/Model/ProviderProblemDisplay.swift`.

## Facts about Xtream providers

Facts about the provider this checkout is used with (addresses, findings) are in `CLAUDE.local.md`,
which is gitignored.

- Often plain `http` only. ATS is relaxed in Info.plist (`NSAllowsArbitraryLoads`).
- **Some providers drop requests whose user agent they don't recognise**, even with a valid login.
  Every API request and the player send `AppSettings.userAgent` (a setting; default is a VLC user agent).
- **Accounts often allow one connection.** Never open a second stream (no previews, no prefetching
  of video). Switching channels goes through `MPVPlayer.play`, which replaces the stream in place.
- Live URLs are `/live/<user>/<pass>/<id>.ts`. The server answers them with a redirect to a separate
  stream server. Networks can block the stream servers while the API server works; the app reports
  that as "Stream server blocked on this network".
- The player is proven on Apple's public HLS stream: H.264 decodes on `videotoolbox` and draws
  through MoltenVK.
- JSON is loose: numbers can arrive as strings and fields can be null. Decode leniently.

## Rules

- **The repo is public.** Never commit `.env`, credentials, or anything that identifies the provider,
  the account or its owner: server names or IPs, usernames, logo hosts, network findings. Those go in
  `CLAUDE.local.md`. Fixtures use `example.com` and documentation IPs (`203.0.113.x`).
- Never log URLs that contain credentials (stream URLs and `player_api.php` URLs both do). mpv logs
  them, so its log text goes through `LogRedaction.redact` before it is printed.
- Never send API requests through `URLSession.shared`: its URL cache writes every request URL, with
  the password, to disk. `XtreamClient` uses `XtreamClient.defaultSession`, which caches nothing.
- MPVKit's MoltenVK context reads the drawable size only when mpv reconfigures its output, never on
  resize. `MPVPlayer.drawableSizeChanged` forces a reconfigure by nudging `video-aspect-override`;
  without it the picture stays at its old size in a corner after full screen, mini mode or a move
  to another display.
- Keep `audio-channels=stereo` while MPVKit ships mpv 0.41.0. On macOS 27 its coreaudio output fails
  to open mono, and a failed open leaves a device listener on freed memory: the next audio device
  change (headphones, AirPlay) crashes the app in `hotplug_cb`. mpv then plays through avfoundation,
  which reads ~2 s ahead, so volume changes lag. Fixed upstream after 0.41.0 (mpv `af067b5ea`,
  `c5d391adb`, `3dae21b1e`); drop the option once MPVKit ships an mpv with them.
- Keep `MPVPlayer` the only thing that talks to libmpv. Keep the `MPVVideoView` instance alive for
  the app's lifetime: mpv is bound to its Metal layer at startup.
- Core logic goes in `IPTVCore` with tests. The app target holds UI and wiring only.
- Testing against a real account uses its connection: don't run playback checks while the account
  is in use on another device.
