# To do

## Reviewer findings on the player features (31 Oct 2026)

- [ ] **Say why when the last reconnect fails** (medium). If each retry plays for a while and then
  ends, mpv reports an end, not an error. After the third retry the player shows "Stopped" and checks
  nothing. Make the end of a live stream a failure (the EOF branch in `MPVPlayer.drainEvents` sets
  `.failed`), and run the diagnosis whenever reconnecting gives up (`AppModel.streamEnded`).
- [ ] **Ignore an error that arrives just after Stop** (low). The END_FILE error branch in `MPVPlayer`
  doesn't check `currentURL`. An error that arrives after Stop or the sleep timer can leave
  "Reconnecting… 1 of 3" on screen until Stop is pressed again. When `currentURL` is nil, go idle
  and don't report it.
- [ ] **Reconnect with the current password** (low). `MPVPlayer.reload` reopens the stored URL, which
  still has the old password after a password change in the account sheet. Build the URL again from
  the client when reconnecting.
- [ ] **Keep Control Center's programme current** (low). `NowPlaying.publish` only runs again when
  something it watches changes, so the programme title stays up after the programme ends. The sleep
  menu's "End of Programme (time)" can also show a time that has passed. Publish again on the 60 s
  guide timer.
- [ ] **Keep the media keys after a stream stops by itself** (low, not checked on macOS).
  `NowPlaying` clears Now Playing when the stream is idle or has failed, including while it waits to
  reconnect. macOS may then send the play key to Music. While a channel is still selected, publish
  it as paused.
- [ ] **Fix the `IPTV_TEST_INSTANCE` docs** (nit). CLAUDE.md lists it under `make run`, but
  `scripts/run.sh` doesn't pass it on, or `IPTV_DEBUG_PLAY_URL`. Say to launch a second copy with
  `open -n --env …`, or pass both through in run.sh.

## Decided

- [ ] **Check the line before reconnecting.** Before each retry, ask the provider whether the line
  is busy. If it's still busy after the last wait, stop and show the "Another device is watching.
  Watch here?" prompt. On a provider where the newest connection wins, retrying without checking
  could knock the TV off.

## Still to check in the app

- [ ] The media keys reach the app: play/pause, and previous/next change channel.
- [ ] The sleep timer stops playback when it runs out.
- [ ] Previous Channel (⌘L) works end to end.
- [ ] Screenshots of the new buttons, the stream info panel and the Reconnecting screen. The screen
  was locked during testing.

## Bugs found along the way, not caused by these changes

- [ ] mpv crashes when an audio device appears or disappears (`hotplug_cb` → `mp_msg`). Crash
  report: `~/Library/Logs/DiagnosticReports/IPTVPlayer-2026-10-31-152731.ips`. mpv fixed it upstream
  on 18 Aug 2026 (commits c5d391adb and af067b5ea), but MPVKit 1.1.0 still ships mpv 0.41.0, which
  doesn't have the fix. Upgrade once MPVKit includes it.
- [ ] If saving the login to the Keychain fails during sign in, the warning is wiped at once,
  because the channel refresh that follows clears it.
- [ ] `ServerAddress.normalize` keeps the host's capitals, so `HOST.COM` and `host.com` count as
  different accounts and the channels reload.
