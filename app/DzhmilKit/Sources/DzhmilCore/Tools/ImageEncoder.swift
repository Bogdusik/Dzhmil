import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageEncoder {
    public enum EncodeError: Error { case context, destination }

    public static func fittedSize(width: Int, height: Int, maxSide: Int = 1568) -> (width: Int, height: Int) {
        let longest = max(width, height)
        guard longest > maxSide, longest > 0 else { return (width, height) }
        let scale = Double(maxSide) / Double(longest)
        return (Int((Double(width) * scale).rounded()), Int((Double(height) * scale).rounded()))
    }

    public static func jpegBase64(_ image: CGImage, maxSide: Int = 1568, quality: Double = 0.75) throws -> String {
        let size = fittedSize(width: image.width, height: image.height, maxSide: maxSide)
        var output = image
        if size.width != image.width || size.height != image.height {
            guard let ctx = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw EncodeError.context }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            guard let scaled = ctx.makeImage() else { throw EncodeError.context }
            output = scaled
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw EncodeError.destination }
        CGImageDestinationAddImage(dest, output, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw EncodeError.destination }
        return (data as Data).base64EncodedString()
    }
}
