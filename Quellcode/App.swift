import SwiftUI
import UniformTypeIdentifiers

@main
@MainActor
struct FotowerkApp: App {
    @StateObject private var editor = Editor()

    var body: some Scene {
        Window("Fotowerk", id: "main") {
            ContentView(editor: editor)
                .frame(minWidth: 900, minHeight: 600)
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

@MainActor
struct ContentView: View {
    @ObservedObject var editor: Editor
    @State private var dropTargeted = false

    var body: some View {
        Group {
            if editor.doc == nil {
                welcome
            } else {
                HStack(spacing: 0) {
                    StageView(editor: editor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .underPageBackgroundColor))
                    Divider()
                    InspectorView(editor: editor)
                        .frame(width: 300)
                }
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            editor.open(url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { editor.openPanel() } label: { Label("Öffnen", systemImage: "photo.on.rectangle") }
                    .help("Foto öffnen (⌘O)")
            }
            ToolbarItemGroup {
                Button { editor.undo() } label: { Label("Widerrufen", systemImage: "arrow.uturn.backward") }
                    .disabled(!editor.canUndo)
                    .help("Widerrufen (⌘Z)")
                Button { editor.redo() } label: { Label("Wiederholen", systemImage: "arrow.uturn.forward") }
                    .disabled(!editor.canRedo)
                    .help("Wiederholen (⇧⌘Z)")
                Menu {
                    Button("Als PNG …") { editor.export(.png) }
                    Button("Als JPG …") { editor.export(.jpeg) }
                } label: {
                    Label("Exportieren", systemImage: "square.and.arrow.up")
                }
                .disabled(editor.doc == nil)
                .help("Bild exportieren (⌘E)")
            }
        }
        .alert(
            "Fotowerk",
            isPresented: Binding(get: { editor.errorText != nil }, set: { if !$0 { editor.errorText = nil } })
        ) {
            Button("OK") { editor.errorText = nil }
        } message: {
            Text(editor.errorText ?? "")
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.artframe")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            Text("Fotowerk").font(.largeTitle.bold())
            Text("Fotos zuschneiden, anpassen und mit Text, Stickern und Pinsel gestalten.\nAlles bleibt auf deinem Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                Button("Foto öffnen …") { editor.openPanel() }
                    .buttonStyle(.borderedProminent)
                Button("Leere Leinwand") { editor.newBlank() }
            }
            .controlSize(.large)
            Text("… oder ein Bild in dieses Fenster ziehen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
