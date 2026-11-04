import AppKit
import IPTVCore
import Libmpv
import Observation

enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case failed(String)
}

/// A stream that ended by itself: not by `stop`, and not replaced by another one.
struct StreamEnd {
    /// mpv reported an error, rather than the stream just ending.
    let failed: Bool
    /// How long it had shown video; nil when it never started.
    let playedFor: TimeInterval?
}

/// The app's single mpv instance and the view it draws into.
///
/// Created once for the app's lifetime: mpv is bound to the view's Metal layer at startup, so the
/// view is reused wherever the video is shown (main window, full screen, mini mode).
/// Only one stream is ever open, which matters because the account allows one connection.
@MainActor
@Observable
final class MPVPlayer {
    private(set) var state: PlaybackState = .idle
    private(set) var isPaused = false
    private(set) var isBuffering = false
    private(set) var isMuted = false
    private(set) var volume: Double = 100
    /// The playing stream's video, audio and subtitle tracks.
    private(set) var tracks: [MediaTrack] = []

    let videoView = MPVVideoView()
    /// Masked in mpv's log output, which includes the stream URLs and so the login.
    @ObservationIgnored var logSecrets: [String] = []
    /// When a stream last started showing video.
    @ObservationIgnored private(set) var lastPlayedAt: Date?
    /// Called when the stream fails (state turns `.failed`) or ends by itself (state turns `.idle`).
    @ObservationIgnored var onStreamEnd: ((StreamEnd) -> Void)?
    /// Called when the stream first shows video.
    @ObservationIgnored var onStreamStart: (() -> Void)?
    @ObservationIgnored private var mpv: OpaquePointer?
    /// What `reload` opens again. Nil after `stop`.
    @ObservationIgnored private var currentURL: URL?
    /// When the current stream first showed video.
    @ObservationIgnored private var entryStartedAt: Date?
    /// The audio and subtitles picked for the current stream (`aid`, `sid`), kept across `reload`.
    @ObservationIgnored private var trackChoice: [String: String] = [:]
    /// mpv's playlist entry for the latest `play`. A replaced stream can still end in an error after
    /// `play` returns; that error must not count as the new stream failing.
    @ObservationIgnored private var currentEntryID: Int64?

    init(userAgent: String) {
        guard let handle = mpv_create() else {
            state = .failed("Could not start the video player")
            return
        }
        mpv = handle

        #if DEBUG
        mpv_request_log_messages(handle, ProcessInfo.processInfo.environment["IPTV_MPV_LOG"] ?? "warn")
        #else
        mpv_request_log_messages(handle, "no")
        #endif

        var layer = Int64(Int(bitPattern: Unmanaged.passUnretained(videoView.metalLayer).toOpaque()))
        check(mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &layer))
        for (name, value) in [
            ("vo", "gpu-next"),
            ("gpu-api", "vulkan"),
            ("gpu-context", "moltenvk"),
            ("hwdec", "videotoolbox"),
            // mpv 0.41.0's coreaudio output can't open mono on macOS 27 (error -50). When it fails it
            // leaves a device listener pointing at freed memory: the next audio device change (headphones,
            // AirPlay) crashes the app. mpv then falls back to avfoundation, which reads ~2 s ahead, so
            // volume changes lag. Stereo always opens. Drop this once MPVKit ships an mpv after 0.41.0.
            ("audio-channels", "stereo"),
            ("user-agent", userAgent),
            ("idle", "yes"),
            ("keep-open", "no"),
            ("ytdl", "no"),
            ("input-default-bindings", "no"),
            ("input-vo-keyboard", "no"),
            ("input-media-keys", "no"),
            ("cache", "yes"),
            ("network-timeout", "15"),
        ] {
            check(mpv_set_option_string(handle, name, value))
        }
        check(mpv_initialize(handle))

        mpv_observe_property(handle, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "mute", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "volume", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "track-list", MPV_FORMAT_NODE)
        videoView.onDrawableSizeChange = { [weak self] in self?.drawableSizeChanged() }

        // Called on an mpv thread. mpv API calls aren't allowed inside, so hop to the main thread
        // and drain events there. The player lives as long as the app, so an unretained pointer is safe.
        mpv_set_wakeup_callback(handle, { context in
            guard let context else { return }
            let player = Unmanaged<MPVPlayer>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { player.drainEvents() }
        }, Unmanaged.passUnretained(self).toOpaque())

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutdown() }
        }
    }

    // MARK: Commands

    /// Replaces whatever is playing. mpv closes the old connection before opening the new one.
    func play(_ url: URL) {
        currentURL = url
        trackChoice = [:]
        open()
    }

    /// Opens the current stream again, e.g. after it dropped, with the same audio and subtitles.
    func reload() {
        guard currentURL != nil else { return }
        open()
    }

    private func open() {
        guard let url = currentURL else { return }
        state = .loading
        entryStartedAt = nil
        // Per-file options: mpv puts them back when the file ends, so a track picked on one channel
        // doesn't carry over to the next one, which may not have that track.
        let options = ["aid": trackChoice["aid"] ?? "auto", "sid": trackChoice["sid"] ?? "auto"]
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        currentEntryID = loadFile(url.absoluteString, options: options)
        setFlag("pause", false)
    }

    /// Stops playback and closes the connection to the provider.
    func stop() {
        currentURL = nil
        entryStartedAt = nil
        command("stop")
        state = .idle
    }

    func selectAudio(_ trackID: Int) { selectTrack("aid", String(trackID)) }

    /// Nil turns subtitles off.
    func selectSubtitle(_ trackID: Int?) { selectTrack("sid", trackID.map(String.init) ?? "no") }

    private func selectTrack(_ property: String, _ value: String) {
        guard let mpv else { return }
        trackChoice[property] = value
        mpv_set_property_string(mpv, property, value)
    }

    /// Read on demand (the stream info panel asks once a second) rather than observed: bitrates and
    /// the buffer change all the time.
    func streamInfo() -> StreamInfo {
        var info = StreamInfo()
        guard state == .playing else { return info }
        let video = tracks.first { $0.kind == .video && $0.isSelected }
        let audio = tracks.first { $0.kind == .audio && $0.isSelected }
        info.width = int("video-params/w")
        info.height = int("video-params/h")
        info.fps = double("container-fps") ?? double("estimated-vf-fps")
        info.videoCodec = video?.codec
        info.hardwareDecoder = string("hwdec-current")
        info.videoBitrate = double("video-bitrate")
        info.audioCodec = audio?.codec
        info.audioChannels = int("audio-params/channel-count") ?? audio?.channelCount
        info.sampleRate = int("audio-params/samplerate") ?? audio?.sampleRate
        info.audioBitrate = double("audio-bitrate")
        let drops = [int("frame-drop-count"), int("decoder-frame-drop-count")].compactMap { $0 }
        info.droppedFrames = drops.isEmpty ? nil : drops.reduce(0, +)
        info.bufferedSeconds = double("demuxer-cache-duration")
        return info
    }

    func togglePause() { setFlag("pause", !isPaused) }
    func toggleMute() { setFlag("mute", !isMuted) }

    func setVolume(_ value: Double) {
        guard let mpv else { return }
        var volume = min(max(value, 0), 100)
        mpv_set_property(mpv, "volume", MPV_FORMAT_DOUBLE, &volume)
    }

    func setUserAgent(_ userAgent: String) {
        guard let mpv else { return }
        mpv_set_property_string(mpv, "user-agent", userAgent)
    }

    #if DEBUG
    /// Reads any mpv property as a string, for debug logging.
    func debugProperty(_ name: String) -> String? {
        guard let mpv, let value = mpv_get_property_string(mpv, name) else { return nil }
        defer { mpv_free(value) }
        return String(cString: value)
    }
    #endif

    // MARK: Resizing

    @ObservationIgnored private var resizeTask: Task<Void, Never>?

    /// MPVKit's MoltenVK context reads the drawable size only when mpv reconfigures its video output
    /// (a new stream or video format), never on resize: after full screen, mini mode or a move to another
    /// display, the picture stayed at its old size in a corner. Nudging the aspect override by 0.01% (too
    /// little to see) for a few frames makes mpv reconfigure, and setting it back reconfigures it again.
    private func drawableSizeChanged() {
        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))  // let a live resize settle
            guard let self, !Task.isCancelled, let mpv = self.mpv, self.state == .playing else { return }
            var aspect = 0.0
            guard mpv_get_property(mpv, "video-params/aspect", MPV_FORMAT_DOUBLE, &aspect) >= 0, aspect > 0 else { return }
            mpv_set_property_string(mpv, "video-aspect-override", String(aspect * 1.0001))
            // The override reaches the output with the next decoded frame.
            try? await Task.sleep(for: .milliseconds(300))
            guard let mpv = self.mpv else { return }
            mpv_set_property_string(mpv, "video-aspect-override", "no")
        }
    }

    // MARK: mpv plumbing

    private func command(_ args: String...) {
        guard let mpv else { return }
        var cArgs: [UnsafePointer<CChar>?] = args.map { UnsafePointer(strdup($0)) }
        cArgs.append(nil)
        defer { cArgs.forEach { free(UnsafeMutablePointer(mutating: $0)) } }
        check(mpv_command(mpv, &cArgs))
    }

    /// `loadfile <url> replace -1 <options>`, returning the new playlist entry's id. The index (-1)
    /// is unused with `replace`, but mpv takes the options only after it.
    private func loadFile(_ url: String, options: String) -> Int64? {
        guard let mpv else { return nil }
        var cArgs: [UnsafePointer<CChar>?] = ["loadfile", url, "replace", "-1", options].map { UnsafePointer(strdup($0)) }
        cArgs.append(nil)
        defer { cArgs.forEach { free(UnsafeMutablePointer(mutating: $0)) } }
        var result = mpv_node()
        let status = mpv_command_ret(mpv, &cArgs, &result)
        check(status)
        guard status >= 0 else { return nil }
        defer { mpv_free_node_contents(&result) }
        guard result.format == MPV_FORMAT_NODE_MAP, let list = result.u.list?.pointee else { return nil }
        for i in 0..<Int(list.num) where list.keys[i].map({ String(cString: $0) }) == "playlist_entry_id" {
            return list.values[i].u.int64
        }
        return nil
    }

    private func setFlag(_ name: String, _ value: Bool) {
        guard let mpv else { return }
        var flag: Int32 = value ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &flag)
    }

    private func int(_ name: String) -> Int? {
        var value: Int64 = 0
        guard let mpv, mpv_get_property(mpv, name, MPV_FORMAT_INT64, &value) >= 0 else { return nil }
        return Int(value)
    }

    private func double(_ name: String) -> Double? {
        var value = 0.0
        guard let mpv, mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &value) >= 0 else { return nil }
        return value
    }

    private func string(_ name: String) -> String? {
        guard let mpv, let value = mpv_get_property_string(mpv, name) else { return nil }
        defer { mpv_free(value) }
        return String(cString: value)
    }

    /// An mpv node as Swift values: integers as `Int64`, flags as `Bool`, maps as `[String: Any]`.
    private static func value(of node: mpv_node) -> Any? {
        switch node.format {
        case MPV_FORMAT_STRING: return node.u.string.map { String(cString: $0) }
        case MPV_FORMAT_FLAG: return node.u.flag != 0
        case MPV_FORMAT_INT64: return node.u.int64
        case MPV_FORMAT_DOUBLE: return node.u.double_
        case MPV_FORMAT_NODE_ARRAY:
            guard let list = node.u.list?.pointee else { return [Any]() }
            return (0..<Int(list.num)).compactMap { value(of: list.values[$0]) }
        case MPV_FORMAT_NODE_MAP:
            guard let list = node.u.list?.pointee else { return [String: Any]() }
            var map: [String: Any] = [:]
            for i in 0..<Int(list.num) {
                if let key = list.keys[i].map({ String(cString: $0) }) { map[key] = value(of: list.values[i]) }
            }
            return map
        default: return nil
        }
    }

    private func drainEvents() {
        while let mpv, let event = mpv_wait_event(mpv, 0)?.pointee, event.event_id != MPV_EVENT_NONE {
            switch event.event_id {
            case MPV_EVENT_START_FILE:
                state = .loading
            case MPV_EVENT_PLAYBACK_RESTART:
                state = .playing
                lastPlayedAt = .now
                if entryStartedAt == nil {
                    entryStartedAt = .now
                    onStreamStart?()
                }
            case MPV_EVENT_END_FILE:
                guard let endFile = event.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee else { continue }
                // The end of a stream that was already replaced: the new one is still opening.
                // Entry ids only grow, and a playlist URL's own entries come after the current one.
                if let currentEntryID, endFile.playlist_entry_id < currentEntryID { continue }
                let playedFor = entryStartedAt.map { Date.now.timeIntervalSince($0) }
                switch endFile.reason {
                case MPV_END_FILE_REASON_ERROR:
                    state = .failed(String(cString: mpv_error_string(endFile.error)))
                    onStreamEnd?(StreamEnd(failed: true, playedFor: playedFor))
                case MPV_END_FILE_REASON_EOF where currentURL != nil:
                    // A live stream has no end: the server closed the connection.
                    state = .idle
                    onStreamEnd?(StreamEnd(failed: false, playedFor: playedFor))
                default:
                    // A "stop", or a playlist URL handing over to its entries. A loadfile replace also
                    // ends the old file, but by then state is already .loading for the new one.
                    if state != .loading, endFile.reason != MPV_END_FILE_REASON_REDIRECT { state = .idle }
                }
            case MPV_EVENT_PROPERTY_CHANGE:
                if let property = event.data?.assumingMemoryBound(to: mpv_event_property.self).pointee {
                    apply(property)
                }
            case MPV_EVENT_LOG_MESSAGE:
                if let message = event.data?.assumingMemoryBound(to: mpv_event_log_message.self).pointee {
                    let text = LogRedaction.redact(String(cString: message.text), hiding: logSecrets)
                    print("[mpv/\(String(cString: message.prefix))] \(text)", terminator: "")
                }
            case MPV_EVENT_SHUTDOWN:
                shutdown()
            default:
                break
            }
        }
    }

    private func apply(_ property: mpv_event_property) {
        guard let data = property.data else { return }
        let name = String(cString: property.name)
        switch (name, property.format) {
        case ("pause", MPV_FORMAT_FLAG): isPaused = data.load(as: Int32.self) != 0
        case ("paused-for-cache", MPV_FORMAT_FLAG): isBuffering = data.load(as: Int32.self) != 0
        case ("mute", MPV_FORMAT_FLAG): isMuted = data.load(as: Int32.self) != 0
        case ("volume", MPV_FORMAT_DOUBLE): volume = data.load(as: Double.self)
        case ("track-list", MPV_FORMAT_NODE):
            let list = Self.value(of: data.load(as: mpv_node.self)) as? [Any] ?? []
            tracks = MediaTrack.parse(mpvTrackList: list.compactMap { $0 as? [String: Any] })
        default: break
        }
    }

    private func shutdown() {
        guard let handle = mpv else { return }
        mpv = nil
        mpv_set_wakeup_callback(handle, nil, nil)
        mpv_terminate_destroy(handle)
    }

    private func check(_ status: Int32) {
        if status < 0 {
            print("[mpv] API error: \(String(cString: mpv_error_string(status)))")
        }
    }
}

/// Layer-backed view whose layer is the Metal layer mpv renders into.
final class MPVVideoView: NSView {
    let metalLayer = MetalLayer()

    init() {
        super.init(frame: .zero)
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = NSColor.black.cgColor
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func makeBackingLayer() -> CALayer { metalLayer }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    /// Called after the drawable size changes (resize, full screen, mini mode, another display).
    var onDrawableSizeChange: (() -> Void)?

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        metalLayer.contentsScale = scale
        guard size != metalLayer.drawableSize else { return }
        metalLayer.drawableSize = size
        onDrawableSizeChange?()
    }
}
