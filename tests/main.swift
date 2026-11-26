let favorites = Array(1...27)
precondition(LibraryQueue.successor(in: favorites, after: 7, loops: false) == 9)
precondition(LibraryQueue.successor(in: favorites, after: 26, loops: true) == 1)
precondition(LibraryQueue.successor(in: favorites, after: 26, loops: false) == nil)
precondition(LibraryQueue.successor(in: [Int](), after: 0, loops: true) == nil)
print("Queue successor checks passed")

precondition(MusicQuality.standard.lxQuality(supported: ["128k", "320k"]) == "128k")
precondition(MusicQuality.high.lxQuality(supported: ["128k", "320k"]) == "320k")
precondition(MusicQuality.lossless.lxQuality(supported: ["128k", "320k", "flac"]) == "flac")
precondition(MusicQuality.hires.lxQuality(supported: ["128k", "flac", "flac24bit"]) == "flac24bit")
precondition(MusicQuality.hires.lxQuality(supported: ["128k", "320k"]) == "320k")
precondition(MusicQuality.standard.lxQuality(supported: []) == "320k")
print("LX quality preference checks passed")

func fixture(_ source: MusicSource, _ index: Int, _ title: String, _ artist: String) -> MusicSong {
    MusicSong(source: source, sourceID: String(index), title: title, artist: artist,
              album: nil, artworkURL: nil, duration: nil, hash: nil, albumID: nil,
              pictureID: nil, lyricID: nil)
}
let wyChart = [
    fixture(.netease, 1, "冬天又来临", "罗言"),
    fixture(.netease, 2, "Hong Kong (feat. 王菲季候风)", "The Weeknd"),
    fixture(.netease, 3, "慌啥子嘛", "赵本山"),
    fixture(.netease, 4, "污点证人 (Live)", "薛之谦"),
    fixture(.netease, 5, "无 意", "加木/Demxntia")
]
let qqChart = [
    fixture(.qq, 1, "慌啥子嘛", "赵本山"),
    fixture(.qq, 2, "Hong Kong (feat. 王菲季候风)", "The Weeknd"),
    fixture(.qq, 3, "Hot Shot", "喻言"),
    fixture(.qq, 4, "宿命之外", "时代少年团"),
    fixture(.qq, 5, "你的名字", "鹭卓")
]
let fused = MusicChartFusion.merge(netease: wyChart, qq: qqChart, limit: 6)
precondition(fused.map(\.title) == ["冬天又来临", "慌啥子嘛", "Hong Kong (feat. 王菲季候风)", "Hot Shot", "污点证人 (Live)", "宿命之外"])
precondition(fused.map(\.source) == [.netease, .qq, .netease, .qq, .netease, .qq])
precondition(MusicChartFusion.merge(netease: wyChart, qq: [], limit: 50) == wyChart)
precondition(MusicChartFusion.merge(netease: [], qq: qqChart, limit: 50) == qqChart)
precondition(MusicChartFusion.merge(netease: wyChart, qq: qqChart, limit: 0).isEmpty)
let largeWY = (1...50).map { fixture(.netease, $0, "WY \($0)", "WY") }
let largeQQ = (1...50).map { fixture(.qq, $0, "QQ \($0)", "QQ") }
let large = MusicChartFusion.merge(netease: largeWY, qq: largeQQ, limit: 50)
precondition(large.count == 50 && large.filter { $0.source == .qq }.count == 25)
precondition(MusicChartFusion.merge(netease: largeWY, qq: largeWY, limit: 50) == largeWY)
print("Chart fusion regression checks passed")
