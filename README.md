# Fotowerk

Ein Foto-Editor für macOS (Apple Silicon, macOS 14+), geschrieben in Swift/SwiftUI. Alle Bilder werden lokal verarbeitet.

## Funktionen

- Foto öffnen (⌘O oder Drag & Drop) oder mit leerer Leinwand starten (⌘N)
- Zuschneiden (frei oder festes Seitenverhältnis), drehen, spiegeln
- Anpassen: Helligkeit, Kontrast, Sättigung, Wärme, Verblassen, Vignette
- Filter mit Vorschaubildern
- Text (Farbe, Schrift, Größe, Fett, Kontur) und Sticker als verschieb-, skalier- und drehbare Ebenen
- Pinsel zum freien Malen
- Widerrufen / Wiederholen (⌘Z / ⇧⌘Z)
- Export als PNG (⌘E) oder JPG (⇧⌘E) in voller Auflösung

## Bauen

```sh
./Quellcode/build.sh
open Fotowerk.app
```

Kein Xcode-Projekt – `build.sh` ruft `swiftc` direkt auf (die Xcode Command Line Tools genügen). Neue `.swift`-Dateien in `Quellcode/` werden automatisch mitgebaut.

## Aufbau

- `App.swift` – App, Menübefehle, Hauptfenster, Startseite
- `Editor.swift` – Zustand: Dokument, Verlauf, Auswahl, Werkzeug, Export
- `Dokument.swift` – Datenmodell (Ebenen, Bearbeitungsstand), Drehen/Spiegeln/Zuschneiden
- `Stage.swift` – Leinwand mit Maus-Bedienung
- `Panels.swift` – Seitenleiste mit den Bedienfeldern der Werkzeuge
- `Zeichnen.swift` – Zeichnen des Dokuments für Vorschau und Export
- `Farbe.swift` – Farbmatrix für Regler und Filter
- `Bild.swift` – Laden, Skalieren und Speichern von Bildern
