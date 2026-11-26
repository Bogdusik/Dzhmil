#!/usr/bin/env swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(_ width: Int, _ height: Int, scale: CGFloat, to path: String, draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: Int(CGFloat(width) * scale), height: Int(CGFloat(height) * scale), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.translateBy(x: 0, y: CGFloat(height) * scale)
    ctx.scaleBy(x: scale, y: -scale)
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = NSSize(width: width, height: height)
    try! rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(path))
}

func fill(_ ctx: CGContext, _ path: CGPath, _ fill: CGColor) {
    ctx.addPath(path)
    ctx.setFillColor(fill)
    ctx.fillPath()
}

func rounded(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ paint: CGColor) {
    fill(ctx, CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: min(r, w / 2), cornerHeight: min(r, h / 2), transform: nil), paint)
}

func stroke(_ ctx: CGContext, _ points: [CGPoint], _ width: CGFloat, _ paint: CGColor) {
    ctx.addLines(between: points)
    ctx.setStrokeColor(paint)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
}

func gradient(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func glow(_ ctx: CGContext, at center: CGPoint, radius: CGFloat, _ hex: UInt32, _ alpha: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(hex, alpha), color(hex, 0)] as CFArray, locations: nil)!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

func honeycomb(_ ctx: CGContext, in area: CGRect, size: CGFloat, _ paint: CGColor, width: CGFloat, fade: (CGPoint) -> CGFloat) {
    let dx = size * 3.0.squareRoot(), dy = size * 1.5
    var row = 0
    var y = area.minY
    while y < area.maxY + size {
        var x = area.minX + (row % 2 == 0 ? 0 : dx / 2)
        while x < area.maxX + size {
            let alpha = fade(CGPoint(x: x, y: y))
            if alpha > 0.01 {
                let points = (0...6).map { i -> CGPoint in
                    let a = CGFloat(i) * .pi / 3 + .pi / 6
                    return CGPoint(x: x + cos(a) * size * 0.9, y: y + sin(a) * size * 0.9)
                }
                stroke(ctx, points, width, paint.copy(alpha: paint.alpha * alpha)!)
            }
            x += dx
        }
        y += dy
        row += 1
    }
}

func drone(_ ctx: CGContext, center: CGPoint, scale: CGFloat, tilt: CGFloat = 0, shadow: Bool = true) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: tilt)
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: -120, y: -93)
    if shadow {
        let unit = ctx.ctm.a.magnitude
        ctx.setShadow(offset: CGSize(width: 0, height: -7 * unit), blur: 12 * unit, color: color(0x5A3A00, 0.35))
    }
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    let frame = color(0x20343A)
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    func propeller(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ h: CGFloat, _ thick: CGFloat) {
        fill(ctx, CGPath(ellipseIn: CGRect(x: x - r, y: y - h / 2, width: r * 2, height: h), transform: nil), color(0x20343A, 0.2))
        ctx.addEllipse(in: CGRect(x: x - r * 0.99, y: y - h * 0.46, width: r * 1.98, height: h * 0.92))
        ctx.setStrokeColor(color(0xFFFFFF, 0.55))
        ctx.setLineWidth(1)
        ctx.strokePath()
        rounded(ctx, x - r, y - thick * 0.17, r * 2, thick * 0.34, thick * 0.17, frame)
        fill(ctx, CGPath(ellipseIn: CGRect(x: x - 3, y: y - 2.2, width: 6, height: 4.4), transform: nil), color(0x3C565E))
    }

    stroke(ctx, [p(96, 82), p(54, 56)], 8, frame)
    stroke(ctx, [p(144, 82), p(186, 56)], 8, frame)
    rounded(ctx, 47, 46, 14, 13, 3, frame)
    rounded(ctx, 179, 46, 14, 13, 3, frame)
    propeller(54, 44, 30, 18, 8)
    propeller(186, 44, 30, 18, 8)
    stroke(ctx, [p(150, 66), p(166, 40)], 3, frame)
    fill(ctx, CGPath(ellipseIn: CGRect(x: 161, y: 34, width: 10, height: 10), transform: nil), color(0xFFD23F))
    fill(ctx, CGPath(ellipseIn: CGRect(x: 163.2, y: 36, width: 3.4, height: 3.4), transform: nil), color(0xFFF6C8))
    stroke(ctx, [p(102, 136), p(96, 150)], 4, frame)
    stroke(ctx, [p(138, 136), p(144, 150)], 4, frame)

    rounded(ctx, 78, 66, 84, 62, 26, color(0x008C75))
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 78, y: 60, width: 84, height: 62), cornerWidth: 26, cornerHeight: 26, transform: nil))
    ctx.clip()
    gradient(ctx, [color(0x38EBC4), color(0x00D4AA), color(0x00B592)], from: p(96, 60), to: p(140, 124))
    ctx.restoreGState()
    rounded(ctx, 96, 65, 30, 5, 2.5, color(0xD6FFF4, 0.85))
    rounded(ctx, 87, 76, 66, 34, 15, color(0x0A1B20))
    rounded(ctx, 94, 123, 52, 17, 5, frame)
    rounded(ctx, 111, 123, 18, 8.5, 0, color(0x2B6FE0))
    rounded(ctx, 111, 131.5, 18, 8.5, 0, color(0xFFD23F))

    for x: CGFloat in [101, 129] {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 6 * ctx.ctm.a.magnitude, color: color(0x8CFFE4, 0.9))
        rounded(ctx, x, 84, 10, 14, 5, color(0x8CFFE4))
        ctx.restoreGState()
        fill(ctx, CGPath(ellipseIn: CGRect(x: x + 2, y: 86, width: 3.6, height: 3.6), transform: nil), color(0xFFFFFF))
    }

    stroke(ctx, [p(92, 108), p(40, 122)], 10, frame)
    stroke(ctx, [p(148, 108), p(200, 122)], 10, frame)
    rounded(ctx, 31, 107, 18, 17, 4, frame)
    rounded(ctx, 191, 107, 18, 17, 4, frame)
    propeller(40, 104, 38, 22, 10)
    propeller(200, 104, 38, 22, 10)
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

func icon(_ ctx: CGContext) {
    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    let unit = ctx.ctm.a.magnitude
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * unit), blur: 28 * unit, color: color(0x000000, 0.3))
    fill(ctx, tile, color(0xFFC233))
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    gradient(ctx, [color(0xFFF0A8), color(0xFFD04A), color(0xFF9F1C)], from: CGPoint(x: 260, y: 100), to: CGPoint(x: 760, y: 924))
    honeycomb(ctx, in: CGRect(x: 100, y: 100, width: 824, height: 824), size: 64, color(0xFFFFFF, 0.55), width: 5) { p in
        max(0, min(1, (hypot(p.x - 512, p.y - 500) - 230) / 300))
    }
    glow(ctx, at: CGPoint(x: 512, y: 470), radius: 430, 0xFFFFFF, 0.8)
    fill(ctx, CGPath(ellipseIn: CGRect(x: 342, y: 748, width: 340, height: 46), transform: nil), color(0x8A4B00, 0.16))
    drone(ctx, center: CGPoint(x: 512, y: 500), scale: 3.12, tilt: -0.07)
    ctx.restoreGState()
    ctx.addPath(tile)
    ctx.setStrokeColor(color(0xFFFFFF, 0.45))
    ctx.setLineWidth(3)
    ctx.strokePath()
}

func text(_ ctx: CGContext, _ s: String, centerX: CGFloat, baseline: CGFloat, size: CGFloat, weight: NSFont.Weight, _ paint: CGColor, rounded design: Bool = true) {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    let font = design ? base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base : base
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor(cgColor: paint)!]))
    let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    ctx.saveGState()
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    ctx.textPosition = CGPoint(x: centerX - width / 2, y: baseline)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

func installer(_ ctx: CGContext) {
    gradient(ctx, [color(0xE4F8FF), color(0xFFF8E1), color(0xFFE59A)], from: CGPoint(x: 120, y: 0), to: CGPoint(x: 520, y: 400))
    honeycomb(ctx, in: CGRect(x: 0, y: 0, width: 1000, height: 520), size: 22, color(0xF2A900, 0.34), width: 1.4) { p in
        max(0, min(1, (hypot(p.x - 660, p.y - 400) * -1 + 330) / 220)) + max(0, min(1, (230 - hypot(p.x, p.y)) / 170)) * 0.6
    }
    for x: CGFloat in [170, 490] { glow(ctx, at: CGPoint(x: x, y: 205), radius: 130, 0xFFFFFF, 0.95) }

    text(ctx, "Dzhmil", centerX: 330, baseline: 52, size: 32, weight: .heavy, color(0x14343C))
    text(ctx, "Drag the drone onto Applications", centerX: 330, baseline: 77, size: 14, weight: .medium, color(0x4E6B72))

    let start = CGPoint(x: 246, y: 200), end = CGPoint(x: 410, y: 200)
    let c1 = CGPoint(x: 282, y: 122), c2 = CGPoint(x: 374, y: 122)
    ctx.saveGState()
    ctx.move(to: start)
    ctx.addCurve(to: end, control1: c1, control2: c2)
    ctx.setStrokeColor(color(0x00A98A))
    ctx.setLineWidth(3.5)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [2, 10])
    ctx.strokePath()
    ctx.restoreGState()
    let angle = atan2(end.y - c2.y, end.x - c2.x)
    stroke(ctx, [CGPoint(x: end.x - 13 * cos(angle - 0.6), y: end.y - 13 * sin(angle - 0.6)), end,
                 CGPoint(x: end.x - 13 * cos(angle + 0.6), y: end.y - 13 * sin(angle + 0.6))], 3.5, color(0x00A98A))
    drone(ctx, center: CGPoint(x: 328, y: 130), scale: 0.34, tilt: 0.12)

    rounded(ctx, 96, 322, 468, 48, 14, color(0xFFFFFF, 0.78))
    text(ctx, "First launch: if macOS blocks it, open System Settings → Privacy & Security", centerX: 330, baseline: 342, size: 11.5, weight: .medium, color(0x35535A), rounded: false)
    text(ctx, "and click Open Anyway. If asked about the saved key, click Always Allow.", centerX: 330, baseline: 359, size: 11.5, weight: .medium, color(0x35535A), rounded: false)
}

let set = "app/Dzhmil/Assets.xcassets/AppIcon.appiconset"
var images: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)@\(scale)x.png"
        render(1024, 1024, scale: CGFloat(points * scale) / 1024, to: "\(set)/\(name)", draw: icon)
        images.append("    { \"idiom\" : \"mac\", \"size\" : \"\(points)x\(points)\", \"scale\" : \"\(scale)x\", \"filename\" : \"\(name)\" }")
    }
}
let info = "  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }"
try! "{\n  \"images\" : [\n\(images.joined(separator: ",\n"))\n  ],\n\(info)\n}\n".write(to: root.appendingPathComponent("\(set)/Contents.json"), atomically: true, encoding: .utf8)
try! "{\n\(info)\n}\n".write(to: root.appendingPathComponent("app/Dzhmil/Assets.xcassets/Contents.json"), atomically: true, encoding: .utf8)
render(1000, 520, scale: 1, to: "scripts/dmg/background.png", draw: installer)
render(1000, 520, scale: 2, to: "scripts/dmg/background@2x.png", draw: installer)
