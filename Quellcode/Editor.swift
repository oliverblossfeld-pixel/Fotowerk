import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Tool: String, CaseIterable, Identifiable {
    case crop, adjust, filter, text, sticker, brush

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crop: return "Zuschneiden"
        case .adjust: return "Anpassen"
        case .filter: return "Filter"
        case .text: return "Text"
        case .sticker: return "Sticker"
        case .brush: return "Pinsel"
        }
    }

    var subtitle: String {
        switch self {
        case .crop: return "Ausschnitt wählen, drehen und spiegeln"
        case .adjust: return "Helligkeit, Kontrast und Farben einstellen"
        case .filter: return "Einen fertigen Look auswählen"
        case .text: return "Text hinzufügen und gestalten"
        case .sticker: return "Sticker auf dem Bild platzieren"
        case .brush: return "Frei auf dem Bild malen"
        }
    }

    var icon: String {
        switch self {
        case .crop: return "crop"
        case .adjust: return "slider.horizontal.3"
        case .filter: return "camera.filters"
        case .text: return "textformat"
        case .sticker: return "face.smiling"
        case .brush: return "paintbrush.pointed"
        }
    }
}

/// Zustand des Editors: aktuelles Dokument, Verlauf, Auswahl und Werkzeug.
@MainActor
final class Editor: ObservableObject {
    @Published private(set) var doc: Snapshot?
    /// Farbkorrigiertes Grundbild in Vorschaugröße.
    @Published private(set) var preview: CGImage?
    /// Vorschaubilder der Filter, in der Reihenfolge von `Preset.all`.
    @Published private(set) var thumbs: [CGImage] = []
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    @Published var selectedID: UUID?
    @Published var tool: Tool = .adjust
    @Published var crop: CGRect = .zero
    @Published var aspect: CGFloat?
    @Published var brushColor = Color(red: 1, green: 0.23, blue: 0.36)
    @Published var brushWidth = 14.0
    @Published var errorText: String?

    private var past: [Snapshot] = []
    private var future: [Snapshot] = []
    private var previewBase: CGImage?
    private var lastKey: String?
    private var lastTime = Date.distantPast
    private var gestureCount = 0

    // MARK: Auswahl

    var selected: ObjectLayer? {
        guard let doc, let id = selectedID else { return nil }
        for layer in doc.layers {
            if case .object(let o) = layer, o.id == id { return o }
        }
        return nil
    }

    /// Kürzere Bildseite – Bezugsgröße für Schrift, Sticker und Pinsel.
    var side: CGFloat {
        guard let doc else { return 1000 }
        return min(doc.width, doc.height)
    }

    var lastIsStroke: Bool {
        if case .stroke = doc?.layers.last { return true }
        return false
    }

    func newGestureKey() -> String {
        gestureCount += 1
        return "g\(gestureCount)"
    }

    // MARK: Laden

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        guard let image = Bild.load(url) else {
            errorText = "„\(url.lastPathComponent)“ konnte nicht als Bild geöffnet werden."
            return
        }
        load(Snapshot(base: image))
    }

    func newBlank() {
        if let image = Bild.blank(width: 1080, height: 1350) { load(Snapshot(base: image)) }
    }

    private func load(_ snapshot: Snapshot) {
        past = []
        future = []
        lastKey = nil
        selectedID = nil
        tool = .adjust
        install(snapshot)
    }

    // MARK: Verlauf

    /// `key`: aufeinanderfolgende Änderungen mit gleichem Schlüssel zählen als ein Schritt.
    func change(_ new: Snapshot, key: String? = nil) {
        guard let current = doc else { return }
        let now = Date()
        var merge = false
        if let key, key == lastKey {
            // Gesten (Schlüssel "g…") immer zusammenfassen, Regler nur bei zügiger Folge.
            merge = key.hasPrefix("g") || now.timeIntervalSince(lastTime) < 1
        }
        if !merge {
            past.append(current)
            if past.count > 60 { past.removeFirst() }
            future = []
        }
        lastKey = key
        lastTime = now
        install(new)
    }

    func undo() {
        guard let current = doc, let previous = past.popLast() else { return }
        future.append(current)
        lastKey = nil
        install(previous)
    }

    func redo() {
        guard let current = doc, let next = future.popLast() else { return }
        past.append(current)
        lastKey = nil
        install(next)
    }

    private func install(_ new: Snapshot) {
        let old = doc
        doc = new
        if old?.base !== new.base {
            let small = Bild.scaled(new.base, maxSide: 1800)
            previewBase = small
            let tiny = Bild.scaled(small, maxSide: 160)
            thumbs = Preset.all.map { Bild.adjusted(tiny, ColorMatrix(look: $0.look)) }
            crop = new.centeredRect(aspect: aspect)
            preview = Bild.adjusted(small, new.matrix)
        } else if old?.adjust != new.adjust || old?.preset != new.preset {
            preview = Bild.adjusted(previewBase ?? new.base, new.matrix)
        }
        canUndo = !past.isEmpty
        canRedo = !future.isEmpty
    }

    // MARK: Ebenen

    func add(_ object: ObjectLayer) {
        guard var d = doc else { return }
        d.layers.append(.object(object))
        change(d)
        selectedID = object.id
    }

    func addText() {
        guard let doc else { return }
        let style = TextStyle(text: "Dein Text", color: .white, font: "sans", bold: true, outline: true)
        add(ObjectLayer(
            content: .text(style),
            center: CGPoint(x: doc.width / 2, y: doc.height / 2),
            size: (side / 9).rounded()
        ))
    }

    func addSticker(_ glyph: String) {
        guard let doc else { return }
        add(ObjectLayer(
            content: .sticker(glyph),
            center: CGPoint(x: doc.width / 2, y: doc.height / 2),
            size: (side / 4).rounded()
        ))
    }

    func addStroke(_ points: [CGPoint]) {
        guard var d = doc, !points.isEmpty else { return }
        d.layers.append(.stroke(Stroke(points: points, color: brushColor, width: brushDocWidth)))
        change(d)
    }

    /// Pinselstärke in Bildpixeln.
    var brushDocWidth: CGFloat {
        CGFloat(brushWidth) * side / 1000
    }

    func replace(_ object: ObjectLayer, key: String? = nil) {
        guard var d = doc else { return }
        d.layers = d.layers.map { $0.id == object.id ? .object(object) : $0 }
        change(d, key: key)
    }

    func removeSelected() {
        guard var d = doc, let s = selected else { return }
        d.layers.removeAll { $0.id == s.id }
        change(d)
        selectedID = nil
    }

    func duplicateSelected() {
        guard var copy = selected else { return }
        copy.id = UUID()
        copy.center.x += side * 0.05
        copy.center.y += side * 0.05
        add(copy)
    }

    func reorderSelected(toFront: Bool) {
        guard var d = doc, let s = selected else { return }
        d.layers.removeAll { $0.id == s.id }
        if toFront {
            d.layers.append(.object(s))
        } else {
            d.layers.insert(.object(s), at: 0)
        }
        change(d)
    }

    func removeLastStroke() {
        guard var d = doc, lastIsStroke else { return }
        d.layers.removeLast()
        change(d)
    }

    // MARK: Zuschneiden

    var cropIsFull: Bool {
        guard let doc else { return true }
        return crop.minX < 1 && crop.minY < 1 && crop.width > doc.width - 2 && crop.height > doc.height - 2
    }

    func setAspect(_ value: CGFloat?) {
        aspect = value
        resetCrop()
    }

    func resetCrop() {
        if let doc { crop = doc.centeredRect(aspect: aspect) }
    }

    func applyCrop() {
        if let new = doc?.cropped(to: crop) { change(new) }
    }

    func rotate(clockwise: Bool) {
        if let new = doc?.rotated(clockwise: clockwise) { change(new) }
    }

    func flip(horizontal: Bool) {
        if let new = doc?.flipped(horizontal: horizontal) { change(new) }
    }

    // MARK: Export

    func export(_ type: UTType) {
        guard let doc else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = "Fotowerk"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = Zeichnen.finalImage(doc, opaque: type == .jpeg), Bild.write(image, to: url, type: type) else {
            errorText = "Das Bild konnte nicht gespeichert werden."
            return
        }
    }
}
