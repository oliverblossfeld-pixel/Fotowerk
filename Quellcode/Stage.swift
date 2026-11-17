import SwiftUI

/// Die Leinwand: zeigt das Dokument und verarbeitet Maus-Gesten
/// (Auswählen, Verschieben, Skalieren/Drehen, Zuschnittrahmen, Malen).
@MainActor
struct StageView: View {
    @ObservedObject var editor: Editor
    @State private var live: [CGPoint] = []
    @State private var holder = DragHolder()

    private enum Drag {
        case idle
        case draw
        case move(orig: ObjectLayer, start: CGPoint, key: String)
        case handle(orig: ObjectLayer, d0: CGFloat, a0: CGFloat, key: String)
        case cropMove(orig: CGRect, start: CGPoint)
        case cropCorner(orig: CGRect, west: Bool, north: Bool)
    }

    /// Referenztyp, damit der Gestenzustand zwischen zwei Mausereignissen sofort verfügbar ist.
    private final class DragHolder {
        var drag: Drag?
        var points: [CGPoint] = []
    }

    var body: some View {
        GeometryReader { geo in
            if let doc = editor.doc, let preview = editor.preview {
                let fit = max(0.001, min((geo.size.width - 40) / doc.width, (geo.size.height - 40) / doc.height))
                let size = CGSize(width: doc.width * fit, height: doc.height * fit)
                let selected = editor.selected
                let tool = editor.tool
                let crop = editor.crop
                let liveStroke = live.isEmpty
                    ? nil
                    : Stroke(points: live, color: editor.brushColor, width: editor.brushDocWidth)

                Canvas { ctx, canvasSize in
                    Zeichnen.document(&ctx, image: preview, doc: doc, size: canvasSize, live: liveStroke)
                    var c = ctx
                    c.scaleBy(x: fit, y: fit)
                    let k = 1 / fit // Bildpixel pro Bildschirmpunkt
                    if let selected, tool != .crop, tool != .brush {
                        StageView.drawSelection(&c, selected, k: k)
                    }
                    if tool == .crop {
                        StageView.drawCrop(&c, crop, width: doc.width, height: doc.height, k: k)
                    }
                }
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            let p = CGPoint(x: value.location.x / fit, y: value.location.y / fit)
                            if holder.drag == nil {
                                let start = CGPoint(x: value.startLocation.x / fit, y: value.startLocation.y / fit)
                                holder.drag = begin(at: start, k: 1 / fit, doc: doc)
                            }
                            move(to: p, doc: doc)
                        }
                        .onEnded { _ in end() }
                )
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
    }

    // MARK: Gesten

    private func begin(at p: CGPoint, k: CGFloat, doc: Snapshot) -> Drag {
        switch editor.tool {
        case .brush:
            holder.points = []
            return .draw
        case .crop:
            let r = editor.crop
            let tolerance = 22 * k
            let corners: [(west: Bool, north: Bool, x: CGFloat, y: CGFloat)] = [
                (true, true, r.minX, r.minY),
                (false, true, r.maxX, r.minY),
                (true, false, r.minX, r.maxY),
                (false, false, r.maxX, r.maxY),
            ]
            for c in corners where hypot(p.x - c.x, p.y - c.y) < tolerance {
                return .cropCorner(orig: r, west: c.west, north: c.north)
            }
            return r.contains(p) ? .cropMove(orig: r, start: p) : .idle
        default:
            let key = editor.newGestureKey()
            if let s = editor.selected {
                let h = s.handle
                if hypot(p.x - h.x, p.y - h.y) < 16 * k {
                    return .handle(
                        orig: s,
                        d0: max(1, hypot(p.x - s.center.x, p.y - s.center.y)),
                        a0: atan2(p.y - s.center.y, p.x - s.center.x),
                        key: key
                    )
                }
            }
            for layer in doc.layers.reversed() {
                if case .object(let o) = layer, o.contains(p) {
                    editor.selectedID = o.id
                    switch o.content {
                    case .text: editor.tool = .text
                    case .sticker: editor.tool = .sticker
                    }
                    return .move(orig: o, start: p, key: key)
                }
            }
            editor.selectedID = nil
            return .idle
        }
    }

    private func move(to p: CGPoint, doc: Snapshot) {
        guard let drag = holder.drag else { return }
        let W = doc.width
        let H = doc.height
        switch drag {
        case .idle:
            break
        case .draw:
            holder.points.append(p)
            live = holder.points
        case .move(let orig, let start, let key):
            var o = orig
            o.center = CGPoint(x: orig.center.x + p.x - start.x, y: orig.center.y + p.y - start.y)
            editor.replace(o, key: key)
        case .handle(let orig, let d0, let a0, let key):
            var o = orig
            let d = hypot(p.x - orig.center.x, p.y - orig.center.y)
            let a = atan2(p.y - orig.center.y, p.x - orig.center.x)
            o.size = min(max(orig.size * d / d0, 8), max(W, H) * 2)
            o.rotation = orig.rotation + a - a0
            editor.replace(o, key: key)
        case .cropMove(let orig, let start):
            var r = orig
            r.origin.x = min(max(orig.minX + p.x - start.x, 0), W - orig.width)
            r.origin.y = min(max(orig.minY + p.y - start.y, 0), H - orig.height)
            editor.crop = r
        case .cropCorner(let orig, let west, let north):
            editor.crop = StageView.resize(orig, west: west, north: north, to: p, aspect: editor.aspect, W: W, H: H)
        }
    }

    private func end() {
        if case .draw = holder.drag {
            editor.addStroke(holder.points)
        }
        holder.drag = nil
        holder.points = []
        live = []
    }

    private static func resize(
        _ o: CGRect, west: Bool, north: Bool, to p: CGPoint, aspect: CGFloat?, W: CGFloat, H: CGFloat
    ) -> CGRect {
        // Die gegenüberliegende Ecke bleibt fest.
        let fx = west ? o.maxX : o.minX
        let fy = north ? o.maxY : o.minY
        let dx: CGFloat = west ? -1 : 1
        let dy: CGFloat = north ? -1 : 1
        let minimum = min(W, H) * 0.05
        let maxW = west ? fx : W - fx
        let maxH = north ? fy : H - fy
        var w = max(minimum, (min(max(p.x, 0), W) - fx) * dx)
        var h = max(minimum, (min(max(p.y, 0), H) - fy) * dy)
        if let aspect {
            w = min(max(w, h * aspect), maxW, maxH * aspect)
            h = w / aspect
        } else {
            w = min(w, maxW)
            h = min(h, maxH)
        }
        return CGRect(x: west ? fx - w : fx, y: north ? fy - h : fy, width: w, height: h)
    }

    // MARK: Überlagerungen

    private static func drawSelection(_ ctx: inout GraphicsContext, _ o: ObjectLayer, k: CGFloat) {
        var g = ctx
        g.translateBy(x: o.center.x, y: o.center.y)
        g.rotate(by: .radians(Double(o.rotation)))
        let b = o.boxSize
        let frame = Path(CGRect(x: -b.width / 2, y: -b.height / 2, width: b.width, height: b.height))
        g.stroke(frame, with: .color(.black.opacity(0.45)), lineWidth: 3 * k)
        g.stroke(frame, with: .color(.white), style: StrokeStyle(lineWidth: 1.5 * k, dash: [6 * k, 4 * k]))
        let r = 7 * k
        let knob = Path(ellipseIn: CGRect(x: b.width / 2 - r, y: b.height / 2 - r, width: 2 * r, height: 2 * r))
        g.fill(knob, with: .color(teal))
        g.stroke(knob, with: .color(.white), lineWidth: 2 * k)
    }

    private static func drawCrop(_ ctx: inout GraphicsContext, _ r: CGRect, width W: CGFloat, height H: CGFloat, k: CGFloat) {
        let dim = GraphicsContext.Shading.color(.black.opacity(0.6))
        ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: r.minY)), with: dim)
        ctx.fill(Path(CGRect(x: 0, y: r.maxY, width: W, height: H - r.maxY)), with: dim)
        ctx.fill(Path(CGRect(x: 0, y: r.minY, width: r.minX, height: r.height)), with: dim)
        ctx.fill(Path(CGRect(x: r.maxX, y: r.minY, width: W - r.maxX, height: r.height)), with: dim)

        var grid = Path()
        for i in 1..<3 {
            let x = r.minX + r.width * CGFloat(i) / 3
            let y = r.minY + r.height * CGFloat(i) / 3
            grid.move(to: CGPoint(x: x, y: r.minY))
            grid.addLine(to: CGPoint(x: x, y: r.maxY))
            grid.move(to: CGPoint(x: r.minX, y: y))
            grid.addLine(to: CGPoint(x: r.maxX, y: y))
        }
        ctx.stroke(grid, with: .color(.white.opacity(0.45)), lineWidth: k)
        ctx.stroke(Path(r), with: .color(.white), lineWidth: 2 * k)

        let s = 12 * k
        for corner in [
            CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
        ] {
            ctx.fill(Path(CGRect(x: corner.x - s / 2, y: corner.y - s / 2, width: s, height: s)), with: .color(.white))
        }
    }
}
