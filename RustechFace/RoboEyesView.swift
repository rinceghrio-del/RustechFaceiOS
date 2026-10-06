import SwiftUI
import UIKit

enum EyeMood { case idle, alert, searching, angry }

/// Port ng RoboEyesView.kt (Android) - cyan na robot eyes na kumukurap, lumilingon,
/// at may mood: IDLE, ALERT (happy eyes), SEARCHING, ANGRY.
final class RoboEyesUIView: UIView {

    var mood: EyeMood = .idle {
        didSet {
            if oldValue != mood { scheduleNextLookChange() }
        }
    }

    // ---- Dito i-adjust ang itsura (parehong values sa Android) ----
    private let eyeWidthScale: CGFloat = 1.25
    private let eyeHeightScale: CGFloat = 1.10
    private let happySmile: CGFloat = 0.40
    private let angryLid: CGFloat = 0.55

    private let eyeColor = UIColor(red: 0, green: 229.0 / 255.0, blue: 1.0, alpha: 1.0)

    private var blinkAmount: CGFloat = 0
    private var happyAmount: CGFloat = 0
    private var angryAmount: CGFloat = 0
    private var lookX: CGFloat = 0
    private var lookY: CGFloat = 0
    private var lookTargetX: CGFloat = 0
    private var lookTargetY: CGFloat = 0
    private var nextBlinkAtMs: Double = 0
    private var nextLookChangeAtMs: Double = 0
    private var blinkPhase = 0 // 0 idle, 1 closing, 2 opening

    private var displayLink: CADisplayLink?

    private final class LinkProxy: NSObject {
        weak var target: RoboEyesUIView?
        @objc func tick() { target?.tick() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isOpaque = true
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { startLoop() } else { stopLoop() }
    }

    private func nowMs() -> Double { CACurrentMediaTime() * 1000.0 }

    private func startLoop() {
        guard displayLink == nil else { return }
        scheduleNextBlink()
        scheduleNextLookChange()
        let proxy = LinkProxy()
        proxy.target = self
        let link = CADisplayLink(target: proxy, selector: #selector(LinkProxy.tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopLoop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func scheduleNextBlink() {
        nextBlinkAtMs = nowMs() + Double.random(in: 1400...3800)
    }

    private func scheduleNextLookChange() {
        nextLookChangeAtMs = nowMs() + Double.random(in: 1500...3800)
        if mood == .searching {
            lookTargetX = CGFloat.random(in: -1...1)
        } else {
            lookTargetX = CGFloat.random(in: -0.6...0.6)
        }
        lookTargetY = CGFloat.random(in: -0.3...0.3)
    }

    fileprivate func tick() {
        let now = nowMs()

        // Blink state machine
        if blinkPhase == 0 && now >= nextBlinkAtMs { blinkPhase = 1 }
        switch blinkPhase {
        case 1:
            blinkAmount += 0.26
            if blinkAmount >= 1 { blinkAmount = 1; blinkPhase = 2 }
        case 2:
            blinkAmount -= 0.26
            if blinkAmount <= 0 { blinkAmount = 0; blinkPhase = 0; scheduleNextBlink() }
        default:
            break
        }

        // Idle look-around
        if now >= nextLookChangeAtMs { scheduleNextLookChange() }
        lookX += (lookTargetX - lookX) * 0.07
        lookY += (lookTargetY - lookY) * 0.07

        // Happy eyes
        let happyTarget: CGFloat = (mood == .alert) ? 1 : 0
        happyAmount += (happyTarget - happyAmount) * 0.2
        if abs(happyTarget - happyAmount) < 0.01 { happyAmount = happyTarget }

        // Angry eyes
        let angryTarget: CGFloat = (mood == .angry) ? 1 : 0
        angryAmount += (angryTarget - angryAmount) * 0.25
        if abs(angryTarget - angryAmount) < 0.01 { angryAmount = angryTarget }

        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let w = bounds.width
        let h = bounds.height

        UIColor.black.setFill()
        UIBezierPath(rect: bounds).fill()

        let eyeHeight = h * 0.28 * eyeHeightScale
        let eyeWidth = w * 0.22 * eyeWidthScale
        let spacing = w * 0.10

        let centerY = h / 2 + lookY * h * 0.08
        let shiftX = lookX * w * 0.06

        let leftCenterX = w / 2 - spacing / 2 - eyeWidth / 2 + shiftX
        let rightCenterX = w / 2 + spacing / 2 + eyeWidth / 2 + shiftX

        let currentEyeHeight = eyeHeight * max(1 - blinkAmount, 0.06)
        let cornerRadius = currentEyeHeight * 0.35

        drawEye(cx: leftCenterX, cy: centerY, w: eyeWidth, h: currentEyeHeight, radius: cornerRadius, isLeft: true)
        drawEye(cx: rightCenterX, cy: centerY, w: eyeWidth, h: currentEyeHeight, radius: cornerRadius, isLeft: false)
    }

    private func drawEye(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat, radius: CGFloat, isLeft: Bool) {
        let rect = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        eyeColor.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()

        // HAPPY: itim na "lower eyelid" na tumataas mula sa ibaba -> arko/ngiti
        if happyAmount > 0 {
            let offset = h * happySmile * happyAmount
            let pad = w * 0.03
            let cover = CGRect(x: cx - w / 2 - pad, y: cy + h / 2 - offset, width: w + pad * 2, height: h)
            UIColor.black.setFill()
            UIBezierPath(roundedRect: cover, cornerRadius: radius).fill()
        }

        // ANGRY: itim na tatsulok sa itaas na mas mababa sa loob (ilong side) -> nakakunot ang noo
        if angryAmount > 0 {
            let lidH = h * angryLid * angryAmount
            let left = cx - w / 2 - 2
            let right = cx + w / 2 + 2
            let top = cy - h / 2 - 2
            let path = UIBezierPath()
            path.move(to: CGPoint(x: left, y: top))
            path.addLine(to: CGPoint(x: right, y: top))
            if isLeft {
                path.addLine(to: CGPoint(x: right, y: top + lidH + 2))
            } else {
                path.addLine(to: CGPoint(x: left, y: top + lidH + 2))
            }
            path.close()
            UIColor.black.setFill()
            path.fill()
        }
    }
}

struct RoboEyesView: UIViewRepresentable {
    var mood: EyeMood

    func makeUIView(context: Context) -> RoboEyesUIView {
        RoboEyesUIView()
    }

    func updateUIView(_ uiView: RoboEyesUIView, context: Context) {
        uiView.mood = mood
    }
}
