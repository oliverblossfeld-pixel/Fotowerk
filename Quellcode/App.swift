import SwiftUI
import UniformTypeIdentifiers

@main
@MainActor
struct FotowerkApp: App {
    @StateObject private var editor = Editor()

    var body: some Scene {
        Window("Fotowerk", id: "main") {
            ContentView(editor: editor)
                .frame(minWidth: 960, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Öffnen …") { editor.openPanel() }
                    .keyboardShortcut("o")
                Button("Leere Leinwand") { editor.newBlank() }
                    .keyboardShortcut("n")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Als PNG exportieren …") { editor.export(.png) }
                    .keyboardShortcut("e")
                    .disabled(editor.doc == nil)
                Button("Als JPG exportieren …") { editor.export(.jpeg) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(editor.doc == nil)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Widerrufen") { editor.undo() }
                    .keyboardShortcut("z")
                    .disabled(!editor.canUndo)
                Button("Wiederholen") { editor.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!editor.canRedo)
            }
            CommandMenu("Ebene") {
                Button("Duplizieren") { editor.duplicateSelected() }
                    .keyboardShortcut("d")
                    .disabled(editor.selected == nil)
                Button("Löschen") { editor.removeSelected() }
                    .keyboardShortcut(.delete)
                    .disabled(editor.selected == nil)
            }
        }
    }
}

/// Akzentfarbe – dieselbe wie in Blattwerk.
let teal = Color(red: 0.08, green: 0.43, blue: 0.40)

@MainActor
struct ContentView: View {
    @ObservedObject var editor: Editor
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                if editor.doc == nil {
                    dropZone
                } else {
                    HStack(spacing: 0) {
                        StageView(editor: editor)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider()
                        InspectorView(editor: editor)
                            .frame(width: 290)
                    }
                }
                Divider()
                footer
            }
        }
        .tint(teal)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            editor.open(url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .alert(
            "Fotowerk",
            isPresented: Binding(get: { editor.errorText != nil }, set: { if !$0 { editor.errorText = nil } })
        ) {
            Button("OK") { editor.errorText = nil }
        } message: {
            Text(editor.errorText ?? "")
        }
    }

    // MARK: Seitenleiste

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Fotowerk", systemImage: "camera.aperture").font(.title2.bold()).foregroundStyle(teal)
            Button { editor.openPanel() } label: { Label("Foto öffnen …", systemImage: "photo.on.rectangle") }
                .controlSize(.large)
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Tool.allCases) { tool in
                    let active = editor.doc != nil && editor.tool == tool
                    Button { editor.tool = tool } label: {
                        HStack(alignment: .center, spacing: 9) {
                            Image(systemName: tool.icon).frame(width: 20).foregroundStyle(teal)
                            Text(tool.title)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 7)
                        .background(RoundedRectangle(cornerRadius: 7).fill(active ? teal.opacity(0.16) : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(editor.doc == nil)
                }
            }
            Spacer(minLength: 0)
            Divider()
            Button("Leere Leinwand") { editor.newBlank() }
        }
        .padding(16)
        .frame(width: 231)
        .frame(maxHeight: .infinity)
        .background(.quaternary.opacity(0.45))
    }

    // MARK: Kopf- und Fußzeile

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(editor.doc == nil ? "Foto bearbeiten" : editor.tool.title)
                    .font(.system(size: 26, weight: .semibold))
                Text(editor.doc == nil ? "Ein Foto öffnen oder mit einer leeren Leinwand beginnen" : editor.tool.subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { editor.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!editor.canUndo)
                .help("Rückgängig")
            Button { editor.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!editor.canRedo)
                .help("Wiederholen")
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Text(status).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Als JPG …") { editor.export(.jpeg) }
                .disabled(editor.doc == nil)
            Button("Bild exportieren …") { editor.export(.png) }
                .buttonStyle(.borderedProminent)
                .tint(teal)
                .disabled(editor.doc == nil)
        }
        .padding(14)
    }

    private var status: String {
        guard let doc = editor.doc else { return "Kein Bild geöffnet" }
        let objects = doc.layers.count
        return "\(doc.base.width) × \(doc.base.height) Pixel · \(objects) \(objects == 1 ? "Ebene" : "Ebenen")"
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(teal.opacity(dropTargeted ? 1 : 0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            VStack(spacing: 14) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 38, weight: .light)).foregroundStyle(teal)
                Text("Foto hierher ziehen").font(.title3.weight(.semibold))
                Button("Datei auswählen …") { editor.openPanel() }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
