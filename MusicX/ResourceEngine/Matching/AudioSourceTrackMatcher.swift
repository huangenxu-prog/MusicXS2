import Foundation

/// Song identity is title + artist. Edition labels influence ranking rather
/// than rejecting every alternative recording of the same work.
enum AudioSourceTrackMatcher {
    static func matches(
        original: MusicSong,
        candidateTitle: String,
        candidateArtist: String,
        candidateDuration: TimeInterval? = nil,
        candidateAlbum: String? = nil,
        requireDuration: Bool = false
    ) -> Bool {
        matchScore(original: original, candidateTitle: candidateTitle,
                   candidateArtist: candidateArtist,
                   candidateDuration: candidateDuration) > 0
    }

    /// 100 = same edition; 55 = acceptable alternate live/re-recorded edition;
    /// 0 = different artist, remix, karaoke, instrumental, DJ, or cover.
    static func matchScore(
        original: MusicSong,
        candidateTitle: String,
        candidateArtist: String,
        candidateDuration: TimeInterval? = nil
    ) -> Int {
        let originalEdition = edition(original.title)
        let candidateEdition = edition(candidateTitle)
        guard !originalEdition.title.isEmpty,
              originalEdition.title == candidateEdition.title else { return 0 }

        let expected = Set(artistParts(original.artist))
        let actual = Set(artistParts(candidateArtist))
        guard !expected.isEmpty, !actual.isEmpty,
              !expected.isDisjoint(with: actual) else { return 0 }

        // Never substitute remixes, backing tracks, covers or radically altered
        // versions for the requested recording.
        let excluded: Set<String> = ["remix", "instrumental", "cover", "dj",
                                      "karaoke", "slowed", "spedup", "demo"]
        if !originalEdition.markers.isDisjoint(with: excluded)
            || !candidateEdition.markers.isDisjoint(with: excluded) {
            return originalEdition.markers == candidateEdition.markers ? 100 : 0
        }

        let versionKinds: Set<String> = ["live", "rerecorded", "acoustic"]
        let originalKinds = originalEdition.markers.intersection(versionKinds)
        let candidateKinds = candidateEdition.markers.intersection(versionKinds)
        var score = originalKinds == candidateKinds ? 100 : 55

        // Duration is a soft preference only; some catalogs report bad values.
        if let first = original.duration, let second = candidateDuration,
           first > 0, second > 0 {
            let delta = abs(first - second)
            if delta > 90 { score -= 15 }
            else if delta > 30 { score -= 5 }
        }
        return max(1, score)
    }

    /// Search by the work's title, not a platform-specific edition suffix.
    /// Preserve Chinese characters and original title punctuation where possible.
    static func searchTitle(_ title: String) -> String {
        var result = title
        let suffixes = [
            #"(?i)\s*[（(\[【]\s*(?:live|concert|remix|instrumental|acoustic|remaster(?:ed)?|official|original|无损|现场版?|演唱会版?|伴奏版?|混音版?|标准版|官方版|原版)\s*[)）\]】]\s*$"#,
            #"(?i)\s*[-–—]\s*(?:live|concert|remix|无损|现场版?|演唱会版?|伴奏版?|标准版)\s*$"#
        ]
        for pattern in suffixes {
            result = result.replacingOccurrences(of: pattern, with: "",
                                                  options: .regularExpression)
        }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? title : trimmed
    }

    static func durationDifference(original: MusicSong, candidateDuration: TimeInterval?) -> TimeInterval {
        guard let expected = original.duration, let actual = candidateDuration else {
            return .greatestFiniteMagnitude
        }
        return abs(expected - actual)
    }

    private static func artistParts(_ value: String) -> [String] {
        let withoutFeaturedCredits = value.replacingOccurrences(
            of: #"(?i)\s+(?:feat\.?|ft\.?|featuring|with)\s+"#,
            with: ";", options: .regularExpression
        )
        return withoutFeaturedCredits
            .split(whereSeparator: { "/&＆、,，;；".contains($0) })
            .map { normalized(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                      locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init).joined()
    }

    private static func edition(_ value: String) -> (title: String, markers: Set<String>) {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
        var text = folded
        var markers = Set<String>()
        let patterns: [(String, String)] = [
            (#"(?i)\b(?:live|concert)\b|现场版?|演唱会版?"#, "live"),
            (#"(?i)\b(?:remix|mix)\b|混音版?"#, "remix"),
            (#"(?i)\b(?:instrumental|inst\.?|backing track)\b|伴奏版?|纯音乐"#, "instrumental"),
            (#"(?i)\b(?:cover)\b|翻唱版?"#, "cover"),
            (#"(?i)\bdj\b|dj版"#, "dj"),
            (#"(?i)\bkaraoke\b|卡拉ok"#, "karaoke"),
            (#"(?i)\b(?:slowed)\b|降速版?"#, "slowed"),
            (#"(?i)\bsped[ -]?up\b|加速版?"#, "spedup"),
            (#"(?i)\bdemo\b|小样版?"#, "demo"),
            (#"(?i)\b(?:acoustic|unplugged)\b|不插电版?"#, "acoustic"),
            (#"(?i)\b(?:re-recorded|rerecorded)\b|重新录制版?|重录版?|重制版?"#, "rerecorded")
        ]
        for (pattern, marker) in patterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                markers.insert(marker)
                text = text.replacingOccurrences(of: pattern, with: " ",
                                                  options: .regularExpression)
            }
        }
        // Metadata/quality labels are not recording identities.
        let metadata = #"(?:\b(?:lossless|flac|hires|hi-res|320k|128k|official|original|remastered|remaster)\b|无损(?:音质|版)?|高音质|官方版?|原版|标准版|母带版?)"#
        text = text.replacingOccurrences(of: metadata, with: " ",
                                          options: .regularExpression)
        return (normalized(text), markers)
    }
}
