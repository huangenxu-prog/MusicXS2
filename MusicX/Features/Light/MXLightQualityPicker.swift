import SwiftUI

/// Light-skin quality chooser with a visible, persisted selection.
/// This only changes the requested quality for subsequent stream resolution.
struct MXLightQualityPicker: View {
    @Binding var selectedQualityRaw: String
    @Environment(\.dismiss) private var dismiss

    private let options: [(MusicQuality, String, String)] = [
        (.standard, "标准音质", "128 kbps"),
        (.high, "高音质", "320 kbps"),
        (.lossless, "无损音质", "FLAC · 音源支持时"),
        (.hires, "Hi-Res", "高解析度 · 音源支持时")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(MXLight.muted.opacity(0.35))
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 16)

            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("播放音质")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(MXLight.ink)
                    Text("勾选的是当前音质偏好")
                        .font(.system(size: 12))
                        .foregroundStyle(MXLight.muted)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MXLight.teal)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.bottom, 15)

            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    let isSelected = selectedQualityRaw == option.0.rawValue
                    Button {
                        selectedQualityRaw = option.0.rawValue
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.1)
                                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(MXLight.ink)
                                Text(option.2)
                                    .font(.system(size: 12))
                                    .foregroundStyle(MXLight.muted)
                            }
                            Spacer(minLength: 8)
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 21))
                                    .foregroundStyle(MXLight.red)
                                    .accessibilityHidden(true)
                            } else {
                                Circle().stroke(MXLight.line, lineWidth: 1.4)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    if index < options.count - 1 {
                        MXLight.line.frame(height: 0.5)
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(MXLight.paper, in: RoundedRectangle(cornerRadius: 18))

            Text("切换后在下一次取链或重新播放时生效，实际音质取决于音源。")
                .font(.system(size: 12))
                .foregroundStyle(MXLight.muted)
                .padding(.top, 14)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .background(MXLight.background.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}
