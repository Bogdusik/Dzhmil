import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import DzhmilCore

func solidImage(_ w: Int, _ h: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0, green: 0.8, blue: 0.6, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

@Suite struct ImageEncoderTests {
    @Test func fittedSizeScalesDownLongSide() {
        let s = ImageEncoder.fittedSize(width: 3000, height: 2000)
        #expect(s.width == 1568 && s.height == 1045)
    }

    @Test func fittedSizeHandles5K() {
        let s = ImageEncoder.fittedSize(width: 5120, height: 2880)
        #expect(s.width == 1568 && s.height == 882)
    }

    @Test func fittedSizeKeepsSmallImages() {
        let s = ImageEncoder.fittedSize(width: 800, height: 600)
        #expect(s.width == 800 && s.height == 600)
    }

    @Test func jpegIsValidAndFitted() throws {
        let b64 = try ImageEncoder.jpegBase64(solidImage(2000, 1000))
        let data = try #require(Data(base64Encoded: b64))
        #expect(data.prefix(2) == Data([0xFF, 0xD8]))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 1568 && decoded.height == 784)
    }
}
