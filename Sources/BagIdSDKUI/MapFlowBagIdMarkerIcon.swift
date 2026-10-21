import BagIdSDK
import SwiftUI
import UIKit

/// Map pin: white disc, BagID glyph (aspect-fit), small pointed tip.
enum MapFlowBagIdMarkerIcon {
    static let groundAnchor = CGPoint(x: 0.5, y: 0.92)

    /// Rendered pins keyed by (selected, live).
    private static var cache: [String: UIImage] = [:]
    private static var bagCache: UIImage?

    static func image(isPrimary: Bool, live: Bool = false) -> UIImage {
        let key = "\(isPrimary)-\(live)"
        if let cached = cache[key] { return cached }
        let made = render(isPrimary: isPrimary, live: live)
        cache[key] = made
        return made
    }

    /// A distinct image per pin. Sharing one `UIImage` across `GMSMarker`s drops the later pins.
    static func markerImage(isPrimary: Bool, live: Bool = false) -> UIImage {
        let image = image(isPrimary: isPrimary, live: live)
        guard let cgImage = image.cgImage else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    static func bagUIImage() -> UIImage? {
        if let bagCache { return bagCache }
        for bundle in [Bundle.module, Bundle.main] {
            if let image = UIImage(named: "map_pin_bagid", in: bundle, compatibleWith: nil) {
                bagCache = image
                return image
            }
        }
        return nil
    }

    private static func render(isPrimary: Bool, live: Bool) -> UIImage {
        let pinWidth: CGFloat = isPrimary ? 56 : 48
        let tipHeight: CGFloat = isPrimary ? 10 : 8
        let shadowPad: CGFloat = 5
        let canvas = CGSize(
            width: pinWidth + shadowPad * 2,
            height: pinWidth + tipHeight + shadowPad * 2 + 2,
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { ctx in
            let pinRect = CGRect(
                x: shadowPad,
                y: shadowPad,
                width: pinWidth,
                height: pinWidth + tipHeight,
            )
            let path = pinPath(in: pinRect)

            ctx.cgContext.setShadow(
                offset: CGSize(width: 0, height: 1.5),
                blur: 3,
                color: UIColor.black.withAlphaComponent(0.22).cgColor,
            )
            UIColor.white.setFill()
            path.fill()
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

            if isPrimary {
                UIColor(MapFlowTheme.accent).setStroke()
                path.lineWidth = 2.5
                path.stroke()
            }

            let circleRect = CGRect(x: shadowPad, y: shadowPad, width: pinWidth, height: pinWidth)
            drawBag(in: circleRect, maxFraction: 0.58)

            if live {
                // Live badge: accent dot with a white ring on the pin's top-right edge.
                let radius = pinWidth / 2
                let center = CGPoint(x: circleRect.midX + radius * 0.72, y: circleRect.midY - radius * 0.72)
                let dot: CGFloat = 7
                UIColor.white.setFill()
                UIBezierPath(arcCenter: center, radius: dot + 2, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
                UIColor(MapFlowTheme.accent).setFill()
                UIBezierPath(arcCenter: center, radius: dot, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
            }
        }
    }

    private static func pinPath(in rect: CGRect) -> UIBezierPath {
        let radius = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.minY + radius)
        let joinSpread: CGFloat = 0.38
        let leftAngle = CGFloat.pi / 2 + joinSpread
        let rightAngle = CGFloat.pi / 2 - joinSpread
        let left = CGPoint(
            x: center.x + radius * cos(leftAngle),
            y: center.y + radius * sin(leftAngle),
        )
        let tip = CGPoint(x: rect.midX, y: rect.maxY)

        let path = UIBezierPath()
        path.move(to: tip)
        path.addLine(to: left)
        path.addArc(
            withCenter: center,
            radius: radius,
            startAngle: leftAngle,
            endAngle: rightAngle,
            clockwise: true,
        )
        path.addLine(to: tip)
        path.close()
        return path
    }

    private static func drawBag(in circleRect: CGRect, maxFraction: CGFloat) {
        let bag = bagUIImage() ?? fallbackSuitcase(size: circleRect.width * maxFraction)
        let size = bag.size
        guard size.width > 0, size.height > 0 else { return }
        let maxW = circleRect.width * maxFraction
        let maxH = circleRect.height * maxFraction
        let scale = min(maxW / size.width, maxH / size.height)
        let drawW = size.width * scale
        let drawH = size.height * scale
        let drawRect = CGRect(
            x: circleRect.midX - drawW / 2,
            y: circleRect.midY - drawH / 2,
            width: drawW,
            height: drawH,
        )
        bag.draw(in: drawRect)
    }

    private static func fallbackSuitcase(size: CGFloat) -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: size * 0.72, weight: .medium)
        return UIImage(systemName: "suitcase.fill", withConfiguration: config)?
            .withTintColor(
                UIColor(red: 20 / 255, green: 97 / 255, blue: 109 / 255, alpha: 1),
                renderingMode: .alwaysOriginal,
            )
            ?? UIImage()
    }
}

struct MapFlowBagIdGlyph: View {
    var maxSide: CGFloat = 26

    var body: some View {
        Group {
            if let image = MapFlowBagIdMarkerIcon.bagUIImage() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "suitcase.fill")
                    .foregroundStyle(Color(red: 20 / 255, green: 97 / 255, blue: 109 / 255))
            }
        }
        .frame(width: maxSide * 21 / 31, height: maxSide)
    }
}

enum MapFlowDeviceChrome {
    static func iconCircleFill(isHighlighted: Bool) -> Color {
        isHighlighted ? MapFlowTheme.accent : MapFlowTheme.background.opacity(0.12)
    }

    static func listStatusDotColor(isWithYou: Bool) -> Color {
        isWithYou ? Color(red: 232 / 255, green: 93 / 255, blue: 58 / 255) : Color(red: 180 / 255, green: 180 / 255, blue: 185 / 255)
    }

    static func hasListSerial(_ device: MapDevice) -> Bool {
        let sn = device.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return !sn.isEmpty && sn != "—"
    }
}
