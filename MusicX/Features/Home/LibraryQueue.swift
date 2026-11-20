enum LibraryQueue {
    static func successor<Song>(in queue: [Song], after index: Int, loops: Bool) -> Song? {
        guard queue.indices.contains(index) else { return nil }
        if index + 1 < queue.count { return queue[index + 1] }
        return loops ? queue.first : nil
    }
}
