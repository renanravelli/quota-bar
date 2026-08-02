import AppKit
import QuotaBarCore
import SwiftUI

struct Raster {
    let widthInPixels: Int
    let heightInPixels: Int

    private let channels: [UInt8]

    fileprivate init?(image: CGImage) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        widthInPixels = width
        heightInPixels = height
        channels = buffer
    }

    private func color(atX x: Int, y: Int) -> QuotaBarCore.RGBColor {
        let start = (y * widthInPixels + x) * 4
        return QuotaBarCore.RGBColor(
            red: Double(channels[start]) / 255,
            green: Double(channels[start + 1]) / 255,
            blue: Double(channels[start + 2]) / 255
        )
    }

    private func luminance(atX x: Int, y: Int) -> Double {
        Contrast.relativeLuminance(color(atX: x, y: y))
    }

    func contrastRatio(of foreground: CGRect, against background: CGRect) -> Double {
        let surface = meanLuminance(in: background)
        let ink = luminances(in: foreground).max(by: { distance($0, surface) < distance($1, surface) }) ?? surface

        return (max(ink, surface) + 0.05) / (min(ink, surface) + 0.05)
    }

    private func meanLuminance(in region: CGRect) -> Double {
        let sampled = luminances(in: region)
        guard !sampled.isEmpty else { return 0 }

        return sampled.reduce(0, +) / Double(sampled.count)
    }

    private func luminances(in region: CGRect) -> [Double] {
        let horizontal = max(Int(region.minX), 0)..<min(Int(region.maxX), widthInPixels)
        let vertical = max(Int(region.minY), 0)..<min(Int(region.maxY), heightInPixels)

        return vertical.flatMap { y in horizontal.map { x in luminance(atX: x, y: y) } }
    }

    private func distance(_ first: Double, _ second: Double) -> Double {
        abs(first - second)
    }
}

@MainActor
enum RenderedProbe {
    struct Environment {
        let font: Font
        let scale: CGFloat

        static let smallerMetric = Environment(font: .system(size: 13), scale: 2)
        static let largerMetric = Environment(font: .system(size: 26), scale: 2)
    }

    static func raster(_ view: some View, in environment: Environment) -> Raster? {
        let renderer = ImageRenderer(content: view.environment(\.font, environment.font).fixedSize())
        renderer.scale = environment.scale

        guard let image = renderer.cgImage else { return nil }

        return Raster(image: image)
    }

    static func layoutFrame(of view: some View, in environment: Environment) -> CGRect {
        let host = NSHostingView(rootView: view.environment(\.font, environment.font))
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 600, height: 400)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        let frame = CGRect(origin: .zero, size: host.fittingSize)
        window.contentView = nil
        window.close()

        return frame
    }
}
