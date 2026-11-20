enum LibraryQueue {
    static func selection<Song>(in displayed: [Song], at index: Int) -> [Song] {
        guard displayed.indices.contains(index) else { return [] }
        return Array(displayed[index...])
    }

    static func successor<Song>(in queue: [Song], after index: Int, loops: Bool) -> Song? {
        guard queue.indices.contains(index) else { return nil }
        if index + 1 < queue.count { return queue[index + 1] }
        return loops ? queue.first : nil
    }
}
