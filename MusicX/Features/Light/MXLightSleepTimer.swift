import SwiftUI

/// A small, light-theme-only sheet. The actual pause is owned by ContentView's
/// shared PlayerStore so it also works if the full-screen player is dismissed.
struct MXLightSleepTimer: View {
    @Binding var deadline: Double
    @Environment(\.dismiss) private var dismiss

    private let options: [Int] = [15, 30, 60, 90, 120]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(MXLight.muted.opacity(0.3))
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 17)

            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("睡眠定时")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(MXLight.ink)
                    Text("时间到后自动暂停播放")
                        .font(.system(size: 12))
                        .foregroundStyle(MXLight.muted)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MXLight.teal)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.bottom, 22)

            if deadline > Date().timeIntervalSince1970 {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = max(0, Int(ceil(deadline - context.date.timeIntervalSince1970)))
                    let minutes = seconds / 60
                    let rest = seconds % 60
                    HStack {
                        Image(systemName: "moon.zzz.fill")
                            .foregroundStyle(MXLight.teal)
                        Text("剩余 \(minutes):\(String(format: "%02d", rest))")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(MXLight.teal)
                            .monospacedDigit()
                        Spacer()
                        Button("取消定时") {
                            deadline = 0
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(MXLight.red)
                    }
                    .padding(15)
                    .background(MXLight.lightTeal, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.bottom, 18)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(options, id: \.self) { minutes in
                    Button {
                        deadline = Date().addingTimeInterval(Double(minutes * 60)).timeIntervalSince1970
                        dismiss()
                    } label: {
                        Text("\(minutes) 分钟")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(MXLight.ink)
                            .frame(maxWidth: .infinity, minHeight: 53)
                            .background(MXLight.paper, in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(MXLight.line, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 18)

            Text("关闭此页面后定时仍然有效。后台暂停时间可能受 iOS 调度影响。")
                .font(.system(size: 12))
                .foregroundStyle(MXLight.muted)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .background(MXLight.background.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}
