import AppKit
import SwiftUI

/// Zeichnet ein Dokument – dieselbe Routine für die Vorschau und den Export.
enum Zeichnen {
    /// `image` ist das bereits farbkorrigierte Grundbild; es wird auf `size` gestreckt.
    static func document(_ ctx: inout GraphicsContext, image: CGImage, doc: Snapshot, size: CGSize, live: Stroke? = nil) {
        let rect = CGRect(origin: .zero, size: size)
        ctx.draw(Image(decorative: image, scale: 1).interpolation(.high), in: rect)

        if doc.adjust.vignette > 0 {
            let r = hypot(size.width, size.height) / 2
            let gradient = Gradient(stops: [
                .init(color: .black.opacity(0), location: 0),
                .init(color: .black.opacity(doc.adjust.vignette / 100 * 0.85), location: 1),
            ])
            ctx.fill(
                Path(rect),
                with: .radialGradient(
                    gradient,
                    center: CGPoint(x: size.width / 2, y: size.height / 2),
                    startRadius: r * 0.35,
                    endRadius: r
                )
            )
        }

        var c = ctx
        c.scaleBy(x: size.width / doc.width, y: size.height / doc.height)
        for layer in doc.layers {
            switch layer {
            case .stroke(let s): stroke(&c, s)
            case .object(let o): object(&c, o)
            }
        }
        if let live { stroke(&c, live) }
    }

    static func stroke(_ ctx: inout GraphicsContext, _ s: Stroke) {
        let p = s.points
        guard let first = p.first else { return }
        if p.count == 1 {
            let r = s.width / 2
            ctx.fill(Path(ellipseIn: CGRect(x: first.x - r, y: first.y - r, width: s.width, height: s.width)), with: .color(s.color))
            return
        }
        var path = Path()
        path.move(to: first)
        if p.count > 2 {
            // geglättet: Kurve durch die Mittelpunkte
            for i in 1..<(p.count - 1) {
                let mid = CGPoint(x: (p[i].x + p[i + 1].x) / 2, y: (p[i].y + p[i + 1].y) / 2)
                path.addQuadCurve(to: mid, control: p[i])
            }
        }
        path.addLine(to: p[p.count - 1])
        ctx.stroke(path, with: .color(s.color), style: StrokeStyle(lineWidth: s.width, lineCap: .round, lineJoin: .round))
    }

    static func object(_ ctx: inout GraphicsContext, _ o: ObjectLayer) {
        var g = ctx
        g.translateBy(x: o.center.x, y: o.center.y)
        g.rotate(by: .radians(Double(o.rotation)))
        switch o.content {
        case .sticker(let glyph):
            g.draw(Text(glyph).font(.system(size: o.size)), at: .zero)
        case .text(let t):
            let font = Font(Schrift.nsFont(t.font, size: o.size, bold: t.bold) as CTFont)
            let lines = t.text.components(separatedBy: "\n")
            let step = o.size * Schrift.lineHeight
            let y0 = -CGFloat(lines.count - 1) * step / 2
            if t.outline {
                let edge = contrast(to: t.color)
                let d = o.size / 14
                for (i, line) in lines.enumerated() {
                    let text = Text(line).font(font).foregroundColor(edge)
                    for n in 0..<12 {
                        let a = CGFloat(n) / 12 * 2 * .pi
                        g.draw(text, at: CGPoint(x: cos(a) * d, y: y0 + CGFloat(i) * step + sin(a) * d))
                    }
                }
            }
            for (i, line) in lines.enumerated() {
                g.draw(Text(line).font(font).foregroundColor(t.color), at: CGPoint(x: 0, y: y0 + CGFloat(i) * step))
            }
        }
    }

    private static func contrast(to color: Color) -> Color {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return .black }
        let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return lum > 0.55 ? .black : .white
    }

    /// Fertiges Bild in voller Auflösung.
    @MainActor
    static func finalImage(_ doc: Snapshot, opaque: Bool) -> CGImage? {
        let image = Bild.adjusted(doc.base, doc.matrix)
        let size = CGSize(width: doc.width, height: doc.height)
        let view = Canvas { ctx, canvasSize in
            if opaque {
                ctx.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(.white))
            }
            Zeichnen.document(&ctx, image: image, doc: doc, size: canvasSize)
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = opaque
        return renderer.cgImage
    }
}
