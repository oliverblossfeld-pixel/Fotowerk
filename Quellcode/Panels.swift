import SwiftUI

/// Rechte Seitenleiste: Werkzeugwahl und das Bedienfeld des aktiven Werkzeugs.
@MainActor
struct InspectorView: View {
    @ObservedObject var editor: Editor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if editor.selected != nil { selectionActions }
                    switch editor.tool {
                    case .crop: CropPanel(editor: editor)
                    case .adjust: AdjustPanel(editor: editor)
                    case .filter: FilterPanel(editor: editor)
                    case .text: TextPanel(editor: editor)
                    case .sticker: StickerPanel(editor: editor)
                    case .brush: BrushPanel(editor: editor)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: editor.tool) { _, tool in
            if tool == .crop || tool == .brush { editor.selectedID = nil }
            if tool == .crop { editor.resetCrop() }
        }
    }

    private var selectionActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("Duplizieren") { editor.duplicateSelected() }
                Button("Löschen", role: .destructive) { editor.removeSelected() }
            }
            HStack {
                Button("Nach vorne") { editor.reorderSelected(toFront: true) }
                Button("Nach hinten") { editor.reorderSelected(toFront: false) }
            }
        }
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 8) {
            Text(title).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
            Slider(value: $value, in: range)
            Text("\(Int(value.rounded()))").monospacedDigit().frame(width: 38, alignment: .trailing)
        }
    }
}

// MARK: Zuschneiden

@MainActor
struct CropPanel: View {
    @ObservedObject var editor: Editor

    private static let aspects: [(name: String, value: CGFloat?)] = [
        ("Frei", nil), ("1:1", 1), ("4:5", 4.0 / 5), ("3:4", 3.0 / 4),
        ("9:16", 9.0 / 16), ("4:3", 4.0 / 3), ("16:9", 16.0 / 9),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58))], alignment: .leading, spacing: 6) {
                ForEach(CropPanel.aspects, id: \.name) { item in
                    Button(item.name) { editor.setAspect(item.value) }
                        .buttonStyle(.bordered)
                        .tint(item.value == editor.aspect ? teal : nil)
                }
            }
            Text("Ecken ziehen, um den Ausschnitt zu ändern; im Rahmen ziehen, um ihn zu verschieben.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Zuschnitt anwenden") { editor.applyCrop() }
                .buttonStyle(.borderedProminent)
                .disabled(editor.cropIsFull)
            Divider()
            HStack {
                Button { editor.rotate(clockwise: false) } label: { Label("Links", systemImage: "rotate.left") }
                Button { editor.rotate(clockwise: true) } label: { Label("Rechts", systemImage: "rotate.right") }
            }
            HStack {
                Button { editor.flip(horizontal: true) } label: {
                    Label("Spiegeln", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                }
                Button { editor.flip(horizontal: false) } label: {
                    Label("Kippen", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down")
                }
            }
        }
    }
}

// MARK: Anpassen

@MainActor
struct AdjustPanel: View {
    @ObservedObject var editor: Editor

    private func binding(_ path: WritableKeyPath<Adjust, Double>, _ key: String) -> Binding<Double> {
        Binding(
            get: { editor.doc?.adjust[keyPath: path] ?? 0 },
            set: { value in
                guard var d = editor.doc else { return }
                d.adjust[keyPath: path] = value
                editor.change(d, key: "adjust-" + key)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SliderRow(title: "Helligkeit", value: binding(\.brightness, "brightness"), range: -100...100)
            SliderRow(title: "Kontrast", value: binding(\.contrast, "contrast"), range: -100...100)
            SliderRow(title: "Sättigung", value: binding(\.saturation, "saturation"), range: -100...100)
            SliderRow(title: "Wärme", value: binding(\.warmth, "warmth"), range: -100...100)
            SliderRow(title: "Verblassen", value: binding(\.fade, "fade"), range: 0...100)
            SliderRow(title: "Vignette", value: binding(\.vignette, "vignette"), range: 0...100)
            Button("Zurücksetzen") {
                guard var d = editor.doc else { return }
                d.adjust = Adjust()
                editor.change(d)
            }
            .disabled(editor.doc?.adjust == Adjust())
        }
    }
}

// MARK: Filter

@MainActor
struct FilterPanel: View {
    @ObservedObject var editor: Editor

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
            ForEach(Array(Preset.all.enumerated()), id: \.element.id) { index, preset in
                let active = editor.doc?.preset == preset.id
                Button {
                    guard var d = editor.doc else { return }
                    d.preset = preset.id
                    editor.change(d)
                } label: {
                    VStack(spacing: 4) {
                        if index < editor.thumbs.count {
                            Image(decorative: editor.thumbs[index], scale: 1)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(active ? teal : Color.clear, lineWidth: 3)
                                )
                        }
                        Text(preset.name).font(.caption).foregroundStyle(active ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: Text

@MainActor
struct TextPanel: View {
    @ObservedObject var editor: Editor

    private var style: TextStyle? {
        if let o = editor.selected, case .text(let t) = o.content { return t }
        return nil
    }

    private func binding<T>(_ path: WritableKeyPath<TextStyle, T>, _ key: String, _ fallback: T) -> Binding<T> {
        Binding(
            get: { style?[keyPath: path] ?? fallback },
            set: { value in
                guard var o = editor.selected, case .text(var t) = o.content else { return }
                t[keyPath: path] = value
                o.content = .text(t)
                editor.replace(o, key: "text-\(o.id)-\(key)")
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if style != nil {
                TextField("Dein Text", text: binding(\.text, "text", ""), axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                ColorPicker("Farbe", selection: binding(\.color, "color", .white), supportsOpacity: false)
                Picker("Schrift", selection: binding(\.font, "font", "sans")) {
                    ForEach(Schrift.all, id: \.id) { font in
                        Text(font.name).tag(font.id)
                    }
                }
                Toggle("Fett", isOn: binding(\.bold, "bold", false))
                Toggle("Kontur", isOn: binding(\.outline, "outline", false))
                SizeRow(editor: editor, maximum: Double(editor.side / 2))
                Divider()
                Button("Weiteren Text hinzufügen") { editor.addText() }
            } else {
                Button("Text hinzufügen") { editor.addText() }
                    .buttonStyle(.borderedProminent)
                Text("Einen Text im Bild anklicken, um ihn zu bearbeiten. Am Griff lässt er sich skalieren und drehen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Größenregler für das ausgewählte Objekt.
@MainActor
struct SizeRow: View {
    @ObservedObject var editor: Editor
    let maximum: Double

    var body: some View {
        let current = Double(editor.selected?.size ?? 8)
        SliderRow(
            title: "Größe",
            value: Binding(
                get: { current },
                set: { value in
                    guard var o = editor.selected else { return }
                    o.size = CGFloat(value)
                    editor.replace(o, key: "size-\(o.id)")
                }
            ),
            range: 8...max(maximum, current, 9)
        )
    }
}

// MARK: Sticker

@MainActor
struct StickerPanel: View {
    @ObservedObject var editor: Editor

    private static let glyphs = "😀 😂 😍 😎 🥳 😭 😡 🤔 👍 👏 🙌 💪 ❤️ 🧡 💛 💚 💙 💜 🔥 ✨ ⭐ 🌈 ☀️ 🌙 ⚡ 💥 🎉 🎈 🎁 🏆 👑 💎 🌸 🌹 🌻 🍀 🌴 🐶 🐱 🦄 🦋 🍕 🍔 🍦 🍩 ☕ 🎵 📸 ✈️ 🚀 💬 💯 ✅ ❌ ➡️ ⬅️"
        .components(separatedBy: " ")

    private var stickerSelected: Bool {
        if let o = editor.selected, case .sticker = o.content { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if stickerSelected {
                SizeRow(editor: editor, maximum: Double(editor.side))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 4) {
                ForEach(StickerPanel.glyphs, id: \.self) { glyph in
                    Button { editor.addSticker(glyph) } label: {
                        Text(glyph).font(.system(size: 26)).frame(width: 40, height: 38)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: Pinsel

@MainActor
struct BrushPanel: View {
    @ObservedObject var editor: Editor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ColorPicker("Farbe", selection: $editor.brushColor, supportsOpacity: false)
            SliderRow(title: "Stärke", value: $editor.brushWidth, range: 2...80)
            Text("Mit gedrückter Maustaste direkt auf dem Bild malen.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Letzten Strich entfernen") { editor.removeLastStroke() }
                .disabled(!editor.lastIsStroke)
        }
    }
}
