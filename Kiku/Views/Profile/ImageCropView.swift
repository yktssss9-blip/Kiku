import SwiftUI

struct ImageCropView: View {
    let image: UIImage
    let onConfirm: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat        = 1.0
    @State private var lastScale: CGFloat    = 1.0
    @State private var minScale: CGFloat     = 1.0
    @State private var offset: CGSize        = .zero
    @State private var lastOffset: CGSize    = .zero
    @State private var containerSize: CGSize = .zero

    private let cropSize: CGFloat = 280
    private let maxScale: CGFloat = 5.0

    var body: some View {
        NavigationStack {
            // GeometryReader を NavigationStack の直接の子にすることで
            // シート提示時でも確実にサイズを取得できる
            GeometryReader { geo in
                ZStack {
                    Color.black

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .clipped()

                    // オーバーレイ：even-odd fill で円の外だけ暗くする
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: geo.size))
                        path.addEllipse(in: CGRect(
                            x: (geo.size.width - cropSize) / 2,
                            y: (geo.size.height - cropSize) / 2,
                            width: cropSize,
                            height: cropSize
                        ))
                    }
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)

                    // ガイド円
                    Circle()
                        .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                        .frame(width: cropSize, height: cropSize)
                        .allowsHitTesting(false)
                }
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(maxScale, max(minScale, lastScale * value))
                            }
                            .onEnded { _ in
                                withAnimation(.interactiveSpring()) {
                                    scale = min(maxScale, max(minScale, scale))
                                }
                                lastScale = scale
                                clampOffset(geoSize: geo.size)
                            },
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width:  lastOffset.width  + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                clampOffset(geoSize: geo.size)
                                lastOffset = offset
                            }
                    )
                )
                .onAppear {
                    guard geo.size.width > 0, geo.size.height > 0 else { return }
                    containerSize = geo.size
                    fitInitialScale(geoSize: geo.size)
                }
                .onChange(of: geo.size) { _, size in
                    guard size.width > 0, size.height > 0 else { return }
                    containerSize = size
                    fitInitialScale(geoSize: size)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .background(Color.black)
            .navigationTitle("切り取り範囲を調整")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("確定") {
                        onConfirm(renderCropped())
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: - Helpers

    private func fitInitialScale(geoSize: CGSize) {
        guard geoSize.width > 0, geoSize.height > 0,
              image.size.width > 0, image.size.height > 0 else { return }

        let fillScale = max(geoSize.width / image.size.width,
                            geoSize.height / image.size.height)
        let scaledMinDim = min(image.size.width * fillScale, image.size.height * fillScale)
        minScale = cropSize / scaledMinDim
        scale = max(minScale, 1.0)
        lastScale = scale
    }

    private func clampOffset(geoSize: CGSize) {
        guard geoSize.width > 0, geoSize.height > 0,
              image.size.width > 0, image.size.height > 0 else { return }

        let fillScale = max(geoSize.width / image.size.width,
                            geoSize.height / image.size.height)
        let scaledImgW = image.size.width  * fillScale * scale
        let scaledImgH = image.size.height * fillScale * scale

        let maxX = max(0, (scaledImgW - cropSize) / 2)
        let maxY = max(0, (scaledImgH - cropSize) / 2)

        let clampedX = min(maxX, max(-maxX, offset.width))
        let clampedY = min(maxY, max(-maxY, offset.height))

        withAnimation(.interactiveSpring()) {
            offset = CGSize(width: clampedX, height: clampedY)
        }
        lastOffset = offset
    }

    private func renderCropped() -> UIImage {
        let viewW = containerSize.width
        let viewH = containerSize.height

        guard viewW > 0, viewH > 0,
              image.size.width > 0, image.size.height > 0 else { return image }

        // 画面上での画像の実際のスケール（scaledToFill × ユーザー操作スケール）
        let fillScale = max(viewW / image.size.width, viewH / image.size.height)
        let totalScale = fillScale * scale
        let scaledW = image.size.width  * totalScale
        let scaledH = image.size.height * totalScale

        // cropSize×cropSize のキャンバスにおける描画起点
        // （ビュー中心 + オフセットを起点に、クロップ円の左上を原点へ変換）
        let drawX = offset.width  - scaledW / 2 + cropSize / 2
        let drawY = offset.height - scaledH / 2 + cropSize / 2

        let size = CGSize(width: cropSize, height: cropSize)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
            image.draw(in: CGRect(x: drawX, y: drawY, width: scaledW, height: scaledH))
        }
    }
}
