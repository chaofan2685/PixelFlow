import SwiftUI
import AVFoundation

/// 相机预览 + 识别框叠加层。
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let rects: [CGRect]

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.setDetectionRects(rects)
    }
}

final class PreviewView: UIView {

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    private let boxLayer = CAShapeLayer()
    private var currentRects: [CGRect] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black

        boxLayer.fillColor = UIColor.systemGreen.withAlphaComponent(0.12).cgColor
        boxLayer.strokeColor = UIColor.systemGreen.withAlphaComponent(0.9).cgColor
        boxLayer.lineWidth = 2
        boxLayer.lineJoin = .round
        layer.addSublayer(boxLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        boxLayer.frame = bounds
        CATransaction.commit()
        redraw()
    }

    func setDetectionRects(_ rects: [CGRect]) {
        currentRects = rects
        redraw()
    }

    private func redraw() {
        guard !currentRects.isEmpty, bounds.width > 0 else {
            boxLayer.path = nil
            return
        }
        let path = UIBezierPath()
        for rect in currentRects {
            let converted = previewLayer.layerRectConverted(fromMetadataOutputRect: rect)
            path.append(UIBezierPath(roundedRect: converted, cornerRadius: 6))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        boxLayer.path = path.cgPath
        CATransaction.commit()
    }
}
