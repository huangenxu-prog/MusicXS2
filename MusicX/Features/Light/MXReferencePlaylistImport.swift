import SwiftUI

/// Matches reference screen 12 while using the existing QQ/NetEase import workflow.
struct MXReferencePlaylistImport: View {
    @Binding var shareLink: String
    let isLoading: Bool
    let errorText: String?
    let preview: MXLightCollection?
    let onBack: () -> Void
    let onParse: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19))
                        .frame(width: 40, height: 42, alignment: .leading)
                }
                Spacer()
                Text("导入歌单").font(.system(size: 16, weight: .bold))
                Spacer()
                Color.clear.frame(width: 40, height: 42)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(MXLight.ink)
            .padding(.horizontal, 24)
            .padding(.top, 7)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 22).fill(MXLight.teal)
                        Circle()
                            .fill(MXLight.ochre)
                            .frame(width: 113, height: 113)
                            .offset(x: 300, y: 37)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("导入自己的音乐")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.75))
                            Text("把喜欢的歌单带过来")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                        .padding(.horizontal, 22)
                    }
                    .frame(height: 110)
                    .clipped()
                    .padding(.bottom, 25)

                    Text("支持的来源")
                        .font(.system(size: 12))
                        .tracking(1.7)
                        .foregroundStyle(MXLight.muted)
                    HStack(spacing: 10) {
                        Text("QQ 音乐")
                            .padding(.horizontal, 17)
                            .frame(height: 40)
                            .background(MXLight.ochre, in: Capsule())
                        Text("网易云音乐")
                            .padding(.horizontal, 17)
                            .frame(height: 40)
                            .background(MXLight.lightTeal, in: Capsule())
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MXLight.ink)
                    .padding(.top, 11)

                    Text("歌单分享链接")
                        .font(.system(size: 15, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(MXLight.headingMuted)
                        .padding(.top, 27)
                        .padding(.bottom, 13)

                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundStyle(MXLight.ink)
                        TextField("", text: $shareLink,
                            prompt: Text("粘贴歌单分享链接…")
                                .foregroundColor(MXLight.muted))
                            .font(.system(size: 14))
                            .foregroundStyle(MXLight.ink)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 55)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(MXLight.line, lineWidth: 1))

                    Text("仅支持公开歌单分享链接，导入后以本地列表方式保存。")
                        .font(.system(size: 12))
                        .foregroundStyle(MXLight.muted)
                        .padding(.top, 11)
                        .padding(.bottom, 19)

                    Button(action: onParse) {
                        Group {
                            if isLoading { ProgressView().tint(.white) }
                            else { Text("解析歌单") }
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 45)
                        .background(MXLight.red, in: Capsule())
                    }
                    .disabled(shareLink.isEmpty || isLoading)

                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 12))
                            .foregroundStyle(MXLight.red)
                            .padding(.top, 10)
                    }

                    Text("导入预览")
                        .font(.system(size: 15, weight: .bold))
                        .tracking(1.7)
                        .foregroundStyle(MXLight.headingMuted)
                        .padding(.top, 27)
                        .padding(.bottom, 13)

                    if let preview {
                        HStack(spacing: 13) {
                            MXLightArtwork(url: preview.artworkURL, size: 62, variant: 3)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(preview.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(MXLight.ink).lineLimit(2)
                                Text("\(preview.source?.displayName ?? "歌单") · \(preview.count ?? 0) 首")
                                    .font(.system(size: 12)).foregroundStyle(MXLight.muted)
                            }
                            Spacer()
                            Image(systemName: "checkmark")
                                .foregroundStyle(MXLight.ink)
                        }
                        .padding(15)
                        .background(MXLight.paper, in: RoundedRectangle(cornerRadius: 18))
                        Button("保存到我的歌单", action: onSave)
                            .font(.system(size: 14))
                            .foregroundStyle(MXLight.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 43)
                            .background(MXLight.cream, in: Capsule())
                            .padding(.top, 17)
                    } else {
                        Text("解析成功后将在这里显示歌单名称及歌曲数量")
                            .font(.system(size: 12))
                            .foregroundStyle(MXLight.muted)
                            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                    }

                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
        }
        .background(MXLight.background.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}
