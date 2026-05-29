import SwiftUI
import AVFoundation

struct QRScannerView: View {
    var onScanned: (String) -> Void

    @State private var authStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var captureSession: AVCaptureSession?
    @State private var coordinator: ScanCoordinator?

    var body: some View {
        ZStack {
            switch authStatus {
            case .authorized:
                cameraContent
                    .onAppear(perform: startSession)
                    .onDisappear { captureSession?.stopRunning() }
            case .notDetermined:
                permissionRequestView
            default:
                permissionDeniedView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Camera

    private var cameraContent: some View {
        ZStack {
            if let session = captureSession {
                CameraPreviewView(session: session)
                    .ignoresSafeArea()
            }

            CutoutOverlay()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.9), lineWidth: 2)
                .frame(width: 240, height: 240)
                .allowsHitTesting(false)

            VStack {
                Spacer()
                Text("QRコードをフレームに合わせてください")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.bottom, 60)
            }
        }
    }

    // MARK: Permissions

    private var permissionRequestView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("カメラへのアクセスが必要です")
                .font(.headline)
            Button("カメラを許可する") {
                Task {
                    let granted = await AVCaptureDevice.requestAccess(for: .video)
                    await MainActor.run {
                        authStatus = granted ? .authorized : .denied
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .padding()
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("カメラが許可されていません")
                .font(.headline)
            Text("設定からカメラのアクセスを許可してください")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .padding()
    }

    // MARK: Session setup

    private func startSession() {
        if let existing = captureSession {
            if !existing.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { existing.startRunning() }
            }
            return
        }

        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        let coord = ScanCoordinator(onScanned: onScanned)
        output.setMetadataObjectsDelegate(coord, queue: .main)
        output.metadataObjectTypes = [.qr]

        coordinator = coord
        captureSession = session

        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }
}

// MARK: - Coordinator

final class ScanCoordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    let onScanned: (String) -> Void
    private var lastValue: String?

    init(onScanned: @escaping (String) -> Void) {
        self.onScanned = onScanned
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue,
              value != lastValue else { return }
        lastValue = value
        onScanned(value)
    }

    func reset() { lastValue = nil }
}

// MARK: - Camera preview

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView { PreviewUIView() }

    func updateUIView(_ view: PreviewUIView, context: Context) {
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
    }

    class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Cutout overlay

private struct CutoutOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
            RoundedRectangle(cornerRadius: 12)
                .frame(width: 240, height: 240)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }
}
