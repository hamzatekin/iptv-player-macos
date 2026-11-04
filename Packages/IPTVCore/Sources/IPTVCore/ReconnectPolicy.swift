import Foundation

/// Whether a live stream that stopped by itself is opened again, and after how long.
///
/// Only a stream that has shown video is reconnected. One that never started is diagnosed instead
/// (blocked, refused, off air): trying it again would only delay saying why. The waits give the
/// provider time to free the dropped connection, since on a one-connection account an instant retry
/// is refused as "connection in use".
public struct ReconnectPolicy: Equatable, Sendable {
    public static let delays: [Duration] = [.seconds(2), .seconds(5), .seconds(10)]
    /// Playing this long counts as working again: the next drop starts over at the first wait.
    public static let steadyAfter: TimeInterval = 60

    private var hasPlayed = false
    /// Reconnects tried since the stream last played steadily.
    public private(set) var attempts = 0

    public init() {}

    /// Called each time the stream ends or fails by itself. `playedFor` is how long it showed video,
    /// nil when it never started. Returns how long to wait before opening it again, or nil to give up.
    public mutating func delayAfterStop(playedFor: TimeInterval?) -> Duration? {
        if let playedFor {
            hasPlayed = true
            if playedFor >= Self.steadyAfter { attempts = 0 }
        }
        guard hasPlayed, attempts < Self.delays.count else { return nil }
        defer { attempts += 1 }
        return Self.delays[attempts]
    }
}
