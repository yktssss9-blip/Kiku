import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let username: String

    private var qrImage: UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data("kiku://add?username=\(username)".utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return UIImage() }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return UIImage() }
        return UIImage(cgImage: cgImage)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 6) {
                    Text("マイQRコード")
                        .font(.headline)
                    Text("相手にスキャンしてもらってください")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(20)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)

                Text("@\(username)")
                    .font(.title3.weight(.semibold))

                ShareLink(
                    item: Image(uiImage: qrImage),
                    preview: SharePreview("Kiku - @\(username)", image: Image(uiImage: qrImage))
                ) {
                    Label("QRコードを共有", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
    }
}
