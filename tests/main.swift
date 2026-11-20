let favorites = Array(1...27)
let recent = Array((101...127).reversed())
var active: [Int] = []
for displayed in [favorites, recent, recent, favorites] {
    for index in [0, 7, 19, 26, 7, 7] {
        active = LibraryQueue.selection(in: displayed, at: index)
        precondition(active == Array(displayed.dropFirst(index)))
        precondition(active.first == displayed[index])
        let next = LibraryQueue.successor(in: active, after: 0, loops: false)
        precondition(next == displayed.dropFirst(index + 1).first)
        precondition(LibraryQueue.successor(in: active, after: active.count - 1, loops: true) == active.first)
    }
}
print("Library queue order, selection, replacement and advance passed")
