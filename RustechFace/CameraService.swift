import SwiftUI
import AVFoundation
import Vision
import UIKit

/// Front camera + Apple Vision face detection (kapalit ng ML Kit + YOLO sa Android).
/// Tumatakbo palagi ang camera para may detection, kahit RoboEyes ang nakikita sa screen.
final class CameraService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()
    @Published var videoOrientation: AVCaptureVideoOrientation = .landscapeRight

    /// Tinatawag sa MAIN thread. Rect ay normalized (0...1), top-left origin, upright na frame.
    /// nil = walang nakitang mukha.
    var onFace: ((CGRect?) -> Void)?

    private let queue = DispatchQueue(label: "rustech.camera.queue")
    private let output = AVCaptureVideoDataOutput()
    private var configured = false
    private var frameCount = 0
    private var currentOrientation: AVCaptureVideoOrientation = .landscapeRight
    private var orientationObserver: NSObjectProtocol?

    func start() {
        DispatchQueue.main.async { self.observeOrientation() }
        queue.async { [weak self] in
            guard let self = self else { return }
            if !self.configured { self.configure() }
            if self.configured && !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)

        if let conn = output.connection(with: .video), conn.isVideoOrientationSupported {
            conn.videoOrientation = currentOrientation
        }
        session.commitConfiguration()
        configured = true
    }

    private func observeOrientation() {
        guard orientationObserver == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateOrientation()
        }
        updateOrientation()
    }

    private func updateOrientation() {
        let newOrientation: AVCaptureVideoOrientation
        switch UIDevice.current.orientation {
        case .landscapeLeft: newOrientation = .landscapeRight
        case .landscapeRight: newOrientation = .landscapeLeft
        default: return
        }
        currentOrientation = newOrientation
        videoOrientation = newOrientation
        queue.async { [weak self] in
            guard let self = self else { return }
            if let conn = self.output.connection(with: .video), conn.isVideoOrientationSupported {
                conn.videoOrientation = newOrientation
            }
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        if frameCount % 4 != 0 { return } // ~7-8 detections kada segundo, sapat na at magaan sa iPhone 8

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return
        }

        let faces: [VNFaceObservation] = (request.results as? [VNFaceObservation]) ?? []
        var result: CGRect? = nil
        if let biggest = faces.max(by: { $0.boundingBox.width < $1.boundingBox.width }) {
            let b = biggest.boundingBox // Vision: normalized, origin sa ibabang-kaliwa
            result = CGRect(x: b.minX, y: 1.0 - b.maxY, width: b.width, height: b.height)
        }

        DispatchQueue.main.async { [weak self] in
            self?.onFace?(result)
        }
    }
}

// MARK: - SwiftUI camera preview

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let orientation: AVCaptureVideoOrientation

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if let conn = uiView.previewLayer.connection, conn.isVideoOrientationSupported {
            conn.videoOrientation = orientation
        }
    }
}
