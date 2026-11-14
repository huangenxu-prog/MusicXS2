import Foundation

/// Compatibility name retained for existing non-UI call sites.
/// All resolution is now performed by MusicSourceScheduler; the legacy
/// provider chain has been removed from the active implementation.
typealias LXMusicURLResolver = MusicSourceScheduler
