import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Hilfsfunktionen für Pixelbilder: laden, skalieren, drehen, Farbmatrix anwenden, speichern.
/// Alle Bilder liegen intern als 8-Bit-sRGB vor.
enum Bild {
    static let maxSide = 6000

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    /// Ohne Farbmanagement rechnen, damit die Matrix direkt auf den sRGB-Werten arbeitet.
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // "Thumbnail" in voller Größe: berücksichtigt die EXIF-Drehung und begrenzt riesige Bilder.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return redraw(image, width: image.width, height: image.height)
    }

    static func blank(width: Int, height: Int) -> CGImage? {
        guard let ctx = bitmap(width: width, height: height) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    static func scaled(_ image: CGImage, maxSide: Int) -> CGImage {
        let longest = max(image.width, image.height)
        if longest <= maxSide { return image }
        let s = Double(maxSide) / Double(longest)
        let w = max(1, Int((Double(image.width) * s).rounded()))
        let h = max(1, Int((Double(image.height) * s).rounded()))
        return redraw(image, width: w, height: h) ?? image
    }

    static func adjusted(_ image: CGImage, _ matrix: ColorMatrix) -> CGImage {
        if matrix.isIdentity { return image }
        return render(matrix.apply(to: CIImage(cgImage: image))) ?? image
    }

    static func rotated(_ image: CGImage, clockwise: Bool) -> CGImage? {
        render(CIImage(cgImage: image).oriented(clockwise ? .right : .left))
    }

    static func flipped(_ image: CGImage, horizontal: Bool) -> CGImage? {
        render(CIImage(cgImage: image).oriented(horizontal ? .upMirrored : .downMirrored))
    }

    /// Rechteck in Bildpixeln, Ursprung oben links.
    static func cropped(_ image: CGImage, to rect: CGRect) -> CGImage? {
        guard let part = image.cropping(to: rect) else { return nil }
        // Neu zeichnen, damit das Ergebnis nicht am großen Ursprungsbild hängt.
        return redraw(part, width: part.width, height: part.height)
    }

    static func write(_ image: CGImage, to url: URL, type: UTType) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            return false
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    private static func bitmap(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func redraw(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let ctx = bitmap(width: width, height: height) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    private static func render(_ image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: sRGB)
    }
}
