import CoreImage
import Foundation

/// Regler eines Looks, jeweils -100 … 100 (fade/sepia 0 … 100).
struct Look {
    var brightness = 0.0
    var contrast = 0.0
    var saturation = 0.0
    var warmth = 0.0
    var fade = 0.0
    var sepia = 0.0
}

/// Farbkorrektur als 3x4-Matrix (Zeilen R, G, B; Spalten R, G, B, Versatz in 0 … 255).
/// Alle Regler und Filter sind linear und lassen sich so zu einer einzigen Matrix verrechnen.
struct ColorMatrix {
    var v: [Double]

    static let identity = ColorMatrix(v: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0])
    private static let sepia: [Double] = [0.393, 0.769, 0.189, 0, 0.349, 0.686, 0.168, 0, 0.272, 0.534, 0.131, 0]

    /// self ∘ b: zuerst b anwenden, dann self.
    func after(_ b: ColorMatrix) -> ColorMatrix {
        var o = [Double](repeating: 0, count: 12)
        for r in 0..<3 {
            for c in 0..<4 {
                var x = v[r * 4] * b.v[c] + v[r * 4 + 1] * b.v[4 + c] + v[r * 4 + 2] * b.v[8 + c]
                if c == 3 { x += v[r * 4 + 3] }
                o[r * 4 + c] = x
            }
        }
        return ColorMatrix(v: o)
    }

    var isIdentity: Bool {
        for i in 0..<12 where abs(v[i] - ColorMatrix.identity.v[i]) > 1e-6 { return false }
        return true
    }

    init(v: [Double]) {
        self.v = v
    }

    init(look q: Look) {
        var m = ColorMatrix.identity
        if q.saturation != 0 {
            let s = 1 + q.saturation / 100
            let lr = 0.2126 * (1 - s)
            let lg = 0.7152 * (1 - s)
            let lb = 0.0722 * (1 - s)
            m = ColorMatrix(v: [lr + s, lg, lb, 0, lr, lg + s, lb, 0, lr, lg, lb + s, 0]).after(m)
        }
        if q.sepia != 0 {
            let a = q.sepia / 100
            var s = ColorMatrix.identity.v
            for i in 0..<12 { s[i] += (ColorMatrix.sepia[i] - s[i]) * a }
            m = ColorMatrix(v: s).after(m)
        }
        if q.warmth != 0 {
            let w = q.warmth / 100
            m = ColorMatrix(v: [1 + 0.18 * w, 0, 0, 0, 0, 1 + 0.03 * w, 0, 0, 0, 0, 1 - 0.18 * w, 0]).after(m)
        }
        if q.contrast != 0 {
            let c = q.contrast / 100
            let f = c >= 0 ? 1 + c : 1 + c * 0.7
            let o = 128 * (1 - f)
            m = ColorMatrix(v: [f, 0, 0, o, 0, f, 0, o, 0, 0, f, o]).after(m)
        }
        if q.brightness != 0 {
            let o = q.brightness * 0.9
            m = ColorMatrix(v: [1, 0, 0, o, 0, 1, 0, o, 0, 0, 1, o]).after(m)
        }
        if q.fade != 0 {
            let f = q.fade / 100
            let k = 1 - 0.28 * f
            let o = 56 * f
            m = ColorMatrix(v: [k, 0, 0, o, 0, k, 0, o, 0, 0, k, o]).after(m)
        }
        self = m
    }

    func apply(to image: CIImage) -> CIImage {
        if isIdentity { return image }
        guard let filter = CIFilter(name: "CIColorMatrix") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: v[0], y: v[1], z: v[2], w: 0), forKey: "inputRVector")
        filter.setValue(CIVector(x: v[4], y: v[5], z: v[6], w: 0), forKey: "inputGVector")
        filter.setValue(CIVector(x: v[8], y: v[9], z: v[10], w: 0), forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        filter.setValue(CIVector(x: v[3] / 255, y: v[7] / 255, z: v[11] / 255, w: 0), forKey: "inputBiasVector")
        return filter.outputImage ?? image
    }
}

struct Preset: Identifiable {
    let id: String
    let name: String
    let look: Look

    static let all: [Preset] = [
        Preset(id: "original", name: "Original", look: Look()),
        Preset(id: "klar", name: "Klar", look: Look(contrast: 15, saturation: 15)),
        Preset(id: "kraeftig", name: "Kräftig", look: Look(contrast: 20, saturation: 45)),
        Preset(id: "warm", name: "Warm", look: Look(saturation: 10, warmth: 35)),
        Preset(id: "kuehl", name: "Kühl", look: Look(warmth: -35)),
        Preset(id: "sanft", name: "Sanft", look: Look(brightness: 8, contrast: -20, warmth: 10, fade: 25)),
        Preset(id: "verblasst", name: "Verblasst", look: Look(saturation: -15, fade: 60)),
        Preset(id: "retro", name: "Retro", look: Look(contrast: 10, warmth: 15, fade: 35, sepia: 35)),
        Preset(id: "sepia", name: "Sepia", look: Look(fade: 15, sepia: 85)),
        Preset(id: "sw", name: "Schwarzweiß", look: Look(contrast: 15, saturation: -100)),
        Preset(id: "noir", name: "Noir", look: Look(brightness: -5, contrast: 45, saturation: -100)),
        Preset(id: "nacht", name: "Nacht", look: Look(brightness: -15, contrast: 25, saturation: -10, warmth: -25)),
    ]
}
