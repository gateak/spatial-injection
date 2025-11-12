import UIKit

final class DetectionOverlayView: UIView {
    var observations: [CGRect] = [] { didSet { setNeedsDisplay() } }
    
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setLineWidth(2)
        UIColor.systemRed.setStroke()
        for box in observations {
            ctx.stroke(box)
        }
    }
}
