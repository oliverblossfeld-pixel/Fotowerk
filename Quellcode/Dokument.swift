import AppKit
import SwiftUI

struct Adjust: Equatable {
    var brightness = 0.0
    var contrast = 0.0
    var saturation = 0.0
    var warmth = 0.0
    var fade = 0.0
    var vignette = 0.0
}

struct TextStyle: Equatable {
    var text: String
    var color: Color
    var font: String
    var bold: Bool
    var outline: Bool
}

/// Verschieb-, skalier- und drehbares Objekt (Text oder Sticker). Koordinaten in Bildpixeln.
struct ObjectLayer: Identifiable, Equatable {
    enum Content: Equatable {
        case text(TextStyle)
        case sticker(String)
    }

    var id = UUID()
    var content: Content
    var center: CGPoint
    var size: CGFloat
    /// Drehung im Bogenmaß, im Uhrzeigersinn.
    var rotation: CGFloat = 0

    /// Größe des unrotierten Rahmens in Bildpixeln.
    var boxSize: CGSize {
        switch content {
        case .sticker:
            return CGSize(width: size * 1.25, height: size * 1.25)
        case .text(let t):
            let font = Schrift.nsFont(t.font, size: size, bold: t.bold)
            let lines = t.text.components(separatedBy: "\n")
            var w = size * 0.5
            for line in lines {
                w = max(w, (line as NSString).size(withAttributes: [.font: font]).width)
            }
            return CGSize(width: w + size * 0.4, height: CGFloat(lines.count) * size * Schrift.lineHeight + size * 0.15)
        }
    }

    /// Position des Griffs (untere rechte Ecke) in Bildpixeln.
    var handle: CGPoint {
        let b = boxSize
        let c = cos(rotation)
        let s = sin(rotation)
        return CGPoint(
            x: center.x + b.width / 2 * c - b.height / 2 * s,
            y: center.y + b.width / 2 * s + b.height / 2 * c
        )
    }

    func contains(_ p: CGPoint) -> Bool {
        let b = boxSize
        let c = cos(-rotation)
        let s = sin(-rotation)
        let dx = p.x - center.x
        let dy = p.y - center.y
        return abs(dx * c - dy * s) <= b.width / 2 && abs(dx * s + dy * c) <= b.height / 2
    }
}

struct Stroke: Identifiable, Equatable {
    var id = UUID()
    var points: [CGPoint]
    var color: Color
    var width: CGFloat
}

enum Layer: Identifiable, Equatable {
    case object(ObjectLayer)
    case stroke(Stroke)

    var id: UUID {
        switch self {
        case .object(let o): return o.id
        case .stroke(let s): return s.id
        }
    }
}

/// Ein Bearbeitungsstand. Jede Änderung erzeugt einen neuen Stand (Grundlage für Widerrufen).
struct Snapshot {
    var base: CGImage
    var adjust = Adjust()
    var preset = "original"
    var layers: [Layer] = []

    var width: CGFloat { CGFloat(base.width) }
    var height: CGFloat { CGFloat(base.height) }

    var matrix: ColorMatrix {
        let look = Look(
            brightness: adjust.brightness,
            contrast: adjust.contrast,
            saturation: adjust.saturation,
            warmth: adjust.warmth,
            fade: adjust.fade
        )
        let preset = Preset.all.first { $0.id == self.preset }?.look ?? Look()
        return ColorMatrix(look: look).after(ColorMatrix(look: preset))
    }

    // MARK: Geometrie

    private func mapped(_ point: (CGPoint) -> CGPoint, _ rotation: (CGFloat) -> CGFloat) -> [Layer] {
        layers.map { layer in
            switch layer {
            case .stroke(var s):
                s.points = s.points.map(point)
                return .stroke(s)
            case .object(var o):
                o.center = point(o.center)
                o.rotation = rotation(o.rotation)
                return .object(o)
            }
        }
    }

    func rotated(clockwise: Bool) -> Snapshot? {
        guard let image = Bild.rotated(base, clockwise: clockwise) else { return nil }
        let W = width
        let H = height
        var s = self
        s.base = image
        s.layers = clockwise
            ? mapped({ CGPoint(x: H - $0.y, y: $0.x) }, { $0 + .pi / 2 })
            : mapped({ CGPoint(x: $0.y, y: W - $0.x) }, { $0 - .pi / 2 })
        return s
    }

    func flipped(horizontal: Bool) -> Snapshot? {
        guard let image = Bild.flipped(base, horizontal: horizontal) else { return nil }
        let W = width
        let H = height
        var s = self
        s.base = image
        s.layers = horizontal
            ? mapped({ CGPoint(x: W - $0.x, y: $0.y) }, { -$0 })
            : mapped({ CGPoint(x: $0.x, y: H - $0.y) }, { -$0 })
        return s
    }

    func cropped(to rect: CGRect) -> Snapshot? {
        let r = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard r.width >= 1, r.height >= 1, let image = Bild.cropped(base, to: r) else { return nil }
        var s = self
        s.base = image
        s.layers = mapped({ CGPoint(x: $0.x - r.minX, y: $0.y - r.minY) }, { $0 })
        return s
    }

    /// Größtes mittiges Rechteck mit dem Seitenverhältnis `aspect` (Breite/Höhe); nil = ganzes Bild.
    func centeredRect(aspect: CGFloat?) -> CGRect {
        guard let aspect else { return CGRect(x: 0, y: 0, width: width, height: height) }
        var w = width
        var h = width / aspect
        if h > height {
            h = height
            w = height * aspect
        }
        return CGRect(x: (width - w) / 2, y: (height - h) / 2, width: w, height: h)
    }
}

enum Schrift {
    static let lineHeight: CGFloat = 1.2

    static let all: [(id: String, name: String)] = [
        ("sans", "Klar"),
        ("serif", "Serif"),
        ("rund", "Rund"),
        ("plakat", "Plakat"),
        ("schrift", "Schreibschrift"),
        ("mono", "Mono"),
    ]

    static func nsFont(_ id: String, size: CGFloat, bold: Bool) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        switch id {
        case "serif":
            return NSFont(name: bold ? "Georgia-Bold" : "Georgia", size: size) ?? system
        case "rund":
            if let d = system.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) {
                return f
            }
            return system
        case "plakat":
            return NSFont(name: "Impact", size: size) ?? system
        case "schrift":
            return NSFont(name: bold ? "SnellRoundhand-Bold" : "SnellRoundhand", size: size) ?? system
        case "mono":
            return NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        default:
            return system
        }
    }
}
